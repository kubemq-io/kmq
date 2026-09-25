#!/bin/sh
# install.sh — Install the kmq CLI (zero credentials).
#
# Primary (GitHub Releases):
#   curl -sSfL https://raw.githubusercontent.com/kubemq-io/kmq/main/install.sh | sh
#   curl -sSfL .../install.sh | sh -s -- --version v1.2.3
#   curl -sSfL .../install.sh | sh -s -- --verify-signature
# Mirror (GCS) / staging:
#   KMQ_BASE_URL=https://storage.googleapis.com/storage.kubemq.io curl -sSfL .../install.sh | sh
#
# Env: KMQ_VERSION, KMQ_INSTALL_DIR, KMQ_BASE_URL, KMQ_PREFIX, KMQ_VERIFY_SIGNATURE=1
# POSIX sh — no bashisms.
set -eu

GH_REPO="kubemq-io/kmq"
GH_BASE="https://github.com/${GH_REPO}"
ARCHIVE_BASE="kmq"                       # goreleaser ProjectName — archive base is ALWAYS kmq
VERSION="${KMQ_VERSION:-}"
INSTALL_DIR="${KMQ_INSTALL_DIR:-}"
BASE_URL="${KMQ_BASE_URL:-}"             # set → GCS mirror/staging mode
PREFIX="${KMQ_PREFIX:-kmq}"              # GCS object prefix; staging verify sets KMQ_PREFIX=kmq/staging
VERIFY_SIG="${KMQ_VERIFY_SIGNATURE:-}"   # non-empty → strict cosign
# Release signing key fingerprint. A replacement key requires an intentional
# installer update; a key downloaded alongside a release is not its own trust root.
TRUSTED_COSIGN_PUB_SHA256="b8792764c60e86a21aa0aed6b34e964ea5cf180c3654a043dbd9e4355a1410fe"

while [ $# -gt 0 ]; do
  case "$1" in
    --version)          [ $# -ge 2 ] && [ -n "$2" ] || { echo "--version requires a release tag" >&2; exit 2; }; VERSION="$2"; shift 2 ;;
    --install-dir)      [ $# -ge 2 ] && [ -n "$2" ] || { echo "--install-dir requires a path" >&2; exit 2; }; INSTALL_DIR="$2"; shift 2 ;;
    --verify-signature) VERIFY_SIG=1; shift ;;
    --help|-h) echo "Usage: $0 [--version vX.Y.Z] [--install-dir /path] [--verify-signature]"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

# Bound every release request, including retries. A failed upgrade must leave the
# existing executable intact instead of waiting forever on a stalled transfer.
fetch() { curl -fsSL --retry 3 --retry-delay 1 --retry-max-time 60 --connect-timeout 10 --max-time 30 "$@"; }

# ---- normalize version to a single leading v ----
norm_ver() { case "$1" in v*) printf '%s' "$1" ;; *) printf 'v%s' "$1" ;; esac; }
[ -n "$VERSION" ] && VERSION=$(norm_ver "$VERSION")

# ---- detect OS / arch (unchanged logic) ----
os=$(uname -s | tr '[:upper:]' '[:lower:]'); arch=$(uname -m)
case "$os" in
  linux) os_name=linux ;; darwin) os_name=darwin ;;
  mingw*|msys*|cygwin*|windows*) os_name=windows ;;
  *) echo "Unsupported OS: $os" >&2; exit 1 ;;
esac
case "$arch" in
  x86_64|amd64) arch_name=amd64 ;; arm64|aarch64) arch_name=arm64 ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
ext=tar.gz; bin_name="kmq"
if [ "$os_name" = windows ]; then ext=zip; bin_name="kmq.exe"; fi
archive="${ARCHIVE_BASE}_${os_name}_${arch_name}.${ext}"   # GAP-R1-1: base is kmq, not kmq.exe

# ---- resolve version + URLs ----
if [ -n "$BASE_URL" ]; then
  # GCS mirror / staging mode (PREFIX = kmq for the mirror, kmq/staging for staging verify)
  if [ -z "$VERSION" ]; then
    VERSION=$(fetch "${BASE_URL}/${PREFIX}/stable.txt" | tr -d '[:space:]' || true)
    [ -n "$VERSION" ] || { echo "Could not determine latest version from ${BASE_URL}/${PREFIX}/stable.txt. Use --version." >&2; exit 1; }
  fi
  ver_base="${BASE_URL}/${PREFIX}/${VERSION}"
else
  # GitHub Releases mode (default)
  if [ -z "$VERSION" ]; then
    # resolve 'latest' via the redirect endpoint (no rate-limited API)
    eff=$(fetch -I -o /dev/null -w '%{url_effective}' "${GH_BASE}/releases/latest" 2>/dev/null || true)
    VERSION=$(printf '%s' "$eff" | sed -n 's#.*/releases/tag/\(v[^/]*\)$#\1#p')
    [ -n "$VERSION" ] || { echo "Could not determine latest version (no published release yet?). Use --version." >&2; exit 1; }
  fi
  ver_base="${GH_BASE}/releases/download/${VERSION}"
