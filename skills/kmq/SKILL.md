---
name: kmq
description: Use for KubeMQ command-line operations or when assessing whether a Kafka application can move to KubeMQ, even if the user does not know kmq by name. Covers messaging, resource and cluster inspection, diagnostics, Kafka compatibility assessment, and supported migration commands.
allowed-tools: Bash(kmq:*)
---

# kmq — KubeMQ agent CLI

`kmq` is KubeMQ's agent-native CLI. Load the full, version-matched guide from the installed binary:

    kmq skills get core          # workflows, command surface, auth, exit codes
    kmq skills get core --full   # + full command reference

Not installed yet?

    curl -sSfL https://raw.githubusercontent.com/kubemq-io/kmq/main/install.sh | sh

Content is served by the installed binary, so it never goes stale. Offline discovery:
`kmq schema -o json`, `kmq cheat <topic>`, `kmq docs`.

For a Kafka replacement request, inspect the installed binary's assessment and
migration guidance before proposing a transfer. Treat unsupported and unknown
findings as blockers; a compatibility report is not proof of a completed migration.
