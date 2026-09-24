# syntax=docker/dockerfile:1
# =============================================================================
# Kirocrew custom container image
# -----------------------------------------------------------------------------
# Built ON TOP OF the official Kiro Crew image, so the gateway, its entrypoint
# and Python 3.12 come from upstream and we only layer the extra tooling the
# agent needs:
#   - Node.js 22 managed through nvm (agent can target the right version)
#   - Corepack-managed Yarn 4.x and pnpm
#   - Playwright + browsers (Settings/Browser feature)
#   - LikeC4 CLI (architecture-as-code diagrams)
#   - CALM CLI (@finos/calm-cli, Common Architecture Language Model)
#   - pdftotext (poppler-utils)
#   - TinyTeX (lualatex/xelatex) for compiling CVs / cover letters
#   - Bun (runtime for the ai-job-search job-portal CLIs)
#   - Voice audio decoder (ffmpeg) for KiroCrew voice (dashboard STT)
#   - KiroCrew [voice] Python extra (pywhispercpp, boto3, amazon-transcribe)
#     plus piper-tts, installed into the gateway's Python so STT + TTS work
#
# Python 3 is provided by the base image (python:3.12), so no conda/micromamba
# layer is needed here.
#
# Hardening follows the OWASP Docker Security Cheat Sheet:
#   - keeps the base image's non-root `kirocrew` user (UID 1000)
#   - pinned base image (by digest), tool versions
#   - no secrets baked into layers (build args carry only public metadata)
#   - preserves the upstream entrypoint that runs the gateway
# Traceability follows the OCI image annotations spec (see LABEL block).
# =============================================================================

# renovate: datasource=docker depName=ghcr.io/kirodotdev/kirocrew
ARG KIROCREW_BASE_TAG='0.6.0'
FROM ghcr.io/kirodotdev/kirocrew:${KIROCREW_BASE_TAG}@sha256:ba01bb1c75ea454af2b53773f39c3b38899f0d1d9ab51a0eb97001df6db27407

# The base image (python:3.12 / Debian trixie) runs as the non-root `kirocrew`
# user (UID 1000). Reuse it rather than inventing our own.
ARG APP_USER="kirocrew"
ARG APP_UID="1000"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# Additional OS dependencies (installed as root, then drop back to the app user)
#   - poppler-utils -> pdftotext
#   - perl          -> required by the TinyTeX installer
#   - ALSA/PulseAudio runtime -> voice mode (kiro-cli voice / whisper via cpal)
#   - curl/wget/unzip/ca-certificates -> tool installers below
# -----------------------------------------------------------------------------
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && apt-get install -yqq --no-install-recommends \
        'ca-certificates' \
        'curl' \
        'wget' \
        'unzip' \
        'git' \
        'perl' \
        # - `xz-utils` is required to extract the TinyTeX .tar.xz bundle
        'xz-utils' \
        'poppler-utils' \
        # --- Voice audio decoder ---
        # KiroCrew's voice (dashboard STT via pywhispercpp) captures the mic in
        # the browser and decodes audio through ffmpeg. Crew can auto-download a
        # decoder, but shipping ffmpeg satisfies it offline. This is the only
        # audio dependency the KiroCrew voice feature actually needs.
        'ffmpeg' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# KiroCrew [voice] Python extra — installed into the gateway's own interpreter
