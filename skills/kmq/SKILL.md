---
name: kmq
description: Use when the user wants to drive a KubeMQ broker or cluster from the command line or from an AI agent — sending or receiving Queue/Events/Events-Store/Command/Query messages, inspecting channels/connectors/agents, checking cluster health or metrics, or otherwise automating KubeMQ instead of using the dashboard. Triggers on "kmq", "KubeMQ CLI", "send a queue message", "subscribe to events", "check kubemq status/health/metrics", or any request to script/automate a KubeMQ broker.
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
