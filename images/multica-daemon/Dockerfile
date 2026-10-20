# syntax=docker/dockerfile:1
# =============================================================================
# Multica daemon container image
#
# Node.js LTS base + the `multica` CLI (daemon mode) + `kiro-cli` (the ACP
# coding agent the daemon drives). Built for ALIT-10 (CI pipeline), consumed
# by the ECS Fargate task definition in alithya-oss/multica-on-aws
# (infrastructure/cloudformation/compute.yaml).
#
# The daemon itself is outbound-only (HTTPS poll + heartbeat to the Multica
# server, see ALIT-4/ALIT-7) — no port is EXPOSEd. It persists local state
# under ~/.multica (config/token/logs/pid) and MULTICA_WORKSPACES_ROOT
# (repo checkouts/cache), both expected to be mounted from the EFS volume
# configured in compute.yaml at /home/multica/.multica-state.
#
# Hardening: non-root user (UID 1000, matching the alithya-oss/containers
# convention used by images/kirocrew), pinned base image + tool versions, no
# secrets baked into layers (the Multica auth token is injected at runtime via
# ECS `secrets` from Secrets Manager — see ALIT-7 §3 / ALIT-9 compute.yaml),
# minimal apt surface, OCI traceability labels, HEALTHCHECK.
# =============================================================================

# renovate: datasource=docker depName=node versioning=node
ARG NODE_VERSION='22.20.0-bookworm-slim'
FROM docker.io/library/node:${NODE_VERSION}

ARG APP_USER="multica"
ARG APP_UID="1000"
ARG APP_GID="1000"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# OS dependencies needed to install/run the two CLIs and for basic daemon
# operation (git: repo checkouts under MULTICA_WORKSPACES_ROOT; ca-certificates:
# TLS to the Multica server/GitHub/npm; tini: PID 1 zombie reaping for a
# long-running daemon process).
# -----------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && apt-get install -yqq --no-install-recommends \
        'ca-certificates' \
        'curl' \
        'git' \
        'tini' \
        'unzip' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Non-root runtime user. The node base image already ships a `node` user at
# UID 1000; create a distinct `multica` user/group instead so the image's
# identity is self-descriptive and not tied to the base image's convention.
# -----------------------------------------------------------------------------
RUN groupadd --gid "${APP_GID}" "${APP_USER}" \
    && useradd --uid "${APP_UID}" --gid "${APP_GID}" --create-home --shell /bin/bash "${APP_USER}"

# -----------------------------------------------------------------------------
# kiro-cli — the ACP coding agent the daemon drives (ALIT-4 context tech,
# ALIT-6 functional requirement: "au moins un CLI agent ACP installé sur
# PATH"). Installed via the official installer into /opt (outside the
# /home/multica EFS mount, so a mounted state volume can never shadow it) and
# symlinked onto the default PATH so it resolves for the daemon's unattended
# process spawns.
# -----------------------------------------------------------------------------
ENV KIRO_CLI_INSTALL_DIR="/opt/kiro-cli"
RUN mkdir -p "${KIRO_CLI_INSTALL_DIR}" \
    && curl -fsSL https://cli.kiro.dev/install \
        | KIRO_INSTALL_DIR="${KIRO_CLI_INSTALL_DIR}" bash \
    && find "${KIRO_CLI_INSTALL_DIR}" -maxdepth 2 -iname 'kiro-cli' -type f -exec ln -sf {} /usr/local/bin/kiro-cli \; \
    && command -v kiro-cli \
    && kiro-cli --version

# -----------------------------------------------------------------------------
# multica CLI — connects this machine to the Multica platform and runs the
# agent daemon (ALIT-4). Distributed as a GitHub Releases binary archive
# (multica-ai/multica), not via npm/apt — installed into /opt and symlinked to
# /usr/local/bin for the same "survives a mounted home volume" reason as
# kiro-cli above.
# -----------------------------------------------------------------------------
# renovate: datasource=github-releases depName=multica-ai/multica extractVersion=^v(?<version>.+)$
ARG MULTICA_CLI_VERSION='0.1.0'
RUN set -e \
    && arch="$(case "$(dpkg --print-architecture)" in arm64) echo arm64;; *) echo amd64;; esac)" \
    && mkdir -p /opt/multica \
    && curl -fsSL -o /tmp/multica.tar.gz \
        "https://github.com/multica-ai/multica/releases/download/v${MULTICA_CLI_VERSION}/multica-cli-${MULTICA_CLI_VERSION}-linux-${arch}.tar.gz" \
    && tar -xzf /tmp/multica.tar.gz -C /opt/multica multica \
    && ln -sf /opt/multica/multica /usr/local/bin/multica \
    && rm -f /tmp/multica.tar.gz \
    && chmod 0755 /opt/multica/multica \
    && multica version

# -----------------------------------------------------------------------------
# Daemon state directories. The real mount points (EFS, per compute.yaml) are
# bound at container start by the orchestrator; these are created here only so
# the image is self-contained and runnable standalone (e.g. local `docker run`
# smoke test) without the volume present. Owned by the non-root app user.
# -----------------------------------------------------------------------------
ENV HOME="/home/${APP_USER}" \
    MULTICA_WORKSPACES_ROOT="/home/${APP_USER}/.multica-state/workspaces"
RUN mkdir -p "${HOME}/.multica" "${MULTICA_WORKSPACES_ROOT}" \
    && chown -R "${APP_UID}:${APP_GID}" "${HOME}"

# -----------------------------------------------------------------------------
# OCI traceability annotations. Fed by CI:
#   --build-arg VCS_REF=$(git rev-parse HEAD) --build-arg BUILD_DATE=...
# -----------------------------------------------------------------------------
ARG VERSION="0.0.1"
ARG VCS_REF="unknown"
ARG BUILD_DATE="unknown"
LABEL org.opencontainers.image.title="multica-daemon" \
      org.opencontainers.image.description="Node.js LTS base image running the Multica CLI agent daemon with kiro-cli (ACP coding agent) on PATH, for the ECS Fargate deployment of the Multica/Kiro-CLI daemon on AWS." \
      org.opencontainers.image.base.name="docker.io/library/node:${NODE_VERSION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.url="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.documentation="https://github.com/alithya-oss/containers/blob/main/images/multica-daemon/README.md" \
      org.opencontainers.image.authors="Alithya Open Source Software" \
      org.opencontainers.image.vendor="Alithya" \
      org.opencontainers.image.licenses="Apache-2.0"

# Liveness check matching the ECS task definition's own health check
# (compute.yaml): confirm the daemon process is actually running, not just
# that the container process tree is alive.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep -f 'multica daemon' > /dev/null || exit 1

USER ${APP_UID}
WORKDIR "/home/${APP_USER}"

# tini as PID 1 reaps zombie processes spawned by the daemon's own child agent
# sessions over a long-running container lifetime.
ENTRYPOINT ["tini", "-g", "--"]
CMD ["multica", "daemon", "start", "--foreground"]