# (/usr/local/bin/python, where kiro_crew lives), not a venv, so the dashboard
# STT/TTS providers resolve. `pip install "kirocrew[voice]"` cannot be used
# (KiroCrew is not on PyPI); instead install the extra's own distributions with
# the exact ranges the wheel's metadata declares:
#   voice      -> pywhispercpp>=1.5,<2  (+ voice-aws)
#   voice-aws  -> boto3>=1.34,<2, amazon-transcribe>=0.6,<1
# Plus piper-tts for the default local Text-to-Speech (voice OUTPUT); it ships a
# 3.12 wheel and a `piper` binary on PATH (kiro_crew's TTS probes the binary).
# All resolve to prebuilt wheels (no compiler needed). Kept in sync with the
# upstream extra; a base bump that changes the ranges is a Renovate/build signal.
# -----------------------------------------------------------------------------
# renovate: datasource=pypi depName=pywhispercpp
ARG PYWHISPERCPP_SPEC='pywhispercpp>=1.5,<2'
# renovate: datasource=pypi depName=boto3
ARG BOTO3_SPEC='boto3>=1.34,<2'
# renovate: datasource=pypi depName=amazon-transcribe
ARG AMAZON_TRANSCRIBE_SPEC='amazon-transcribe>=0.6,<1'
# renovate: datasource=pypi depName=piper-tts
ARG PIPER_TTS_SPEC='piper-tts>=1.3,<2'
RUN pip install --no-cache-dir --root-user-action=ignore \
        "${PYWHISPERCPP_SPEC}" \
        "${BOTO3_SPEC}" \
        "${AMAZON_TRANSCRIBE_SPEC}" \
        "${PIPER_TTS_SPEC}" \
    && python -c 'import pywhispercpp, boto3, amazon_transcribe, piper' \
    && command -v piper > /dev/null

# -----------------------------------------------------------------------------
# Node.js 22 via nvm (agent can target the adequate version).
# -----------------------------------------------------------------------------
USER ${APP_UID}
WORKDIR /home/${APP_USER}

# renovate: datasource=node-version depName=node
ARG NODE_VERSION='22.23.2'
# renovate: datasource=github-tags depName=nvm-sh/nvm extractVersion=^v(?<version>.+)$
ARG NVM_VERSION='0.40.4'
# renovate: datasource=npm depName=playwright
ARG PLAYWRIGHT_VERSION='1.63.0'

ENV NVM_DIR="/home/${APP_USER}/.nvm"
RUN curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash \
    && source "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && nvm use default

ENV NODE_PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/lib/node_modules"
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}"

# -----------------------------------------------------------------------------
# Corepack: manage Yarn 4.x and pnpm (bundled with Node.js). Corepack owns the
# `yarn`/`pnpm` shims, so we do NOT `npm i -g yarn`. `corepack prepare` pins the
# versions and caches them for reproducible, offline-friendly builds.
# -----------------------------------------------------------------------------
# renovate: datasource=npm depName=@yarnpkg/cli-dist
ARG YARN_VERSION='4.18.0'
# renovate: datasource=npm depName=pnpm
ARG PNPM_VERSION='12.5.1'
RUN source "${NVM_DIR}/nvm.sh" \
    && corepack enable \
    && corepack prepare "yarn@${YARN_VERSION}" --activate \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate \
    && yarn --version \
    && pnpm --version

# -----------------------------------------------------------------------------
# Global Node CLIs: Playwright, LikeC4, CALM CLI (pinned for reproducibility).
# -----------------------------------------------------------------------------
# renovate: datasource=npm depName=likec4
ARG LIKEC4_VERSION='1.59.3'
# renovate: datasource=npm depName=@finos/calm-cli
ARG CALM_CLI_VERSION='1.60.1'
RUN source "${NVM_DIR}/nvm.sh" \
    && npm install -g \
        "playwright@${PLAYWRIGHT_VERSION}" \
        "likec4@${LIKEC4_VERSION}" \
        "@finos/calm-cli@${CALM_CLI_VERSION}" \
    && npm cache clean --force

# Install the browser OS dependencies as root (apt), driven by the pinned
# Playwright installed above (nvm Node 22 is on the inherited PATH).
USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && playwright install-deps chromium firefox webkit \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download the browser binaries into the user's cache (non-root, already owned).
USER ${APP_UID}
RUN playwright install chromium firefox webkit

