# Native staged-candidate qualification

Dispatch `.github/workflows/qualify-candidate.yml` on a reviewed commit containing
the candidate installers. Supply the exact version, a non-default
`kmq/staging/...` public Google Cloud Storage prefix, and the SHA-256 of the
candidate `checksums.txt` obtained from trusted release preparation. Every native
job executes the platform installer with strict signature verification, then
checks the installed executable, embedded schema/skill, native secret store,
protected file permissions, export non-overwrite and reveal refusal, synthetic
terminal receiving-session lifecycle, input cancellation and retry exhaustion.

The five jobs execute Linux amd64/arm64, macOS Intel/Apple Silicon and Windows
x86-64. Windows uses PowerShell 7 for installation and exercises the executable's
Windows Credential Manager helper. Windows ARM64 is not qualified or advertised.
Linux starts an actual disposable Secret Service session. macOS uses a disposable
Keychain and also checks locked-store refusal. Windows checks an owner-only
protected access-control list. All platforms reject a deliberately permissive
credential file. No production email, credential, broker, cloud resource or
private server source is used. Only a redacted report is uploaded.

Required staged assets follow the installer layout:
`PREFIX/VERSION/kmq_{linux,darwin}_{amd64,arm64}.tar.gz`,
`kmq_windows_amd64.zip`, `checksums.txt`, `checksums.txt.sig`, `cosign.pub`.
The public checkout must contain the exact candidate `install.sh` and
`install.ps1`. The checksum-manifest digest is checked before installation; strict
installer verification checks the signing key and archive signature/checksum.

This establishes native executable/install/store behavior. It does not establish
Docker Desktop availability, Kubernetes operator/runtime behavior, real mailbox
delivery, public release promotion, or disconnected production completion. Those
remain separate executed qualification records. A workflow file or queued job is
not a passing native-platform result.
