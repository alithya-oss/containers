# kirocrew

Custom [Kiro Crew](https://github.com/kirodotdev/KiroCrew) container image built
**on top of the official Kiro Crew image**
(`ghcr.io/kirodotdev/kirocrew:stable`), adding the extra toolchain the agent
needs to execute every embedded tool. The upstream gateway, its entrypoint and
Python 3.12 come from the base image — this image only layers tools on top.

## Base image

`FROM ghcr.io/kirodotdev/kirocrew:stable` (pinned by digest). The image keeps
the base's non-root `kirocrew` user (UID 1000), its `kirocrew-entrypoint`
entrypoint and `gateway` command, so it still runs the Kiro Crew gateway — now
with the extra tooling on `PATH` (including login/interactive shells, via
`/etc/profile.d/99-kirocrew-tools.sh`).

## Embedded tooling (added on top of the base)

| Tool | Provided by | Notes |
| --- | --- | --- |
| Python 3.12 | base image (`python:3.12`) | Already present upstream — no conda/micromamba layer. |
| Node.js 22 | `nvm` | The agent can `nvm install`/`nvm use` another version if needed. |
| Yarn 4.x / pnpm | Corepack | `corepack enable` manages the `yarn` (4.x) and `pnpm` shims. |
| Playwright | `npm -g playwright` + browsers | Chromium, Firefox and WebKit installed with their OS deps. |
| LikeC4 CLI | `npm -g likec4` | Architecture-as-code diagrams. |
| CALM CLI | `npm -g @finos/calm-cli` | FINOS Common Architecture Language Model. |
| pdftotext | `poppler-utils` | PDF text extraction. |
| LaTeX (TinyTeX) | `tlmgr` package set | `lualatex` + `xelatex` for compiling CVs / cover letters. |
| Bun | official installer | Runtime for the ai-job-search job-portal CLIs. |
| Voice audio decoder | `ffmpeg` | Audio decoding for KiroCrew voice (dashboard STT via pywhispercpp). |

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

KiroCrew's **voice** feature (dashboard) does speech-to-text with a local,
in-process provider (`pywhispercpp`) and text-to-speech with Piper — both run on
the machine and download their own models on first use. Microphone capture
happens in the **browser** (the dashboard mic button), not on the server, so no
ALSA/PulseAudio device is needed in the container.

The one system dependency the STT path needs is an **audio decoder**: whisper
decodes incoming audio (e.g. voice memos) through **ffmpeg**. KiroCrew can
auto-download a verified decoder, but the image ships `ffmpeg` so it works
offline out of the box.

> Note: this is distinct from the *kiro-cli* `/voice` mode, which uses cpal/ALSA
> — that is a separate feature from KiroCrew's dashboard voice.

## Acceptance criteria coverage

- **Settings/Browser** — Playwright and its browsers are pre-installed, so the
  browser feature can be configured.
- **JavaScript execution** — Node.js 22 is available through `nvm`, letting the
  agent target the adequate version.
- **Python execution** — Python 3.12 is available on the `PATH` from the base image.

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

## Running the dashboard (avoiding the "blank screen")

This image inherits the upstream entrypoint and runs the Kiro Crew **gateway**
(dashboard on port `5476`). The gateway serves a token-authenticated SPA whose
`Content-Security-Policy` `connect-src` only allows `localhost` / `127.0.0.1` /
`0.0.0.0` origins by default. A **blank dashboard** almost always means the
browser was pointed at the gateway **without a token** or **via a host that is
not in the allowed origins** (a LAN IP, a hostname, or a reverse proxy) — the
React app then cannot call its own `/api/*` (HTTP 403) or open its WebSocket
(blocked by CSP), so it renders nothing. This behaviour comes from upstream and
is identical in the official `ghcr.io/kirodotdev/kirocrew:stable` image.

Correct local run:

```bash
docker run -d --name kirocrew \
  -p 127.0.0.1:5476:5476 \
  -v kirocrew-home:/home/kirocrew \
  oci.local/kirocrew:latest

# mint a fresh dashboard login link, then open the printed URL
docker exec kirocrew kirocrew token --ttl 2h
# -> open http://localhost:5476/?token=...
```

Reaching it from another host or behind a reverse proxy requires telling the
gateway which origin you browse from, otherwise the CSP/Host checks reject the
app's requests and the page stays blank:

- set `dashboard.url` in `~/.kiro/crew/config.json` (inside the volume), or
- set `KIROCREW_CORS_ORIGINS` to that origin,

ideally behind a TLS reverse proxy. See the upstream
[docker guide](https://github.com/kirodotdev/KiroCrew/blob/main/docs/guides/docker.md)
("Networking and security"). Agent command execution additionally needs either
the upstream seccomp profile (`--security-opt seccomp=...`) or
`-e KIROCREW_ALLOW_UNSANDBOXED=1`; the dashboard itself works without it.

## Security hardening

The image follows the [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html):

- Keeps the base image's non-root `kirocrew` user (UID `1000`).
- Pinned base image (by digest) and tool versions for reproducible builds.
- No secrets baked into layers — build args carry only public metadata.
- Preserves the upstream entrypoint that runs the gateway.
- `HEALTHCHECK` validating the added core toolchain.

## Traceability

The image exposes the standard
[OCI image annotations](https://specs.opencontainers.org/image-spec/annotations/)
(`org.opencontainers.image.*`), including `base.name`. `revision`, `created` and
`version` are fed by build args (`VCS_REF`, `BUILD_DATE`, `VERSION`) for
automatic CI/CD traceability.
