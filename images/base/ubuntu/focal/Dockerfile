FROM docker.io/amd64/ubuntu:focal

ARG NON_ROOT_USER="cicd"
ARG NON_ROOT_UID="10000"
ARG NON_ROOT_GID="10000"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
# Fix: https://github.com/koalaman/shellcheck/wiki/SC3014
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install all OS dependencies for the Server that starts
# but lacks all features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    # - `apt-get upgrade` is run to patch known vulnerabilities in system packages
    #   as the Ubuntu base image is rebuilt too seldom sometimes (less than once a month)
    && apt-get upgrade -yqq \
    && apt-get install -yqq \
        'software-properties-common' \
        'ca-certificates' \
        'locales' \
        # - `netbase` provides /etc/{protocols,rpc,services}, part of POSIX
        #   and required by various C functions like getservbyname and getprotobyname
        #   https://github.com/jupyter/docker-stacks/pull/2129
        'netbase' \
        'sudo' \
        # - `tini` is installed as a helpful container entrypoint,
        #   that reaps zombie processes and such of the actual executable we want to start
        #   See https://github.com/krallin/tini#why-tini for details
        'tini' \
    && apt-get autoremove -y --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen  \
    && echo "C.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen
