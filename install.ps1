# Install a pinned kmq release for Windows without administrator privileges.
# Example: .\install.ps1 -Version v3.5.0 -VerifySignature
param(
    [string]$Version = $env:KMQ_VERSION,
    [string]$InstallDir = $env:KMQ_INSTALL_DIR,
    [switch]$VerifySignature
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$trustedKeyHash = 'b8792764c60e86a21aa0aed6b34e964ea5cf180c3654a043dbd9e4355a1410fe'
$repository = 'https://github.com/kubemq-io/kmq'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-ReleaseFile([string]$Uri, [string]$Destination) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $Destination -TimeoutSec 30 -MaximumRedirection 5 -UseBasicParsing -Headers @{ 'User-Agent' = 'kmq-installer' }
            return
        } catch {
            if ($attempt -eq 3) { throw "Download failed after three attempts: $Uri. $($_.Exception.Message)" }
            Start-Sleep -Seconds $attempt
        }
    }
}

if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
    throw 'This installer supports Windows. Use install.sh on Linux or macOS.'
}
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
    throw 'Only Windows x86-64 has a published kmq archive.'
}
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\kmq' }
$InstallDir = [IO.Path]::GetFullPath($InstallDir)

$work = Join-Path ([IO.Path]::GetTempPath()) ("kmq-install-" + [guid]::NewGuid().ToString('N'))
$stage = $null
$backup = $null
[void][IO.Directory]::CreateDirectory($work)
try {
    if (-not $Version) {
        $latestFile = Join-Path $work 'latest.json'
        Get-ReleaseFile 'https://api.github.com/repos/kubemq-io/kmq/releases/latest' $latestFile
        $Version = (Get-Content -Raw $latestFile | ConvertFrom-Json).tag_name
    }
    if ($Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$') {
        throw "Invalid release tag '$Version'. Pass -Version vX.Y.Z."
    }

    $prefix = if ($env:KMQ_PREFIX) { $env:KMQ_PREFIX.Trim('/') } else { 'kmq' }
    $base = if ($env:KMQ_BASE_URL) { "$($env:KMQ_BASE_URL.TrimEnd('/'))/$prefix/$Version" } else { "$repository/releases/download/$Version" }
    $archiveName = 'kmq_windows_amd64.zip'
    $archive = Join-Path $work $archiveName
    $checksums = Join-Path $work 'checksums.txt'
    Get-ReleaseFile "$base/$archiveName" $archive
    Get-ReleaseFile "$base/checksums.txt" $checksums

    $checksumLines = @(Get-Content $checksums | Where-Object { $_ -match '^([0-9a-fA-F]{64})\s+\*?kmq_windows_amd64\.zip$' })
    if ($checksumLines.Count -ne 1) { throw "Expected exactly one SHA-256 checksum for $archiveName." }
    $expected = [regex]::Match($checksumLines[0], '^([0-9a-fA-F]{64})').Groups[1].Value
    $actual = (Get-FileHash -Algorithm SHA256 $archive).Hash
    if ($actual -ne $expected) { throw "Checksum mismatch for $archiveName; existing installation was not changed." }

    $cosign = Get-Command cosign -ErrorAction SilentlyContinue
    $signatureRequired = $VerifySignature -or [bool]$env:KMQ_VERIFY_SIGNATURE
    if ($signatureRequired -and -not $cosign) { throw 'cosign is required for signature verification.' }
    if ($cosign) {
        $signature = Join-Path $work 'checksums.txt.sig'
        $publicKey = Join-Path $work 'cosign.pub'
        $signatureAvailable = $true
        try {
            Get-ReleaseFile "$base/checksums.txt.sig" $signature
            Get-ReleaseFile "$base/cosign.pub" $publicKey
        } catch {
            $signatureAvailable = $false
            if ($signatureRequired) { throw }
            Write-Warning 'Release signature is unavailable; only the checksum was verified.'
        }
        if ($signatureAvailable) {
            if ((Get-FileHash -Algorithm SHA256 $publicKey).Hash -ne $trustedKeyHash) {
                throw 'Release signing key differs from the pinned kmq trust root.'
            }
            & $cosign.Source verify-blob --key $publicKey --signature $signature $checksums | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'cosign signature verification failed.' }
        }
    } elseif (-not $signatureRequired) {
        Write-Warning 'cosign was not found; only the checksum was verified.'
    }

    [void][IO.Directory]::CreateDirectory($InstallDir)
    $stage = Join-Path $InstallDir ('.kmq-' + [guid]::NewGuid().ToString('N') + '.exe')
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entry = $zip.GetEntry('kmq.exe')
        if (-not $entry) { throw 'Archive does not contain kmq.exe at its root.' }
        $inputStream = $entry.Open()
        $outputStream = [IO.File]::Create($stage)
        try { $inputStream.CopyTo($outputStream) }
        finally { $outputStream.Dispose(); $inputStream.Dispose() }
    } finally { $zip.Dispose() }

    $installedVersion = (& $stage version | Out-String | ConvertFrom-Json).version
    if ($LASTEXITCODE -ne 0 -or $installedVersion -ne $Version) {
        throw "Downloaded executable did not report $Version; existing installation was not changed."
    }

    $destination = Join-Path $InstallDir 'kmq.exe'
    if ([IO.File]::Exists($destination)) {
        $backup = Join-Path $InstallDir ('.kmq-' + [guid]::NewGuid().ToString('N') + '.bak')
        [IO.File]::Replace($stage, $destination, $backup)
    } else {
        [IO.File]::Move($stage, $destination)
    }
    $stage = $null
    Write-Host "kmq $Version installed to $destination"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($userPath -split ';') -contains $InstallDir)) {
        $updatedPath = if ($userPath) { "$($userPath.TrimEnd(';'));$InstallDir" } else { $InstallDir }
        [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
    }
    if (-not (($env:PATH -split ';') -contains $InstallDir)) {
        $env:PATH = "$($env:PATH.TrimEnd(';'));$InstallDir"
    }
    Write-Host 'kmq is available in this PowerShell session and in newly opened terminals.'
} finally {
    if ($stage -and [IO.File]::Exists($stage)) { [IO.File]::Delete($stage) }
    if ($backup -and [IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    [IO.Directory]::Delete($work, $true)
}
