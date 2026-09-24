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
#   - @playwright/cli (`playwright-cli`) for KiroCrew browser rendering
#   - LikeC4 CLI (architecture-as-code diagrams)
#   - CALM CLI (@finos/calm-cli, Common Architecture Language Model)
#   - pdftotext (poppler-utils)
#   - TinyTeX (lualatex/xelatex) for compiling CVs / cover letters
#   - Bun (runtime for the ai-job-search job-portal CLIs)
#   - Voice audio decoder (ffmpeg) for KiroCrew voice (dashboard STT)
#   - KiroCrew [voice] Python extra (pywhispercpp, boto3, amazon-transcribe)
#     plus piper-tts, installed into the gateway's Python so STT + TTS work
#   - faiss-cpu — optional accelerator for the gateway's episodic memory recall
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
# KiroCrew [voice] Python extra — installed into the gateway's own interpreter.
# Invoke pip via `/usr/local/bin/python3.12 -m pip` (the exact interpreter that
# runs kiro_crew) rather than a bare `pip`, so the packages land in the gateway
# site-packages unambiguously regardless of PATH state or which pip shim exists.
# Not a venv, so the dashboard STT/TTS providers resolve. `pip install
# "kirocrew[voice]"` cannot be used (KiroCrew is not on PyPI); instead install
# the extra's own distributions with the exact ranges the wheel metadata declares:
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
RUN /usr/local/bin/python3.12 -m pip install --no-cache-dir --root-user-action=ignore \
        "${PYWHISPERCPP_SPEC}" \
        "${BOTO3_SPEC}" \
        "${AMAZON_TRANSCRIBE_SPEC}" \
        "${PIPER_TTS_SPEC}" \
    && /usr/local/bin/python3.12 -c 'import pywhispercpp, boto3, amazon_transcribe, piper' \
    && command -v piper > /dev/null

# -----------------------------------------------------------------------------
# faiss-cpu — optional vector-search accelerator for the gateway's episodic
# memory recall. Without it kiro_crew falls back to a slower stdlib path
# (`kirocrew doctor` reports it as an optional, non-fatal miss). Installed into
# the same gateway interpreter; ships a prebuilt wheel (no compiler needed).
# -----------------------------------------------------------------------------
# renovate: datasource=pypi depName=faiss-cpu
ARG FAISS_CPU_SPEC='faiss-cpu>=1.9,<2'
RUN /usr/local/bin/python3.12 -m pip install --no-cache-dir --root-user-action=ignore \
        "${FAISS_CPU_SPEC}" \
    && /usr/local/bin/python3.12 -c 'import faiss'

# -----------------------------------------------------------------------------
# Node.js 22 via nvm. Installed to /opt/nvm (NOT the user's home) so a mounted
# /home/kirocrew data-home volume cannot shadow it, and the node/npm binaries
# are symlinked into /usr/local/bin so they resolve on the default PATH — even
# in a stripped `nerdctl/kata exec` shell that does not inherit the image ENV.
# Global npm packages install to /usr/local (prefix) for the same reasons.
# -----------------------------------------------------------------------------
USER root

# renovate: datasource=node-version depName=node
ARG NODE_VERSION='22.23.2'
# renovate: datasource=github-tags depName=nvm-sh/nvm extractVersion=^v(?<version>.+)$
ARG NVM_VERSION='0.40.4'
# renovate: datasource=npm depName=playwright
ARG PLAYWRIGHT_VERSION='1.63.0'

ENV NVM_DIR="/opt/nvm"
RUN mkdir -p "${NVM_DIR}" \
    && curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && nvm use default \
    # Expose node/npm/npx on the default PATH, outside any volume.
    && ln -sf "${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/node" /usr/local/bin/node \
    && ln -sf "${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/npm" /usr/local/bin/npm \
    && ln -sf "${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/npx" /usr/local/bin/npx \
    && node --version && npm --version

ENV NODE_PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/lib/node_modules"
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}"

# -----------------------------------------------------------------------------
# Corepack: manage Yarn 4.x and pnpm (bundled with Node.js). Shims are written
# to /usr/local/bin (default PATH, outside the volume).
# -----------------------------------------------------------------------------
# renovate: datasource=npm depName=@yarnpkg/cli-dist
ARG YARN_VERSION='4.18.0'
# renovate: datasource=npm depName=pnpm
ARG PNPM_VERSION='12.5.1'
RUN . "${NVM_DIR}/nvm.sh" \
    && corepack enable --install-directory /usr/local/bin \
    && corepack prepare "yarn@${YARN_VERSION}" --activate \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate \
    && /usr/local/bin/yarn --version \
    && /usr/local/bin/pnpm --version

# -----------------------------------------------------------------------------
# Global Node CLIs: Playwright, LikeC4, CALM CLI, and @playwright/cli (the
# `playwright-cli` KiroCrew browser rendering drives). They install into the
# nvm global bin under /opt (outside the volume); we symlink each into
# /usr/local/bin so they resolve on the default PATH (incl. stripped exec).
# -----------------------------------------------------------------------------
# renovate: datasource=npm depName=likec4
ARG LIKEC4_VERSION='1.59.3'
# renovate: datasource=npm depName=@finos/calm-cli
ARG CALM_CLI_VERSION='1.60.1'
# renovate: datasource=npm depName=@playwright/cli
ARG PLAYWRIGHT_CLI_VERSION='0.1.21'
RUN . "${NVM_DIR}/nvm.sh" \
    && npm install -g \
        "playwright@${PLAYWRIGHT_VERSION}" \
        "likec4@${LIKEC4_VERSION}" \
        "@finos/calm-cli@${CALM_CLI_VERSION}" \
        "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" \
    && npm cache clean --force \
    && nvm_bin="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin" \
    && for c in playwright playwright-cli likec4 calm; do \
         [ -e "${nvm_bin}/${c}" ] && ln -sf "${nvm_bin}/${c}" "/usr/local/bin/${c}"; \
       done \
    && command -v playwright playwright-cli likec4 > /dev/null

