# CLAUDE.md — KubeMQ Agent Integration Guide

This file is generated from a single source (`cli/cmd/skills/core.md`) — do not
hand-edit. Run `go generate ./cli/...` after changing the source. Kept in lockstep
with `cli/AGENTS.md` — some tools read `CLAUDE.md`, others `AGENTS.md`; both carry
identical body content below the sentinel.

<!-- kmq:body -->
## Quick start

```sh
# Install kmq on macOS or Linux (POSIX sh, no credentials required)
curl -sSfL https://raw.githubusercontent.com/kubemq-io/kmq/main/install.sh | sh

# Windows x86-64: download install.ps1 from the same repository and run it in PowerShell

# Teach this agent the full command surface (workflows, auth, exit codes)
kmq skills get core

# Install the discovery skill into a supported agent (requires Node.js)
npx skills add kubemq-io/kmq
```

## Exit codes

| Code | Meaning | Retry? |
|------|---------|--------|
| 0 | Success | — |
| 1 | Generic error | No |
| 2 | Usage / bad flags / bad address or TLS setup | No |
| 3 | Not found | No |
| 4 | Auth error | No |
| 5 | Connection error | Yes (server down?) |
| 6 | Timeout | Yes |
| 7 | Partial success | Case-by-case |
| 8 | Retryable (server initializing or not ready; HTTP 429/502/503/504) | Yes — `kmq` retries some automatically |
| 130 | Stopped by Ctrl-C / SIGTERM | — |

Every exit-8 error carries `"retryable": true`; `kmq schema -o json | jq .error_codes` lists
every error code with its exit code.

One exception to the automatic retry: `kmq kafka share-groups reset-offsets` exits 8 when
the share group still has consumers attached (NON_EMPTY_GROUP). `kmq` does not retry that
one — stop the consumers, then run the command again.

## Output discipline

- Data → **stdout** only; errors and warnings → **stderr** only.
- Default one-shot format: compact JSON (`-o json`); default stream format: NDJSON (`-o ndjson`).

## Full guide

- `kmq skills get core` — workflows, command surface, auth, exit codes (offline, version-matched).
- `kmq skills get core --full` — the above plus the full command reference.
- `kmq cheat <topic>`, `kmq schema -o json`, `kmq docs` — embedded recipes, machine schema, doc signpost.

## Work Tracking

Work items are GitHub issues on the org-wide "KubeMQ" project board
(https://github.com/orgs/kubemq-io/projects/2). The procedure is
https://github.com/kubemq-io/kubemq-server/blob/master/docs/github-workflow.md: an issue lives in the
repo whose code changes (this repo's usual areas: area/cli); every PR body starts with
`Closes #N` (or `Refs #N` for a slice); merged-but-unreleased work carries `release/pending`;
releases are milestones. Labels here are managed by `scripts/github/labels.sh` in kubemq-server.
