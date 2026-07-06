# AGENTS.md — KubeMQ Agent Integration Guide

This file is generated from a single source (`cli/cmd/skills/core.md`) — do not
hand-edit. Run `go generate ./cli/...` after changing the source. Some agent
tools read `CLAUDE.md`, others `AGENTS.md`; both share identical body content
below the sentinel.

<!-- kmq:body -->
## Quick start

```sh
# Install kmq (POSIX sh, no credentials required)
curl -sSfL https://raw.githubusercontent.com/kubemq-io/kmq/main/install.sh | sh

# Teach this agent the full command surface (workflows, auth, exit codes)
kmq skills get core

# Or install the discovery skill into every supported agent
npx skills add kubemq-io/kmq
```

## Exit codes

| Code | Meaning | Retry? |
|------|---------|--------|
| 0 | Success | — |
| 1 | Generic error | No |
| 2 | Usage / bad flags | No |
| 3 | Not found | No |
| 4 | Auth error | No |
| 5 | Connection error | Yes (server down?) |
| 6 | Timeout | Yes |
| 7 | Partial success | Case-by-case |
| 8 | Retryable (server initializing) | Yes — `kmq` retries automatically |

## Output discipline

- Data → **stdout** only; errors and warnings → **stderr** only.
- Default one-shot format: compact JSON (`-o json`); default stream format: NDJSON (`-o ndjson`).

## Full guide

- `kmq skills get core` — workflows, command surface, auth, exit codes (offline, version-matched).
- `kmq skills get core --full` — the above plus the full command reference.
- `kmq cheat <topic>`, `kmq schema -o json`, `kmq docs` — embedded recipes, machine schema, doc signpost.
