# kirocrew

Custom [Kiro Crew](https://github.com/alithya-oss) container image bundling the
full toolchain the agent needs to execute every embedded tool.

## Embedded tooling

| Tool | Provided by | Notes |
| --- | --- | --- |
| Node.js 22 | `nvm` | The agent can `nvm install`/`nvm use` another version if needed. |
| Python 3 | `micromamba` (`/opt/conda`) | Aligned with the other images in this repo. |
| Playwright | `npm -g playwright` + browsers | Chromium, Firefox and WebKit installed with their OS deps. |
| LikeC4 CLI | `npm -g likec4` | Architecture-as-code diagrams. |
| CALM CLI | `npm -g @finos/calm-cli` | FINOS Common Architecture Language Model. |
| pdftotext | `poppler-utils` | PDF text extraction. |

## Acceptance criteria coverage

- **Settings/Browser** — Playwright and its browsers are pre-installed, so the
  browser feature can be configured.
- **JavaScript execution** — Node.js 22 is available through `nvm`, letting the
  agent target the adequate version.
- **Python execution** — Python 3 is available on the `PATH` via micromamba.

## Build

```bash
docker image build \
  --build-arg VERSION="$(jq -r .version image-specs.json)" \
  --build-arg VCS_REF="$(git rev-parse HEAD)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t oci.local/kirocrew:latest \
  ./
```

Or, from the repository root, using the Taskfile:

```bash
task build:kirocrew
```

## Security hardening

The image follows the [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html):

- Runs as a non-root user (`cicd`, UID `10000`).
- Pinned base image and tool versions for reproducible builds.
- No secrets baked into layers — build args carry only public metadata.
- `tini` as PID 1 to reap zombie processes.
- `HEALTHCHECK` validating the core toolchain.

## Traceability

The image exposes the standard
[OCI image annotations](https://specs.opencontainers.org/image-spec/annotations/)
(`org.opencontainers.image.*`). `revision`, `created` and `version` are fed by
build args (`VCS_REF`, `BUILD_DATE`, `VERSION`) for automatic CI/CD traceability.
