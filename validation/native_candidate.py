"""Black-box native candidate qualification. No private server source required.

Runs only against explicitly staged, signed release bytes. Uses synthetic local
credentials and a loopback trial gateway. Never uploads stores, keys, or logs.
"""
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / "validation" / "native-report.json"
report = {"status": "failed", "checks": [], "runtime": platform.platform()}
secret = "kmq-synthetic-" + uuid.uuid4().hex
session_secret = "synthetic-session-" + uuid.uuid4().hex
binary = None


def check(condition, description):
    if not condition:
        raise RuntimeError(description)
    report["checks"].append(description)


def call(args, *, input=None, env=None, success=True, timeout=45):
    p = subprocess.run(args, input=input, text=True, capture_output=True,
                       timeout=timeout, env=env)
    # Captured command output is intentionally never written to workflow logs.
    check(secret not in p.stdout + p.stderr and session_secret not in p.stdout + p.stderr,
          "command output redacts synthetic credentials")
    if (p.returncode == 0) != success:
        report["failed_command"] = [Path(str(args[0])).name, *[str(a) for a in args[1:3]]]
        report["exit_code"] = p.returncode
        if os.name == "nt" and "--credential-dir" in args:
            directory = str(args[args.index("--credential-dir") + 1])
            script = r'''$p=$args[0];$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$paths=@($p,(Join-Path $p 'native'),(Join-Path $p 'file'));$paths|ForEach-Object {if(Test-Path -LiteralPath $_){$a=Get-Acl -LiteralPath $_;@{kind=(Split-Path $_ -Leaf);owner_matches=($a.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq $sid);protected=$a.AreAccessRulesProtected;rules=@($a.Access).Count}}}|ConvertTo-Json -Compress'''
            with tempfile.TemporaryDirectory(prefix="kmq-diagnostic-") as temp:
                diagnostic = Path(temp) / "acl.ps1"
                diagnostic.write_text(script)
                probe = subprocess.run(["pwsh", "-NoProfile", "-File", str(diagnostic), directory], text=True, capture_output=True)
                if probe.returncode == 0 and probe.stdout.strip():
                    report["directory_access"] = json.loads(probe.stdout)
    check((p.returncode == 0) == success, "command exit matches expected outcome")
    return p


def kmq(*args, **kwargs):
    return call([str(binary), *args], **kwargs)


def powershell(script, *args):
    with tempfile.TemporaryDirectory(prefix="kmq-acl-script-") as directory:
        path = Path(directory) / "access.ps1"
        path.write_text(script)
        return call(["pwsh", "-NoProfile", "-NonInteractive", "-File", str(path), *args])


def protect(path):
    if os.name != "nt":
        path.chmod(0o700 if path.is_dir() else 0o600)
        return
    script = r'''
$p=$args[0]; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=Get-Acl -LiteralPath $p
$acl.SetAccessRuleProtection($true,$false)
foreach($rule in @($acl.Access)) { [void]$acl.RemoveAccessRuleSpecific($rule) }
$acl.SetOwner($sid)
$rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')
$acl.AddAccessRule($rule); Set-Acl -LiteralPath $p -AclObject $acl
'''
    powershell(script, str(path))


def fetch(url, target):
    with urllib.request.urlopen(url, timeout=30) as response:
        target.write_bytes(response.read())


class Gateway(http.server.BaseHTTPRequestHandler):
    state = "pending_email"
    acknowledged = False
    exhausted = False
    calls = 0

    def log_message(self, *_):
        pass

    def reply(self, data, status=200):
        raw = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        check(self.headers.get("Authorization") == "Bearer " + session_secret,
              "saved receiving session binds authenticated status")
        self.reply({"request_id": "native-candidate-request", "state": self.state,
                    "expires_at": int(time.time()) + 600})

    def do_POST(self):
        Gateway.calls += 1
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        if self.path == "/requests":
            check("registration_source" not in body, "native client cannot override registration source")
            self.reply({"request_id": "native-candidate-request", "session_token": session_secret,
                        "state": self.state, "expires_at": int(time.time()) + 600})
            return
        check(self.headers.get("Authorization") == "Bearer " + session_secret,
              "receiving session authorizes only its subsequent operations")
        if self.path.endswith("/verify"):
            check(body == {"code": "12345678"}, "email proof arrives through protected input")
            Gateway.state = "credential_ready"
            self.reply({"request_id": "native-candidate-request", "state": self.state})
        elif self.path.endswith("/claim"):
            self.reply({"request_id": "native-candidate-request", "state": "credential_ready",
                        "license_id": "synthetic-license", "license_key": secret,
                        "license_expires_at": "2099-01-01T00:00:00Z", "key_version": 1})
        elif self.path.endswith("/ack"):
            check(body == {"key_version": 1}, "client acknowledges exact saved credential generation")
            Gateway.acknowledged = True
            Gateway.state = "completed"
            self.reply({"request_id": "native-candidate-request", "state": self.state})
        elif self.path.endswith("/resume"):
            self.reply({"request_id": "native-candidate-request", "state": "failed",
                        "error": {"code": "retry_budget_exhausted", "retryable": False}}, 409)
        else:
            self.reply({"state": "failed", "error": {"code": "unknown_request", "retryable": False}}, 404)


