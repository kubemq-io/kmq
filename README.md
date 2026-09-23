# kmq

`kmq` is the KubeMQ command-line tool for messaging, inspecting a server or cluster, and assessing Kafka compatibility. Its offline help and command schema can be read by coding agents without giving them a separate privileged service.

The [KubeMQ server repository](https://github.com/kubemq-io/kubemq-server/tree/master/cli) contains the source. This repository is the public download and agent-discovery entry point.

## Install

The Unix installer supports Linux and macOS on x86-64 and arm64. Select a [published release](https://github.com/kubemq-io/kmq/releases), then use the same tag for the installer and binary:

```sh
release_tag=vX.Y.Z # replace with a published tag
curl -sSfL "https://raw.githubusercontent.com/kubemq-io/kmq/${release_tag}/install.sh" |
  sh -s -- --version "${release_tag}" --install-dir "$HOME/.local/bin"
"$HOME/.local/bin/kmq" version
```

The installer checks the archive against the release checksum. Pass `--verify-signature` if you have `cosign` installed and require its signature check. Review the downloaded script and release assets before using them in a managed environment. The installer accepts `KMQ_INSTALL_DIR` for a custom writable location and never needs KubeMQ credentials.

For a manual install or a platform without this Unix installer, use the archive and checksum from the same [release](https://github.com/kubemq-io/kmq/releases). A native Windows installer is not included in this repository yet.

## First connection

Start with a running KubeMQ server whose management address you know. A licensed deployment is required where the server enforces licensing.

```sh
kmq context create local --api-address http://localhost:8080
kmq context use local
kmq doctor
kmq queue send demo "hello"
kmq queue peek demo --count 1
```

Use a separate named context for each environment. For authenticated servers, provide the token through the supported environment or context options described in the [command guide](https://docs.kubemq.io/operate/kmq-cli). Do not place production tokens in shell history.

## Use with a coding agent

Install the [discovery skill](skills/kmq/SKILL.md) through your agent's skill mechanism. Once `kmq` is installed, ask the agent to run `kmq skills get core` for instructions matched to that binary. `kmq schema -o json` works offline and exposes the command tree; `kmq schema <command> -o json` narrows it to one command or group on versions that support focused discovery. Installing the skill does not grant access to a KubeMQ server.

## Evaluate a Kafka workload

`kmq assess kafka` reads a source cluster and reports compatibility findings. Start with `kmq assess kafka --help` and the [Kafka migration guide](https://docs.kubemq.io/connectors/kafka/how-to/migrate-from-kafka) for the installed version. A read-only assessment is a decision aid, not proof that application code, data, offsets, and production operations have been migrated.

Migration to a Kubernetes target requires an operator-managed KubeMQ cluster and a sales-issued license that covers at least three servers. Compacted topics, Schema Registry dependencies, and unknown scan coverage need explicit review. Do not run a production cutover from an incomplete assessment or an unverified target.

## Support and limitations

Use `kmq version` to record the installed binary version and check its help against the [documentation](https://docs.kubemq.io/operate/kmq-cli). Current migration commands do not by themselves establish durable Kubernetes worker ownership, complete deployment and topic identity, or independent end-to-end cutover verification. Treat those gaps as release blockers for unattended production migration. For help, see the [documentation](https://docs.kubemq.io) and [KubeMQ support](https://kubemq.io/contact-us/).
