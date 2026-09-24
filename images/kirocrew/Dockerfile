# syntax=docker/dockerfile:1
# =============================================================================
# Kirocrew custom container image
#
# Built on the official Kiro Crew base image (gateway, entrypoint, Python 3.12),
# layering the extra tooling the agent needs:
#   - Node.js 22 (nvm) + Corepack Yarn 4.x / pnpm
#   - Playwright + browsers, @playwright/cli (browser rendering)
#   - LikeC4 CLI, CALM CLI (@finos/calm-cli)
#   - pdftotext (poppler-utils), TinyTeX (lualatex/xelatex)
#   - Bun (ai-job-search CLIs), ffmpeg (voice STT decoder)
#   - KiroCrew [voice] Python extra (pywhispercpp/boto3/amazon-transcribe + piper-tts)
#   - faiss-cpu (episodic-memory accelerator)
#
# Hardening: keeps the base non-root `kirocrew` user (UID 1000), pinned base
# image + tool versions, no secrets in layers, preserves the upstream entrypoint.
# =============================================================================

# renovate: datasource=docker depName=ghcr.io/kirodotdev/kirocrew
ARG KIROCREW_BASE_TAG='0.6.0'
FROM ghcr.io/kirodotdev/kirocrew:${KIROCREW_BASE_TAG}@sha256:ba01bb1c75ea454af2b53773f39c3b38899f0d1d9ab51a0eb97001df6db27407

ARG APP_USER="kirocrew"
ARG APP_UID="1000"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# Additional OS dependencies (installed as root).
#   - poppler-utils -> pdftotext; perl/xz-utils -> TinyTeX installer
#   - ffmpeg -> KiroCrew voice STT audio decoder
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
        'xz-utils' \
        'poppler-utils' \
        'ffmpeg' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# KiroCrew [voice] Python extra, installed into the gateway's interpreter via
# `/usr/local/bin/python3.12 -m pip` so packages land in the gateway
# site-packages. KiroCrew is not on PyPI, so install the extra's distributions
# with the ranges the wheel metadata declares (voice + voice-aws), plus
# piper-tts for local Text-to-Speech. All resolve to prebuilt wheels.
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
# faiss-cpu — optional vector-search accelerator for episodic memory recall
# (kiro_crew falls back to a slower stdlib path without it). Prebuilt wheel.
# -----------------------------------------------------------------------------
# renovate: datasource=pypi depName=faiss-cpu
ARG FAISS_CPU_SPEC='faiss-cpu>=1.9,<2'
RUN /usr/local/bin/python3.12 -m pip install --no-cache-dir --root-user-action=ignore \
        "${FAISS_CPU_SPEC}" \
    && /usr/local/bin/python3.12 -c 'import faiss'

# -----------------------------------------------------------------------------
# Node.js 22 via nvm, installed to /opt/nvm (not the user's home) so a mounted
# /home/kirocrew volume cannot shadow it. node/npm/npx are symlinked into
# /usr/local/bin so they resolve on the default PATH, even in a stripped exec
# shell. Global npm packages use /usr/local as prefix for the same reason.
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
    && ln -sf "${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/node" /usr/local/bin/node \
    && ln -sf "${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/npm" /usr/local/bin/npm \
    && ln -sf "${NVM_DIR}/versions/node/v${NODE_VERSION}/bin/npx" /usr/local/bin/npx \
    && node --version && npm --version

ENV NODE_PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/lib/node_modules"
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}"

# -----------------------------------------------------------------------------
# Corepack-managed Yarn 4.x and pnpm; shims written to /usr/local/bin.
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
# Global Node CLIs (Playwright, LikeC4, CALM, @playwright/cli), installed under
# /opt and symlinked into /usr/local/bin so they resolve on the default PATH.
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

# Playwright browsers live outside the home volume, at a fixed path.
ENV PLAYWRIGHT_BROWSERS_PATH="/opt/ms-playwright"

# Browser OS dependencies (apt), driven by the pinned Playwright.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && playwright install-deps chromium firefox webkit \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Browser binaries into the fixed non-volume cache (as root), made
# world-readable for the non-root runtime user.
RUN playwright install chromium firefox webkit \
    && playwright-cli install-browser chromium \
    && chmod -R a+rX /opt/ms-playwright

