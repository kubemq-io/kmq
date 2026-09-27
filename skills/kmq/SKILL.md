---
name: kmq
description: Use when installing, deploying, operating, or diagnosing KubeMQ, or assessing a Kafka move to KubeMQ. Discover the installed kmq command-line client's messaging, cluster, authentication, trial, deployment, and migration commands before acting.
---

# kmq — KubeMQ agent CLI

`kmq` is KubeMQ's agent-native CLI. Load the full, version-matched guide from the installed binary:

    kmq skills get core          # workflows, command surface, auth, exit codes
    kmq skills get core --full   # + full command reference

If `kmq` is missing, install it on macOS or Linux:

    curl -sSfL https://raw.githubusercontent.com/kubemq-io/kmq/main/install.sh | sh

On Windows, download and run the PowerShell installer:

    Invoke-WebRequest https://raw.githubusercontent.com/kubemq-io/kmq/main/install.ps1 -OutFile install-kmq.ps1
    .\install-kmq.ps1

Then run `kmq version` and `kmq skills get core`. The installer supports Windows x86-64;
check its output for the installed path.

Content is served by the installed binary, so it never goes stale. Offline discovery:
`kmq schema -o json`, `kmq cheat <topic>`, `kmq docs`.

For a Kafka replacement request, inspect the installed binary's assessment and
migration guidance before proposing a transfer. Treat unsupported and unknown
findings as blockers; a compatibility report is not proof of a completed migration.
