# syntax=docker/dockerfile:1
# =============================================================================
# Kirocrew custom container image
# -----------------------------------------------------------------------------
# Embeds the toolchain required to run every tool shipped with Kiro Crew:
#   - Node.js 22 managed through nvm (agent can target the right version)
#   - Python 3 (via micromamba, aligned with the other images in this repo)
#   - Playwright (browser automation for the Settings/Browser feature)
#   - LikeC4 CLI (architecture-as-code diagrams)
#   - CALM CLI (@finos/calm-cli, Common Architecture Language Model)
#   - pdftotext (poppler-utils)
#   - TinyTeX (lualatex/xelatex) for compiling CVs / cover letters
#   - Bun (runtime for the ai-job-search job-portal CLIs)
#
# Hardening follows the OWASP Docker Security Cheat Sheet:
#   - runs as a non-root user (USER)
#   - pinned base image, tool versions and apt packages
#   - no secrets baked into layers (build args carry only public metadata)
#   - tini as PID 1 to reap zombies
#   - HEALTHCHECK for orchestrator liveness
# Traceability follows the OCI image annotations spec (see LABEL block).
# =============================================================================
FROM docker.io/amd64/ubuntu:24.04

ARG NON_ROOT_USER="cicd"
ARG NON_ROOT_UID="10000"
ARG NON_ROOT_GID="10000"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
# Fix: https://github.com/koalaman/shellcheck/wiki/SC3014
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# -----------------------------------------------------------------------------
# Base OS dependencies
# `pdftotext` is provided by `poppler-utils`.
# -----------------------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    # - `apt-get upgrade` patches known vulnerabilities in system packages
    #   as the Ubuntu base image is rebuilt too seldom (OWASP: patch base image)
    && apt-get upgrade -yqq \
    && apt-get install -yqq \
        'software-properties-common' \
        'ca-certificates' \
        'locales' \
        # - `netbase` provides /etc/{protocols,rpc,services}, part of POSIX
        'netbase' \
        'sudo' \
        # - `tini` reaps zombie processes as PID 1
        'tini' \
        'git' \
        'gnupg' \
        'jq' \
        'dnsutils' \
        'iputils-ping' \
        'curl' \
        'wget' \
        'unzip' \
        # - `perl` is required by the TinyTeX installer
        'perl' \
        # - `poppler-utils` provides `pdftotext`
        'poppler-utils' \
        'build-essential' \
        'libffi-dev' \
    && apt-get autoremove -y --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && echo "C.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NON_ROOT_USER="${NON_ROOT_USER}" \
    NON_ROOT_UID=${NON_ROOT_UID} \
    NON_ROOT_GID=${NON_ROOT_GID} \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}" \
    HOME="/home/${NON_ROOT_USER}"

# Copy a script that we will use to correct permissions after running certain commands
COPY scripts/fix-permissions.sh /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NON_ROOT_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc \
    && echo 'eval "$(conda shell.bash hook)"' >> /etc/skel/.bashrc

# Create the non-root user (OWASP: never run as root).
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
    && sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers \
    && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
    && useradd --no-log-init --create-home --shell /bin/bash --uid "${NON_ROOT_UID}" --no-user-group "${NON_ROOT_USER}" \
    && mkdir -p "${CONDA_DIR}" \
    && chown "${NON_ROOT_USER}:${NON_ROOT_GID}" "${CONDA_DIR}" \
    && chmod g+w /etc/passwd \
    && fix-permissions "${CONDA_DIR}" \
    && fix-permissions "/home/${NON_ROOT_USER}"

# -----------------------------------------------------------------------------
# Node.js 22 and Playwright toolchain versions.
# -----------------------------------------------------------------------------
ARG NODE_VERSION='22.23.2'
ARG NVM_VERSION='0.40.4'
ARG PLAYWRIGHT_VERSION='1.63.0'

USER ${NON_ROOT_UID}

# Setup work directory
RUN mkdir -p "/home/${NON_ROOT_USER}/work" \
    && fix-permissions "/home/${NON_ROOT_USER}"

# -----------------------------------------------------------------------------
# Python 3 via micromamba (aligned with the other images in this repository).
# -----------------------------------------------------------------------------
ARG PYTHON_VERSION='3.12'
COPY --chown="${NON_ROOT_UID}:${NON_ROOT_GID}" files/initial-condarc "${CONDA_DIR}/.condarc"
WORKDIR /tmp
RUN set -x \
    && export MAMBA_ROOT_PREFIX="${CONDA_DIR}" \
    && export CONDA_PKGS_DIRS="${CONDA_DIR}/pkgs" \
    && arch="$(uname -m)" \
    && if [ "${arch}" = "x86_64" ]; then arch="64"; fi \
    && wget --progress=dot:giga -O - \
        "https://micro.mamba.pm/api/micromamba/linux-${arch}/latest" | tar -xvj bin/micromamba \
    && PYTHON_SPECIFIER="python=${PYTHON_VERSION}" \
    && if [[ "${PYTHON_VERSION}" == "default" ]]; then PYTHON_SPECIFIER="python"; fi \
    && ./bin/micromamba install \
        --root-prefix="${CONDA_DIR}" \
        --prefix="${CONDA_DIR}" \
        --yes \
        'pip' \
        'mamba<2.0.0' \
        "${PYTHON_SPECIFIER}" \
    && rm -rf /tmp/bin/ \
    && mamba list --full-name 'python' | awk 'END{sub("[^.]*$", "*", $2); print $1 " " $2}' >> "${CONDA_DIR}/conda-meta/pinned" \
    && mamba clean --all -f -y \
    && rm -rf "/home/${NON_ROOT_USER}/.mamba" \
    && fix-permissions "${CONDA_DIR}" \
    && fix-permissions "/home/${NON_ROOT_USER}"