# -----------------------------------------------------------------------------
# LaTeX toolchain (TinyTeX) for compiling CVs / cover letters.
# ref: https://github.com/fjudith/ai-job-search/blob/master/SETUP.md
#      (#minimal-tex-install-tinytexbasictex)
# User-level, minimal TeX Live providing `lualatex` (CV) and `xelatex` (cover
# letter), plus the CTAN packages the stock templates require.
# -----------------------------------------------------------------------------
# renovate: datasource=github-releases depName=rstudio/tinytex-releases versioning=loose extractVersion=^v(?<version>.+)$
ARG TINYTEX_VERSION='2026.09'
ENV PATH="/home/${APP_USER}/.TinyTeX/bin/x86_64-linux:${PATH}"
RUN set -e \
    && export PATH="/home/${APP_USER}/.TinyTeX/bin/x86_64-linux:${PATH}" \
    && wget -qO /tmp/install-tinytex.sh "https://yihui.org/tinytex/install-bin-unix.sh" \
    && TINYTEX_VERSION="${TINYTEX_VERSION}" sh /tmp/install-tinytex.sh \
    && rm -f /tmp/install-tinytex.sh \
    # Fail the build if TinyTeX did not install correctly.
    && command -v tlmgr \
    && tlmgr install \
        moderncv fontawesome5 fontawesome6 academicons import luatexbase pgf \
        titlesec textpos xltxtra xunicode cite realscripts needspace \
    && tlmgr path add \
    && lualatex --version > /dev/null \
    && xelatex --version > /dev/null

# -----------------------------------------------------------------------------
# Bun (runtime for the ai-job-search job-portal CLIs), pinned for reproducibility.
# -----------------------------------------------------------------------------
# renovate: datasource=github-releases depName=oven-sh/bun extractVersion=^bun-v(?<version>.+)$
ARG BUN_VERSION='1.4.2'
ENV BUN_INSTALL="/home/${APP_USER}/.bun"
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && bun --version

# -----------------------------------------------------------------------------
# Make the added toolchain available to LOGIN/INTERACTIVE shells too.
# The base image's /etc/profile resets PATH, so a `bash -l` the agent spawns
# would otherwise lose nvm/bun/TinyTeX. Drop a profile.d snippet (and source
# nvm) so `node`, `bun`, `yarn`, `pnpm`, `lualatex`, etc. resolve everywhere.
# -----------------------------------------------------------------------------
USER root
RUN printf '%s\n' \
    '# Added by the kirocrew custom image (see images/kirocrew/Dockerfile)' \
    'export NVM_DIR="/home/'"${APP_USER}"'/.nvm"' \
    'export BUN_INSTALL="/home/'"${APP_USER}"'/.bun"' \
    'export PATH="${NVM_DIR}/versions/node/v'"${NODE_VERSION}"'/bin:${BUN_INSTALL}/bin:/home/'"${APP_USER}"'/.TinyTeX/bin/x86_64-linux:${PATH}"' \
    '[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"' \
    > /etc/profile.d/99-kirocrew-tools.sh \
    && chmod a+r /etc/profile.d/99-kirocrew-tools.sh
USER ${APP_UID}

# -----------------------------------------------------------------------------
# OCI traceability annotations.
# Fed by CI: --build-arg VCS_REF=$(git rev-parse HEAD) --build-arg BUILD_DATE=...
# -----------------------------------------------------------------------------
ARG VERSION="0.0.1"
ARG VCS_REF="unknown"
ARG BUILD_DATE="unknown"
LABEL org.opencontainers.image.title="kirocrew" \
      org.opencontainers.image.description="Custom Kiro Crew image built on the official kirocrew base, adding Node.js 22 (nvm), Corepack Yarn 4.x/pnpm, Playwright, LikeC4 CLI, CALM CLI, pdftotext, TinyTeX (lualatex/xelatex), Bun, the ffmpeg audio decoder and the KiroCrew [voice] Python extra (pywhispercpp/boto3/amazon-transcribe + piper-tts)." \
      org.opencontainers.image.base.name="ghcr.io/kirodotdev/kirocrew:0.6.0" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.url="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.documentation="https://github.com/alithya-oss/containers/blob/main/images/kirocrew/README.md" \
      org.opencontainers.image.authors="Alithya Open Source Software" \
      org.opencontainers.image.vendor="Alithya" \
      org.opencontainers.image.licenses="Apache-2.0"

# Liveness check: confirm the added core toolchain is reachable.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node --version && python --version || exit 1

# Keep the base image's ENTRYPOINT (`kirocrew-entrypoint`) and CMD (`gateway`)
# and its non-root user / workdir, so the container still runs the Kiro Crew
# gateway — now with the extra tooling on PATH.
USER ${APP_UID}
WORKDIR /home/${APP_USER}
