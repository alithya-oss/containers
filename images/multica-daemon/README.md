# multica-daemon

Container image running the [Multica](https://multica.ai) CLI agent daemon with
[`kiro-cli`](https://kiro.dev/cli/) (Kiro's ACP coding agent) on `PATH`, built on
a pinned Node.js LTS base. Deployed as the ECS Fargate task image for the
Multica/Kiro-CLI daemon on AWS — see
[alithya-oss/multica-on-aws](https://github.com/alithya-oss/multica-on-aws),
`infrastructure/cloudformation/compute.yaml`.

## What's inside

| Component | Source | Notes |
| --- | --- | --- |
| Node.js 22 (LTS) | `docker.io/library/node` base image | Pinned tag; the daemon's development tasks run Node.js/TypeScript workloads. |
| `kiro-cli` | [`cli.kiro.dev/install`](https://cli.kiro.dev/) official installer | Installed to `/opt/kiro-cli`, symlinked onto `PATH`. The ACP coding agent the daemon drives for every task. |
| `multica` | [GitHub Releases](https://github.com/multica-ai/multica/releases) (`multica-ai/multica`) | Installed to `/opt/multica`, symlinked onto `PATH`. Runs `multica daemon start --foreground` as the container's main process. |

Both CLIs are installed outside `/home/multica` (the directory an EFS volume
mount will occupy at runtime, per `compute.yaml`'s `multica-state` volume) so a
mounted state volume can never shadow the toolchain — the same pattern used by
`images/kirocrew` in this repo.

## Runtime expectations

- **Outbound only.** The daemon polls the Multica server over HTTPS and sends
  periodic heartbeats; no port is `EXPOSE`d and none should be opened at the
  orchestrator level (ECS security group has zero ingress rules, see
  `storage-security.yaml`).
- **State.** `~/.multica` (config/token/logs/pid) and
  `MULTICA_WORKSPACES_ROOT` (`~/.multica-state/workspaces`, repo checkout
  cache) are expected to be backed by a persistent volume (EFS in production)
  so daemon identity and repo cache survive a task replacement.
- **Auth token.** `MULTICA_TOKEN` is injected at container start via the
  orchestrator's native secret-injection mechanism (ECS `secrets` from
  Secrets Manager) — never baked into the image or passed as a plain
  environment variable in any Dockerfile/compose file.
- **Health check.** `pgrep -f 'multica daemon'`, matching the ECS task
  definition's own container health check in `compute.yaml`.

## Build

```bash
docker image build \
  --build-arg VERSION="$(jq -r .version image-specs.json)" \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t oci.local/multica-daemon:latest \
  ./
```

Or, from the repository root, using the Taskfile:

```bash
task build:multica-daemon
```

## CI/CD

Unlike every other image in this repo (published to GHCR via
`.github/workflows/build-container.yaml`), this image is published to a
private **Amazon ECR** repository in the AWS account that runs the daemon —
see `.github/workflows/build-and-push-ecr.yaml`. The ECR repository itself
(`infrastructure/cloudformation/ecr.yaml` in `multica-on-aws`) already enables
`ScanOnPush`; the workflow additionally waits for that scan to complete and
fails the run if it finds a `CRITICAL` or `HIGH` severity vulnerability,
**before** the image is considered published (the immutable tag is pushed
first — ECR scans a pushed image, it cannot scan an image that was never
uploaded — but the workflow's success/failure status, and therefore whether
anything downstream treats this build as deployable, depends on the scan
result).

Authentication to AWS uses OpentID Connect (no stored AWS access keys): the
workflow assumes `multica-daemon-github-actions-ecr-push`
(`alithya-oss/multica-on-aws`, `infrastructure/cloudformation/github-oidc.yaml`)
via `aws-actions/configure-aws-credentials`, scoped to this repository and to
`main`-branch/tag-triggered runs only.

## Security hardening

Follows the [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html):

- Runs as a dedicated non-root user (`multica`, UID/GID `1000`), never root.
- Pinned base image tag and tool versions (`NODE_VERSION`, `MULTICA_CLI_VERSION`
  build args) for reproducible builds.
- No secrets baked into any layer — the auth token is injected at container
  start by the orchestrator, never present in the image or its build args.
- Minimal apt surface (`ca-certificates`, `curl`, `git`, `tini`, `unzip` only).
- `tini` as PID 1 to reap zombie processes from the daemon's long-running
  child agent sessions.
- `HEALTHCHECK` validating the daemon process is actually running.
- Published to a private ECR repository with `ScanOnPush` and a CI gate that
  fails the pipeline on `CRITICAL`/`HIGH` findings.

## Traceability

Exposes the standard
[OCI image annotations](https://specs.opencontainers.org/image-spec/annotations/)
(`org.opencontainers.image.*`), including `base.name`. `revision`, `created`
and `version` are fed by build args (`VCS_REF`, `BUILD_DATE`, `VERSION`) for
CI/CD traceability.