fi
archive_url="${ver_base}/${archive}"
checksum_url="${ver_base}/checksums.txt"
sig_url="${ver_base}/checksums.txt.sig"
pub_url="${ver_base}/cosign.pub"

echo "Installing kmq ${VERSION} (${os_name}/${arch_name})..."

tmp_dir=$(mktemp -d)
stage=''
trap 'rm -rf "$tmp_dir"; [ -z "$stage" ] || rm -f "$stage"' EXIT
trap 'exit 130' INT TERM
echo "Downloading ${archive_url}..."
fetch -o "${tmp_dir}/${archive}" "$archive_url"
fetch -o "${tmp_dir}/checksums.txt" "$checksum_url"

# ---- MANDATORY checksum verification (abort if no tool) ----
( cd "$tmp_dir"
  match_count=$(awk -v name="$archive" '$2 == name { count++ } END { print count+0 }' checksums.txt)
  [ "$match_count" -eq 1 ] || { echo "checksums.txt does not contain exactly one entry for ${archive} (found ${match_count:-0}); aborting." >&2; exit 1; }
  awk -v name="$archive" '$2 == name { print }' checksums.txt > selected-checksum.txt
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c selected-checksum.txt
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c selected-checksum.txt
  else
    echo "sha256sum/shasum required to verify the download but neither was found." >&2; exit 1
  fi )

# ---- cosign verification (best-effort; strict on demand) ----
if command -v cosign >/dev/null 2>&1; then
  if fetch -o "${tmp_dir}/checksums.txt.sig" "$sig_url" \
     && fetch -o "${tmp_dir}/cosign.pub" "$pub_url"; then
    if command -v sha256sum >/dev/null 2>&1; then
      key_hash=$(sha256sum "${tmp_dir}/cosign.pub" | awk '{print $1}')
    else
      key_hash=$(shasum -a 256 "${tmp_dir}/cosign.pub" | awk '{print $1}')
    fi
    [ "$key_hash" = "$TRUSTED_COSIGN_PUB_SHA256" ] || { echo "Release signing key differs from the pinned kmq trust root; aborting." >&2; exit 1; }
    if ! ( cd "$tmp_dir" && cosign verify-blob --key cosign.pub --signature checksums.txt.sig checksums.txt ); then
      echo "cosign signature verification failed." >&2; exit 1
    fi
    echo "cosign signature verified."
  elif [ -n "$VERIFY_SIG" ]; then
    echo "--verify-signature requested but the signature/public key could not be fetched." >&2; exit 1
  else
    echo "Note: signature/public key not available; skipping cosign verification (checksum verified)." >&2
  fi
elif [ -n "$VERIFY_SIG" ]; then
  echo "cosign is required for --verify-signature but was not found on PATH." >&2; exit 1
else
  echo "Note: cosign not found; skipping signature verification (checksum verified)." >&2
fi

# ---- extract (unchanged logic) ----
if [ "$ext" = tar.gz ]; then
  tar -xzf "${tmp_dir}/${archive}" -C "$tmp_dir" "$bin_name"
elif command -v unzip >/dev/null 2>&1; then
  unzip -q "${tmp_dir}/${archive}" "$bin_name" -d "$tmp_dir"
elif command -v python3 >/dev/null 2>&1; then
  python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract(sys.argv[3],sys.argv[2])" "${tmp_dir}/${archive}" "$tmp_dir" "$bin_name"
else
  echo "Cannot extract zip: install unzip or python3." >&2; exit 1
fi
extracted="${tmp_dir}/${bin_name}"
[ -f "$extracted" ] || { echo "Extraction failed: ${extracted} not found." >&2; exit 1; }
chmod +x "$extracted"

# ---- install dir + install + PATH hint (unchanged logic) ----
if [ -z "$INSTALL_DIR" ]; then
  if [ -w /usr/local/bin ]; then INSTALL_DIR=/usr/local/bin
  elif [ -w "${HOME}/.local/bin" ]; then INSTALL_DIR="${HOME}/.local/bin"
  else INSTALL_DIR="${HOME}/bin"; fi
fi
mkdir -p "$INSTALL_DIR"
dest="${INSTALL_DIR}/${bin_name}"
[ ! -d "$dest" ] || { echo "Install destination is a directory: $dest" >&2; exit 1; }
stage=$(mktemp "${INSTALL_DIR}/.${bin_name}.XXXXXX")
install -m 755 "$extracted" "$stage"
mv -f "$stage" "$dest"
stage=''
echo ""
echo "kmq ${VERSION} installed to ${INSTALL_DIR}/${bin_name}"
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) : ;;
  *) echo ""; echo "Note: ${INSTALL_DIR} is not in your PATH."; echo "  export PATH=\"${INSTALL_DIR}:\$PATH\"" ;;
esac
echo ""; echo "Run 'kmq version' to verify."; echo "Run 'kmq --help' for usage."
echo ""
echo "Teach your AI agent to use kmq:"
echo "  kmq skills install                 # Claude Code + AGENTS.md (this dir)"
echo "  npx skills add kubemq-io/kmq        # any of 70+ agents"
