# multica-kiro-daemon

Container image running the [Multica](https://github.com/multica-ai/multica)
agent daemon with [Kiro CLI](https://kiro.dev/cli/) (`kiro-cli`) as its ACP
coding-agent backend, on a Node.js LTS base. Built for the ECS Fargate
service designed in ALIT-9
(`infrastructure/cloudformation/compute.yaml` in
[alithya-oss/multica-on-aws](https://github.com/alithya-oss/multica-on-aws))
and published to the **ECR** repository from that same design
(`ecr.yaml`) — this image is not pushed to GHCR like the other images in
this repo (see `.github/workflows/push-ecr.yaml`).

## Base image

`FROM docker.io/library/node:22.21.1-bookworm-slim` (Node.js LTS, pinned).
The daemon itself needs Node.js/TypeScript on the image to execute the
development tasks it is assigned (per ALIT-4's architecture).

## What's installed

| Tool | Provided by | Notes |
| --- | --- | --- |
| Node.js 22 LTS | base image | `node`/`npm`/`npx` on `PATH` for the daemon's development tasks. |
| `multica` CLI + daemon | GitHub Releases binary (Option B, `CLI_INSTALL.md`) | Installed under `/opt/multica`, symlinked to `/usr/local/bin/multica`. |
| `kiro-cli` | [official installer](https://cli.kiro.dev/install) | Installed as the non-root user, symlinked to `/usr/local/bin/kiro-cli`; `MULTICA_KIRO_PATH` points at the absolute path so the daemon's unattended spawns don't depend on `PATH`. |
| `git`, `procps`, `curl`, `ca-certificates`, `unzip` | `apt` | `git` for the daemon's own repo checkouts; `procps` for `pgrep` (health checks). |

## Non-root user

Runs as `multica`, **UID/GID 1000** — matching the EFS access point's fixed
POSIX identity in `storage-security.yaml`, so the mounted state directory
(`~/.multica`, `MULTICA_WORKSPACES_ROOT`) is writable without a runtime
`chown`. Derived by renaming the base `node:*` image's existing `node` user
(already `1000:1000`) rather than creating a new one.

## Authentication — resolves ALIT-9's open point #1

`multica` has **no documented environment variable** for non-interactive
authentication (confirmed against `CLI_AND_DAEMON.md` — only agent-specific
`MULTICA_<AGENT>_PATH`/`_MODEL` variables exist, none for the daemon's own
auth). The real non-interactive mechanism is the CLI command:

```bash
multica login --token=<mul_...>
```

`scripts/entrypoint.sh` bridges this: it reads the `MULTICA_TOKEN`
environment variable (injected by ECS's native `secrets` mechanism from
Secrets Manager — never baked into the image or passed as a build arg),
and runs `multica login --token="${MULTICA_TOKEN}"` once per fresh state
directory, skipping it when `multica auth status` already reports a valid
session (so a redeploy/restart with a persisted EFS-backed home volume
does not re-authenticate every time). It then `exec`s
`multica daemon start --foreground` as PID 1.

**Action for ALIT-13 (deployment-execution):** no change needed to
`compute.yaml`'s `Secrets` block — it already targets the env var name
`MULTICA_TOKEN`, which is exactly what this entrypoint expects.

## Build

```bash
docker image build \
  --build-arg VERSION="$(jq -r .version image-specs.json)" \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t oci.local/multica-kiro-daemon:latest \
  ./
```

Or, from the repository root, using the Taskfile:

```bash
task build:multica-kiro-daemon
```

## Running locally

```bash
docker run -d --name multica-kiro-daemon \
  -e MULTICA_TOKEN='mul_...' \
  -v multica-kiro-daemon-home:/home/multica \
  oci.local/multica-kiro-daemon:latest

docker logs -f multica-kiro-daemon
```

No ports are published: the daemon is outbound-only (HTTPS poll + heartbeat
to the Multica server), matching the no-ingress design in ALIT-9.

## Security hardening

Follows the [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html):

- Non-root `multica` user (UID/GID `1000`).
- Pinned base image and tool versions (`NODE_VERSION`, `MULTICA_VERSION`
  build args) for reproducible builds.
- No secrets baked into layers — the auth token is injected only at
  container runtime via ECS `secrets`, never a build arg or `ENV` default.
- `HEALTHCHECK` validates the daemon process is actually running
  (`pgrep -f 'multica daemon'`), matching the ECS container health check in
  `compute.yaml`.
- Vulnerability scanning happens at publish time: ECR's `ScanOnPush` (set in
  `ecr.yaml`) scans every image this repo's CI pushes, before it can be
  pulled by the ECS task — no separate scan step is duplicated in CI.

## Traceability

Exposes the standard
[OCI image annotations](https://specs.opencontainers.org/image-spec/annotations/)
(`org.opencontainers.image.*`). `revision`, `created` and `version` are fed
by build args (`VCS_REF`, `BUILD_DATE`, `VERSION`) from CI.
