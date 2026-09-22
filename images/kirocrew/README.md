# kirocrew

Custom [Kiro Crew](https://github.com/alithya-oss) container image bundling the
full toolchain the agent needs to execute every embedded tool.

## Embedded tooling

| Tool | Provided by | Notes |
| --- | --- | --- |
| Node.js 22 | `nvm` | The agent can `nvm install`/`nvm use` another version if needed. |
| Yarn 4.x / pnpm | Corepack | `corepack enable` manages the `yarn` (4.x) and `pnpm` shims. |
| Python 3 | `micromamba` (`/opt/conda`) | Aligned with the other images in this repo. |
| Playwright | `npm -g playwright` + browsers | Chromium, Firefox and WebKit installed with their OS deps. |
| LikeC4 CLI | `npm -g likec4` | Architecture-as-code diagrams. |
| CALM CLI | `npm -g @finos/calm-cli` | FINOS Common Architecture Language Model. |
| pdftotext | `poppler-utils` | PDF text extraction. |
| LaTeX (TinyTeX) | `tlmgr` package set | `lualatex` + `xelatex` for compiling CVs / cover letters. |
| Bun | official installer | Runtime for the ai-job-search job-portal CLIs. |
| Voice mode audio | `libasound2t64`, `libpulse0`, `libasound2-plugins` | ALSA/PulseAudio runtime for `kiro-cli voice` (Whisper STT). |

## ai-job-search extra dependencies

The LaTeX toolchain and Bun cover the
[ai-job-search SETUP.md](https://github.com/fjudith/ai-job-search/blob/master/SETUP.md#minimal-tex-install-tinytexbasictex)
prerequisites for compiling CVs / cover letters and running the job-portal CLIs:

- **TinyTeX** (minimal, user-level TeX Live) providing `lualatex` (CV) and
  `xelatex` (cover letter), plus the template CTAN packages:
  `moderncv fontawesome5 fontawesome6 academicons import luatexbase pgf titlesec textpos xltxtra xunicode cite realscripts needspace`.
- **pdftotext** (poppler-utils) for the `/apply` ATS parseability check.
- **Bun** for the TypeScript job-portal CLIs.

## Voice mode

`kiro-cli voice` (the `/voice` command) records the microphone via **cpal** and
transcribes locally with **whisper.cpp** (whisper-rs). On Linux, cpal requires
ALSA as its base audio layer and uses PulseAudio/PipeWire when available, so the
image ships the runtime shared libraries:

- `libasound2t64` — ALSA runtime (required base layer).
- `libpulse0` — PulseAudio client, used by cpal's PulseAudio host.
- `libasound2-plugins` — ALSA↔PulseAudio bridge plugin.

The Whisper speech model (~148 MB `base` / ~466 MB `small`) is **downloaded at
runtime** from Hugging Face on first use, not baked into the image. To actually
capture audio, the container must be given access to an audio device/server at
runtime (e.g. mount the host PulseAudio/PipeWire socket, or set
`KIRO_VOICE_SERVER_URL` to use a remote voice server).

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
