# syntax=docker/dockerfile:1
# =============================================================================
# multica-kiro-daemon container image
#
# Runs the Multica agent daemon (`multica daemon start --foreground`) with
# Kiro CLI (`kiro-cli`) as its ACP coding-agent backend, on a Node.js LTS
# base (the daemon executes Node.js/TypeScript development tasks per ALIT-4).
# Built for the ECS Fargate service designed in ALIT-9
# (infrastructure/cloudformation/compute.yaml in alithya-oss/multica-on-aws):
# published to the ECR repository from ALIT-9's ecr.yaml, not GHCR.
#
# Hardening: non-root `multica` user (UID/GID 1000 — matches the EFS access
# point's POSIX identity in storage-security.yaml), pinned base image + tool
# versions, no secrets in layers (the auth token is injected at runtime via
# ECS `secrets`, consumed by scripts/entrypoint.sh — never a build arg).
# =============================================================================

# renovate: datasource=docker depName=node
ARG NODE_VERSION='22.21.1-bookworm-slim'
FROM docker.io/library/node:${NODE_VERSION}

ARG APP_USER="multica"
ARG APP_UID="1000"
ARG APP_GID="1000"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# OS dependencies: ca-certificates/curl for the installers below; git for the
# daemon's own repo checkouts (MULTICA_WORKSPACES_ROOT); procps for `pgrep`,
# used by the container HEALTHCHECK and by ECS's own health check in
# compute.yaml (`pgrep -f 'multica daemon'`).
# -----------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && apt-get install -yqq --no-install-recommends \
        'ca-certificates' \
        'curl' \
        'git' \
        'procps' \
        'unzip' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Non-root runtime user. UID/GID 1000 matches the EFS access point's fixed
# POSIX identity (storage-security.yaml) so the mounted state directory
# (~/.multica, MULTICA_WORKSPACES_ROOT) is writable without a runtime chown.
# The node:* base image already defines a `node` user at 1000:1000; renamed
# to `multica` for clarity in this image rather than reusing it as-is.
# -----------------------------------------------------------------------------
RUN usermod -l "${APP_USER}" -d "/home/${APP_USER}" -m node \
    && groupmod -n "${APP_USER}" node

# -----------------------------------------------------------------------------
# Multica CLI + daemon — GitHub Releases binary (Option B of CLI_INSTALL.md;
# Homebrew is not used in a minimal container base). Installed under /opt,
# outside the home volume that EFS will mount over at runtime, and symlinked
# into /usr/local/bin so it resolves on PATH even if the home dir is replaced
# by the mount.
# -----------------------------------------------------------------------------
# renovate: datasource=github-releases depName=multica-ai/multica extractVersion=^v(?<version>.+)$
ARG MULTICA_VERSION='0.6.4'
RUN set -e \
    && arch="$(case "$(dpkg --print-architecture)" in arm64) echo arm64;; *) echo amd64;; esac)" \
    && mkdir -p /opt/multica \
    && curl -fsSL -o /tmp/multica.tar.gz \
        "https://github.com/multica-ai/multica/releases/download/v${MULTICA_VERSION}/multica-cli-${MULTICA_VERSION}-linux-${arch}.tar.gz" \
    && tar -xzf /tmp/multica.tar.gz -C /opt/multica multica \
    && rm -f /tmp/multica.tar.gz \
    && chmod 0755 /opt/multica/multica \
    && ln -sf /opt/multica/multica /usr/local/bin/multica \
    && multica version

# -----------------------------------------------------------------------------
# Kiro CLI — official installer, run as the non-root user so the install
# lands in a user-writable location the daemon can execute without root.
# MULTICA_KIRO_PATH is set so the daemon finds it by absolute path regardless
# of PATH state in a spawned task shell (mirrors the kirocrew image's
# KIROCREW_KIRO_BIN pattern for the same reason: unattended spawns do not
# always trust PATH).
# -----------------------------------------------------------------------------
USER ${APP_UID}
RUN curl -fsSL https://cli.kiro.dev/install | bash
USER root
RUN kiro_bin="$(su - "${APP_USER}" -c 'command -v kiro-cli')" \
    && ln -sf "${kiro_bin}" /usr/local/bin/kiro-cli \
    && kiro-cli --version
ENV MULTICA_KIRO_PATH=/usr/local/bin/kiro-cli

# -----------------------------------------------------------------------------
# Entrypoint: bridges the ECS-injected MULTICA_TOKEN secret into
# `multica login --token`, then execs the foreground daemon as PID 1 (see
# scripts/entrypoint.sh for the full rationale).
# -----------------------------------------------------------------------------
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/multica-daemon-entrypoint

# -----------------------------------------------------------------------------
# OCI traceability annotations. Fed by CI:
#   --build-arg VCS_REF=$(git rev-parse HEAD) --build-arg BUILD_DATE=...
# -----------------------------------------------------------------------------
ARG VERSION="0.0.1"
ARG VCS_REF="unknown"
ARG BUILD_DATE="unknown"
LABEL org.opencontainers.image.title="multica-kiro-daemon" \
      org.opencontainers.image.description="Multica agent daemon (multica-ai/multica) running on Node.js LTS with Kiro CLI (kiro-cli) as its ACP coding-agent backend. Built for the ECS Fargate deployment designed in ALIT-9 (alithya-oss/multica-on-aws)." \
      org.opencontainers.image.base.name="docker.io/library/node:${NODE_VERSION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.url="https://github.com/alithya-oss/containers" \
      org.opencontainers.image.documentation="https://github.com/alithya-oss/containers/blob/main/images/multica-kiro-daemon/README.md" \
      org.opencontainers.image.authors="Alithya Open Source Software" \
      org.opencontainers.image.vendor="Alithya" \
      org.opencontainers.image.licenses="Apache-2.0"

# Liveness check: the ECS task definition (compute.yaml) runs its own
# `pgrep -f 'multica daemon'` container health check; this HEALTHCHECK gives
# the same signal to a plain `docker run` / local Compose use.
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD pgrep -f 'multica daemon' || exit 1

USER ${APP_UID}
WORKDIR /home/${APP_USER}
ENTRYPOINT ["/usr/local/bin/multica-daemon-entrypoint"]