# Playwright browsers live OUTSIDE the home volume too, at a fixed path.
ENV PLAYWRIGHT_BROWSERS_PATH="/opt/ms-playwright"

# Install the browser OS dependencies as root (apt), driven by the pinned
# Playwright installed above (now on /usr/local/bin, the default PATH).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && playwright install-deps chromium firefox webkit \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download the browser binaries into the fixed non-volume cache. Run as root so
# they land under /opt/ms-playwright, then make them world-readable for the
# non-root runtime user.
RUN playwright install chromium firefox webkit \
    && playwright-cli install-browser chromium \
    && chmod -R a+rX /opt/ms-playwright

# -----------------------------------------------------------------------------
# LaTeX toolchain (TinyTeX) for compiling CVs / cover letters.
# ref: https://github.com/fjudith/ai-job-search/blob/master/SETUP.md
#      (#minimal-tex-install-tinytexbasictex)
# User-level, minimal TeX Live providing `lualatex` (CV) and `xelatex` (cover
# letter), plus the CTAN packages the stock templates require.
# -----------------------------------------------------------------------------
# renovate: datasource=github-releases depName=rstudio/tinytex-releases versioning=loose extractVersion=^v(?<version>.+)$
ARG TINYTEX_VERSION='2026.09'
# The installer always creates ${TINYTEX_DIR}/.TinyTeX on Linux, so TINYTEX_DIR=/opt
# yields /opt/.TinyTeX (outside the /home volume).
ENV PATH="/opt/.TinyTeX/bin/x86_64-linux:${PATH}"
RUN set -e \
    && wget -qO /tmp/install-tinytex.sh "https://yihui.org/tinytex/install-bin-unix.sh" \
    && TINYTEX_VERSION="${TINYTEX_VERSION}" TINYTEX_DIR=/opt sh /tmp/install-tinytex.sh \
    && rm -f /tmp/install-tinytex.sh \
    && export PATH="/opt/.TinyTeX/bin/x86_64-linux:${PATH}" \
    # Fail the build if TinyTeX did not install correctly.
    && command -v tlmgr \
    && tlmgr install \
        moderncv fontawesome5 fontawesome6 academicons import luatexbase pgf \
        titlesec textpos xltxtra xunicode cite realscripts needspace \
    # Symlink the TeX binaries onto the default PATH, outside any volume.
    && for b in /opt/.TinyTeX/bin/x86_64-linux/*; do ln -sf "$b" "/usr/local/bin/$(basename "$b")"; done \
    && lualatex --version > /dev/null \
    && xelatex --version > /dev/null

# -----------------------------------------------------------------------------
# Bun (runtime for the ai-job-search job-portal CLIs), pinned for reproducibility.
# -----------------------------------------------------------------------------
# renovate: datasource=github-releases depName=oven-sh/bun extractVersion=^bun-v(?<version>.+)$
ARG BUN_VERSION='1.4.2'
ENV BUN_INSTALL="/opt/bun"
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && ln -sf "${BUN_INSTALL}/bin/bun" /usr/local/bin/bun \
    && ln -sf "${BUN_INSTALL}/bin/bun" /usr/local/bin/bunx \
    && /usr/local/bin/bun --version

# -----------------------------------------------------------------------------
# All tool binaries are symlinked into /usr/local/bin (on the base PATH), so
# they resolve even in a stripped `nerdctl/kata exec` shell and are never
# shadowed by a /home/kirocrew volume. This profile.d snippet additionally
# exports NVM_DIR (so the `nvm` command works to switch Node versions) and puts
# the /opt bin dirs on PATH for login/interactive shells.
# -----------------------------------------------------------------------------
USER root
RUN printf '%s\n' \
    '# Added by the kirocrew custom image (see images/kirocrew/Dockerfile)' \
    'export NVM_DIR="/opt/nvm"' \
    'export BUN_INSTALL="/opt/bun"' \
    'export PLAYWRIGHT_BROWSERS_PATH="/opt/ms-playwright"' \
    'export PATH="/opt/nvm/versions/node/v'"${NODE_VERSION}"'/bin:/opt/bun/bin:/opt/.TinyTeX/bin/x86_64-linux:${PATH}"' \
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
      org.opencontainers.image.description="Custom Kiro Crew image built on the official kirocrew base, adding Node.js 22 (nvm), Corepack Yarn 4.x/pnpm, Playwright + @playwright/cli (browser rendering), LikeC4 CLI, CALM CLI, pdftotext, TinyTeX (lualatex/xelatex), Bun, the ffmpeg audio decoder, the KiroCrew [voice] Python extra (pywhispercpp/boto3/amazon-transcribe + piper-tts) and faiss-cpu (episodic-memory accelerator)." \
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

# Point the gateway at kiro-cli by ABSOLUTE path. Unattended spawns (channel
# bots, scheduled tasks) do not trust PATH, so without this the gateway skips
# the kiro-cli version check and logs a warning. The base image installs
# kiro-cli at /usr/local/bin/kiro-cli.
ENV KIROCREW_KIRO_BIN=/usr/local/bin/kiro-cli

# Keep the base image's ENTRYPOINT (`kirocrew-entrypoint`) and CMD (`gateway`)
# and its non-root user / workdir, so the container still runs the Kiro Crew
# gateway — now with the extra tooling on PATH.
USER ${APP_UID}
WORKDIR /home/${APP_USER}