# -----------------------------------------------------------------------------
# Node.js 22 via nvm (agent can target the adequate version).
# -----------------------------------------------------------------------------
RUN curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash \
    && source "/home/${NON_ROOT_USER}/.nvm/nvm.sh" \
    && nvm install "${NODE_VERSION}" \
    && nvm alias default "${NODE_VERSION}" \
    && nvm use default \
    && npm install -g yarn

ENV NVM_DIR="/home/${NON_ROOT_USER}/.nvm"
ENV NODE_PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/lib/node_modules"
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:${PATH}"

# -----------------------------------------------------------------------------
# Global Node CLIs: Playwright, LikeC4, CALM CLI.
# Pinned versions for reproducibility (OWASP: pin versions).
# -----------------------------------------------------------------------------
ARG LIKEC4_VERSION='1.59.3'
ARG CALM_CLI_VERSION='1.60.1'
RUN source "${NVM_DIR}/nvm.sh" \
    && npm install -g \
        "playwright@${PLAYWRIGHT_VERSION}" \
        "likec4@${LIKEC4_VERSION}" \
        "@finos/calm-cli@${CALM_CLI_VERSION}" \
    && npm cache clean --force

# Install the browser OS dependencies as root (apt), driven by the pinned
# Playwright installed above (nvm Node 22, on the inherited PATH).
USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && playwright install-deps chromium firefox webkit \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download the browser binaries into the user's cache (non-root).
# The cache is already owned by this user, so no permission fix is needed.
USER ${NON_ROOT_UID}
RUN playwright install chromium firefox webkit

# -----------------------------------------------------------------------------
# LaTeX toolchain (TinyTeX) for compiling CVs / cover letters.
# ref: https://github.com/fjudith/ai-job-search/blob/master/SETUP.md
#      (#minimal-tex-install-tinytexbasictex)
# TinyTeX is a user-level, minimal TeX Live distribution (no sudo needed),
# providing `lualatex` (CV) and `xelatex` (cover letter). The extra CTAN
# packages below are the ones the stock templates require.
# -----------------------------------------------------------------------------
ARG TINYTEX_VERSION='2026.09'
ENV PATH="/home/${NON_ROOT_USER}/.TinyTeX/bin/x86_64-linux:${PATH}"
RUN set -e \
    && export PATH="/home/${NON_ROOT_USER}/.TinyTeX/bin/x86_64-linux:${PATH}" \
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
# Bun (runtime for the ai-job-search job-portal CLIs).
# ref: https://github.com/fjudith/ai-job-search/blob/master/SETUP.md
# Pinned version for reproducibility (OWASP: pin versions).
# -----------------------------------------------------------------------------
ARG BUN_VERSION='1.4.2'
ENV BUN_INSTALL="/home/${NON_ROOT_USER}/.bun"
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && bun --version

# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------
USER root
COPY scripts/run-hooks.sh scripts/entrypoint.sh /usr/local/bin/
RUN chmod a+rx /usr/local/bin/run-hooks.sh /usr/local/bin/entrypoint.sh \
    && fix-permissions "/usr/local/bin/"

# OCI traceability annotations.
# Values marked with build args are meant to be fed by CI:
#   --build-arg VCS_REF=$(git rev-parse HEAD) --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ARG VERSION="0.0.1"
ARG VCS_REF="unknown"
ARG BUILD_DATE="unknown"
LABEL org.opencontainers.image.title="kirocrew" \
      org.opencontainers.image.description="Custom Kiro Crew image bundling Node.js 22 (nvm), Python 3, Playwright, LikeC4 CLI, CALM CLI, pdftotext, TinyTeX (lualatex/xelatex) and Bun." \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.url="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.documentation="https://github.com/alithya-oss/containers/blob/main/images/kirocrew/README.md" \
      org.opencontainers.image.authors="Alithya Open Source Software" \
      org.opencontainers.image.vendor="Alithya" \
      org.opencontainers.image.licenses="Apache-2.0"

# Liveness check: confirm the core toolchain is reachable.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node --version && python --version || exit 1

ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["bash"]

USER ${NON_ROOT_UID}
WORKDIR "/home/${NON_ROOT_USER}/work"