def run():
    global binary
    version = os.environ["KMQ_VERSION"]
    prefix = os.environ["KMQ_PREFIX"]
    expected_checksums = os.environ["KMQ_CANDIDATE_CHECKSUMS_SHA256"]
    check(re.fullmatch(r"v\d+\.\d+\.\d+(?:[.-][0-9A-Za-z.-]+)?", version) is not None,
          "candidate version is explicit and bounded")
    check(prefix.startswith("kmq/staging/") and re.fullmatch(r"[A-Za-z0-9/_-]+", prefix) is not None,
          "candidate prefix cannot address default release pointers")
    check(re.fullmatch(r"[a-f0-9]{64}", expected_checksums) is not None,
          "trusted checksum manifest digest supplied")
    actual_platform = {"Windows": "windows", "Darwin": "darwin", "Linux": "linux"}[platform.system()]
    actual_arch = {"AMD64": "amd64", "x86_64": "amd64", "aarch64": "arm64", "arm64": "arm64"}[platform.machine()]
    check(actual_platform == os.environ["KMQ_EXPECTED_PLATFORM"] and actual_arch == os.environ["KMQ_EXPECTED_ARCH"],
          "runner executes the advertised native architecture")
    report.update(version=version, platform=actual_platform, architecture=actual_arch,
                  checksums_sha256=expected_checksums)
    with tempfile.TemporaryDirectory(prefix="kmq-native-") as temporary:
        root = Path(temporary)
        protect(root)
        checksums = root / "checksums.txt"
        base = os.environ["KMQ_BASE_URL"] + "/" + prefix + "/" + version
        fetch(base + "/checksums.txt", checksums)
        check(hashlib.sha256(checksums.read_bytes()).hexdigest() == expected_checksums,
              "candidate manifest matches independently supplied digest")
        install = root / "bin"
        env = os.environ.copy()
        env["KMQ_INSTALL_DIR"] = str(install)
        env["KMQ_VERIFY_SIGNATURE"] = "1"
        if os.name == "nt":
            call(["pwsh", "-NoProfile", "-File", str(ROOT / "install.ps1"),
                  "-Version", version, "-InstallDir", str(install), "-VerifySignature"], env=env, timeout=180)
            binary = install / "kmq.exe"
        else:
            call(["sh", str(ROOT / "install.sh"), "--version", version,
                  "--install-dir", str(install), "--verify-signature"], env=env, timeout=180)
            binary = install / "kmq"
        check(json.loads(kmq("version").stdout)["version"] == version, "installed executable reports candidate version")
        report["executable_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
        schema = kmq("schema").stdout
        check(all(word in schema for word in ["trial", "claim", "deploy", "auth", "fingerprint"]),
              "installed command schema contains onboarding surface")
        check("Identified deployment plans" in kmq("skills", "get", "core").stdout,
              "installed embedded skill matches candidate commands")
        keychain = None
        if actual_platform == "darwin":
            keychain = root / "candidate.keychain-db"
            password = uuid.uuid4().hex
            # Security's interactive stdin keeps even disposable keychain
            # passwords out of process arguments and workflow output.
            setup = f'create-keychain -p {password} "{keychain}"\nunlock-keychain -p {password} "{keychain}"\ndefault-keychain -d user -s "{keychain}"\nlist-keychains -d user -s "{keychain}"\n'
            call(["/usr/bin/security", "-i"], input=setup)
        source = root / "synthetic.license"
        source.write_text(secret)
        protect(source)
        for backend in ("native", "file"):
            directory = root / (backend + "-credentials")
            flags = ["--credential-backend", backend, "--credential-dir", str(directory)]
            imported = json.loads(kmq("license", "import", "--file", str(source), *flags).stdout)
            reference = imported["reference"]
            shown = json.loads(kmq("license", "show", "--credential", reference, *flags).stdout)
            check(shown["reference"] == reference, "credential persists across executable processes")
            exported = root / (backend + "-export.license")
            kmq("license", "export", "--credential", reference, "--out", str(exported), *flags)
            check(exported.read_text().strip() == secret, "explicit protected export returns exact credential")
            kmq("license", "export", "--credential", reference, "--out", str(exported), *flags, success=False)
            kmq("license", "show", "--credential", reference, "--reveal", *flags, success=False)
            stored = directory / backend / reference
            if backend == "native":
                check(stored.read_bytes() == b"native\n", "native index contains no credential material")
                if actual_platform == "darwin":
                    raw = subprocess.run(["/usr/bin/security", "find-generic-password", "-s", "io.kubemq.kmq.onboarding.v1", "-a", reference, "-w"], capture_output=True, check=True).stdout
                    check(json.loads(base64.b64decode(raw))["key"] == secret, "macOS Keychain contains exact credential")
                elif actual_platform == "linux":
                    raw = subprocess.run(["secret-tool", "lookup", "service", "io.kubemq.kmq.onboarding.v1", "account", reference], capture_output=True, check=True).stdout
                    check(json.loads(base64.b64decode(raw))["key"] == secret, "Linux Secret Service contains exact credential")
                else:
                    native = subprocess.run(["cmdkey", "/list"], capture_output=True, text=True, check=True).stdout
                    check(reference in native, "Windows Credential Manager contains named credential")
            elif os.name != "nt":
                check(stored.stat().st_mode & 0o077 == 0, "protected-file credential denies group and other access")
        if os.name == "nt":
            inspect_acl = r'''$p=$args[0];$a=Get-Acl -LiteralPath $p;$s=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$rules=@($a.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]));@{owner_matches=($a.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq $s);one_rule=($rules.Count -eq 1);only_owner=($rules[0].IdentityReference.Value -eq $s);protected=$a.AreAccessRulesProtected}|ConvertTo-Json -Compress'''
            acl = json.loads(powershell(inspect_acl, str(root / "file-credentials" / "file" / reference)).stdout)
            check(all(acl.values()), "Windows stored credential grants only its owner through a protected access-control list")
        broad = root / "broad.license"
        broad.write_text(secret)
        protect(broad)
        if os.name == "nt":
            broaden = r'''$p=$args[0];$a=Get-Acl -LiteralPath $p;$sid=New-Object Security.Principal.SecurityIdentifier('S-1-1-0');$r=New-Object Security.AccessControl.FileSystemAccessRule($sid,'Read','Allow');$a.AddAccessRule($r);Set-Acl -LiteralPath $p -AclObject $a'''
            powershell(broaden, str(broad))
        else:
            broad.chmod(0o644)
        kmq("license", "import", "--file", str(broad), "--credential-backend", "file", "--credential-dir", str(root / "must-not-save"), success=False)
        check(not (root / "must-not-save").exists(), "permissive credential input is rejected before storage")
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Gateway)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            flags = ["--credential-backend", "native", "--credential-dir", str(root / "sessions"),
                     "--onboarding-url", f"http://127.0.0.1:{server.server_port}/requests"]
            request = root / "request.json"
            request.write_text(json.dumps({"email": "native@example.invalid", "name": "Native fixture", "company": "Fixture", "platform": "docker", "consent": True}))
            kmq("trial", "request", "--input", str(request), *flags)
            process = subprocess.Popen([str(binary), "trial", "verify", "--request", "native-candidate-request", "--code-stdin", "--non-interactive", "--deadline", "150ms", *flags], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            process.wait(timeout=10)
            check(process.returncode != 0, "blocked protected input cancels within deadline")
            process.stdin.close()
            kmq("trial", "verify", "--request", "native-candidate-request", "--code-stdin", "--non-interactive", *flags, input="12345678\n")
            kmq("trial", "claim", "--request", "native-candidate-request", *flags)
            check(Gateway.acknowledged, "native credential save completes before acknowledgement")
            kmq("trial", "status", "--request", "native-candidate-request", *flags)
            before = Gateway.calls
            exhausted = kmq("trial", "resume", "--request", "native-candidate-request", *flags, success=False)
            check("retry_budget_exhausted" in exhausted.stdout + exhausted.stderr and Gateway.calls == before + 1,
                  "exhausted remote request performs one attempt and stops")
        finally:
            server.shutdown()
        if actual_platform == "linux":
            unavailable = os.environ.copy()
            unavailable["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/nonexistent-kmq-session"
            kmq("license", "import", "--file", str(source), "--credential-dir", str(root / "unavailable"), env=unavailable, success=False)
            check(not (root / "unavailable" / "file").exists(), "unavailable native store never falls back to plaintext")
        if keychain is not None:
            call(["/usr/bin/security", "lock-keychain", str(keychain)])
            kmq("license", "import", "--file", str(source), "--credential-dir", str(root / "locked"), success=False)
            check(not (root / "locked" / "file").exists(), "locked macOS Keychain never falls back to plaintext")
        report["status"] = "passed"


try:
    run()
except Exception as failure:
    # Failure class only: raw subprocess/server exceptions may contain output.
    report["failure_class"] = type(failure).__name__
    print("Native candidate qualification failed; inspect the redacted checkpoint report.", file=sys.stderr)
    sys.exit_code = 1
finally:
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "checks": len(report["checks"])}))
if report["status"] != "passed":
    raise SystemExit(1)