# -----------------------------------------------------------------------------
# LaTeX toolchain (TinyTeX) for compiling CVs / cover letters.
# ref: https://github.com/fjudith/ai-job-search/blob/master/SETUP.md
# Minimal TeX Live providing `lualatex` (CV) and `xelatex` (cover letter) plus
# the CTAN packages the stock templates require. The installer creates
# ${TINYTEX_DIR}/.TinyTeX, so TINYTEX_DIR=/opt yields /opt/.TinyTeX.
# -----------------------------------------------------------------------------
# renovate: datasource=github-releases depName=rstudio/tinytex-releases versioning=loose extractVersion=^v(?<version>.+)$
ARG TINYTEX_VERSION='2026.09'
ENV PATH="/opt/.TinyTeX/bin/x86_64-linux:${PATH}"
RUN set -e \
    && wget -qO /tmp/install-tinytex.sh "https://yihui.org/tinytex/install-bin-unix.sh" \
    && TINYTEX_VERSION="${TINYTEX_VERSION}" TINYTEX_DIR=/opt sh /tmp/install-tinytex.sh \
    && rm -f /tmp/install-tinytex.sh \
    && export PATH="/opt/.TinyTeX/bin/x86_64-linux:${PATH}" \
    && command -v tlmgr \
    && tlmgr install \
        moderncv fontawesome5 fontawesome6 academicons import luatexbase pgf \
        titlesec textpos xltxtra xunicode cite realscripts needspace \
    && for b in /opt/.TinyTeX/bin/x86_64-linux/*; do ln -sf "$b" "/usr/local/bin/$(basename "$b")"; done \
    && lualatex --version > /dev/null \
    && xelatex --version > /dev/null

# -----------------------------------------------------------------------------
# Bun (runtime for the ai-job-search job-portal CLIs), pinned.
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
# Tool env: exports NVM_DIR + the /opt bin dirs on PATH and sources nvm.sh so
# the `nvm` shell function is defined. Shipped as a dedicated script (see
# files/etc/profile.d/99-kirocrew-tools.sh) copied into the image.
#
# profile.d is read only by LOGIN shells, so a plain `nerdctl exec kirocrew
# bash` (non-login) would not get `nvm`. The script is sourced from BOTH:
#   - /etc/profile.d/99-kirocrew-tools.sh -> login shells (bash -l, ssh)
#   - /etc/bash.bashrc                    -> interactive non-login bash (exec -it)
# node/npm/bun/latex binaries are also symlinked into /usr/local/bin, so they
# resolve even in a non-interactive stripped exec shell that reads neither file.
# -----------------------------------------------------------------------------
USER root
COPY files/etc/profile.d/99-kirocrew-tools.sh /etc/profile.d/99-kirocrew-tools.sh
RUN chmod a+r /etc/profile.d/99-kirocrew-tools.sh \
    && printf '%s\n' \
        '' \
        '# Added by the kirocrew custom image (see images/kirocrew/Dockerfile)' \
        '[ -r /etc/profile.d/99-kirocrew-tools.sh ] && . /etc/profile.d/99-kirocrew-tools.sh' \
        >> /etc/bash.bashrc
USER ${APP_UID}

# -----------------------------------------------------------------------------
# OCI traceability annotations. Fed by CI:
#   --build-arg VCS_REF=$(git rev-parse HEAD) --build-arg BUILD_DATE=...
# -----------------------------------------------------------------------------
# Re-declare after FROM so the base tag is in scope for the LABEL below.
ARG KIROCREW_BASE_TAG
ARG VERSION="0.0.1"
ARG VCS_REF="unknown"
ARG BUILD_DATE="unknown"
LABEL org.opencontainers.image.title="kirocrew" \
      org.opencontainers.image.description="Custom Kiro Crew image built on the official kirocrew base, adding Node.js 22 (nvm), Corepack Yarn 4.x/pnpm, Playwright + @playwright/cli (browser rendering), LikeC4 CLI, CALM CLI, pdftotext, TinyTeX (lualatex/xelatex), Bun, the ffmpeg audio decoder, the KiroCrew [voice] Python extra (pywhispercpp/boto3/amazon-transcribe + piper-tts) and faiss-cpu (episodic-memory accelerator)." \
      org.opencontainers.image.base.name="ghcr.io/kirodotdev/kirocrew:${KIROCREW_BASE_TAG}" \
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

# Point the gateway at kiro-cli by ABSOLUTE path: unattended spawns do not trust
# PATH, so without this the gateway skips the version check and logs a warning.
ENV KIROCREW_KIRO_BIN=/usr/local/bin/kiro-cli

# Keep the base image's ENTRYPOINT (`kirocrew-entrypoint`) / CMD (`gateway`) and
# non-root user / workdir, now with the extra tooling on PATH.
USER ${APP_UID}
WORKDIR /home/${APP_USER}
