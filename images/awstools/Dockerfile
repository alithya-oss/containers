FROM docker.io/amd64/ubuntu:24.04

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
        'git' \
        'gnupg' \
        'jq' \
        'yq' \
        'dnsutils' \
        'iputils-ping' \
        'netcat-traditional' \
        'curl' \
        'wget' \
        'unzip' \
        'libcurl4' \
        'libunwind8' \
        'libssl1.0' \
        \
        'build-essential' \
        'checkinstall' \
        'libffi-dev' \
    && apt-get autoremove -y --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen  \
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
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
    # More information in: https://github.com/jupyter/docker-stacks/pull/2047
    # and docs: https://docs.conda.io/projects/conda/en/latest/dev-guide/deep-dives/activation.html
    echo 'eval "$(conda shell.bash hook)"' >> /etc/skel/.bashrc

# Enable prompt color in the skeleton .bashrc before creating the default NON_ROOT_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
    # More information in: https://github.com/jupyter/docker-stacks/pull/2047
    # and docs: https://docs.conda.io/projects/conda/en/latest/dev-guide/deep-dives/activation.html
    echo 'eval "$(conda shell.bash hook)"' >> /etc/skel/.bashrc

# Create "${NON_ROOT_USER}" user (`jovyan` by default) with UID="${NON_ROOT_UID}" (`1000` by default) and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su \
    && sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers \
    && sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers \
    && useradd --no-log-init --create-home --shell /bin/bash --uid "${NON_ROOT_UID}" --no-user-group "${NON_ROOT_USER}" \
    && mkdir -p "${CONDA_DIR}" \
    && chown "${NON_ROOT_USER}:${NON_ROOT_GID}" "${CONDA_DIR}" \
    && chmod g+w /etc/passwd \
    && fix-permissions "${CONDA_DIR}" \
    && fix-permissions "/home/${NON_ROOT_USER}"

USER ${NON_ROOT_UID}

# Setup work directory for backward-compatibility
RUN mkdir -p "/home/${NON_ROOT_USER}/work" \
    && fix-permissions "/home/${NON_ROOT_USER}"

# Download and install Micromamba, and initialize the Conda prefix.
#   <https://github.com/mamba-org/mamba#micromamba>
#   Similar projects using Micromamba:
#     - Micromamba-Docker: <https://github.com/mamba-org/micromamba-docker>
#     - repo2docker: <https://github.com/jupyterhub/repo2docker>
# Install Python, Mamba, cfn-lint, yarmllint and checkov
# Cleanup temporary files and remove Micromamba
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
ARG PYTHON_VERSION=3.11
COPY --chown="${NON_ROOT_UID}:${NON_ROOT_GID}" files/initial-condarc "${CONDA_DIR}/.condarc"
WORKDIR /tmp
RUN set -x && \
    arch=$(uname -m) && \
    if [ "${arch}" = "x86_64" ]; then \
        # Should be simpler, see <https://github.com/mamba-org/mamba/issues/1437>
        arch="64"; \
    fi && \
    # https://mamba.readthedocs.io/en/latest/installation/micromamba-installation.html#linux-and-macos
    wget --progress=dot:giga -O - \
        "https://micro.mamba.pm/api/micromamba/linux-${arch}/latest" | tar -xvj bin/micromamba && \
    PYTHON_SPECIFIER="python=${PYTHON_VERSION}" && \
    if [[ "${PYTHON_VERSION}" == "default" ]]; then PYTHON_SPECIFIER="python"; fi && \
    # Install the packages
    ./bin/micromamba install \
        --root-prefix="${CONDA_DIR}" \
        --prefix="${CONDA_DIR}" \
        --yes \
        'yamllint' \
        'cfn-lint' \
        'checkov' \
        # excluding mamba 2.X due to several breaking changes
        # https://github.com/jupyter/docker-stacks/pull/2147
        'mamba<2.0.0' \
        "${PYTHON_SPECIFIER}" && \
    rm -rf /tmp/bin/ && \
    # Pin major.minor version of python
    # https://conda.io/projects/conda/en/latest/user-guide/tasks/manage-pkgs.html#preventing-packages-from-updating-pinning
    mamba list --full-name 'python' | awk 'END{sub("[^.]*$", "*", $2); print $1 " " $2}' >> "${CONDA_DIR}/conda-meta/pinned" && \
    mamba clean --all -f -y && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NON_ROOT_USER}"

# --------------------------------------------------
# Node.JS
# --------------------------------------------------
ARG NVM_VERSION='0.40.1'
ARG NODE_VERSION='18.20.4'

RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash \
    && source /home/${NON_ROOT_USER}/.nvm/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm alias default ${NODE_VERSION} \
    && nvm use default

ENV NODE_PATH="/home/${NON_ROOT_USER}/.nvm/v${NODE_VERSION}/lib/node_modules"
ENV PATH="/home/${NON_ROOT_USER}/.nvm/versions/node/v${NODE_VERSION}/bin:${PATH}"

RUN npm install -g yarn

# --------------------------------------------------
# AWS CDK
# --------------------------------------------------
ARG AWSCDK_VERSION='2.162.1'
RUN npm install -g \
    'aws-cli' \
    'typescript@latest' \
    "aws-cdk@${AWSCDK_VERSION}"

# --------------------------------------------------
# Open Policy Agent
# --------------------------------------------------
ARG OPA_VERSION='0.69.0'

USER root

RUN set -ex; \
    mkdir -p /usr/local/opa/${OPA_VERSION} \
    && cd /usr/local/opa/${OPA_VERSION} \
    && curl -fsSLO \
        https://github.com/open-policy-agent/opa/releases/download/v${OPA_VERSION}/opa_linux_amd64 \
    && curl -fsSLO \
        https://github.com/open-policy-agent/opa/releases/download/v${OPA_VERSION}/opa_linux_amd64.sha256 \
    && sha256sum --check ./opa_linux_amd64.sha256 \
    && chmod +x ./opa_linux_amd64 \
    && ln -sf /usr/local/opa/${OPA_VERSION}/opa_linux_amd64 /usr/local/bin/opa

USER ${NON_ROOT_UID}

# --------------------------------------------------
# YQ
# ref: https://github.com/mikefarah/yq/#install
# --------------------------------------------------
ARG YQ_VERSION='4.40.5'

USER root

RUN set -ex; \
    mkdir -vp /usr/local/yq/${YQ_VERSION} \
    && cd /usr/local/yq/${YQ_VERSION} \
    && curl -fsSL -O https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz \
    && tar xvzf yq_linux_amd64.tar.gz \
    && ln -sf /usr/local/yq/${YQ_VERSION}/yq_linux_amd64 /usr/local/bin/yq \
    && ./install-man-page.sh \
    && chmod +x /usr/local/bin/yq \
    && rm -vf yq_linux_amd64.tar.gz ./install-man-page.sh checksums

USER ${NON_ROOT_UID}

# --------------------------------------------------
# Terraform
# ref: https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli#install-terraform
# --------------------------------------------------
ARG TERRAFORM_VERSION='1.6.3'

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -yqq \
    && apt-get install -yqq \
        'gnupg' \
        'software-properties-common' \
    && wget -O- https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor \
        | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update -yqq \
    && apt-get install -yqq \
        "terraform=${TERRAFORM_VERSION}-1" \
    && apt-get autoremove -y --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER ${NON_ROOT_UID}

# --------------------------------------------------
# Podman
# ref: https://github.com/mgoltzsche/podman-static
# --------------------------------------------------
ARG PODMAN_VERSION='4.9.2'

USER root

RUN set -ex; \
    mkdir -p /usr/local/podman/${PODMAN_VERSION} \
    && cd /usr/local/podman/${PODMAN_VERSION} \
    && curl -fsSL \
        -o 'podman-linux-amd64.tar.gz' \
        https://github.com/mgoltzsche/podman-static/releases/download/v${PODMAN_VERSION}/podman-linux-amd64.tar.gz \
    && curl -fsSL \
        -o "podman-linux-amd64.tar.gz.asc" \
        https://github.com/mgoltzsche/podman-static/releases/download/v${PODMAN_VERSION}/podman-linux-amd64.tar.gz.asc \
    && gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys '0CCF102C4F95D89E583FF1D4F8B5AF50344BB503' \
    && gpg --batch --verify podman-linux-amd64.tar.gz.asc podman-linux-amd64.tar.gz \
    && tar --strip-component=1 -xzf podman-linux-amd64.tar.gz \
    && cp -vrf /usr/local/podman/${PODMAN_VERSION}/usr /usr/local/podman/${PODMAN_VERSION}/etc / \
    && ln -vsf /usr/local/bin/slirp4netns /usr/bin/slirp4netns \
    && ln -vsf /usr/local/bin/runc /usr/bin/runc \
    && ln -vsf /usr/local/bin/podman /usr/bin/podman \
    && ln -vsf /usr/local/bin/fusemount3 /usr/bin/fusemount3 \
    && ln -vsf /usr/local/bin/fuse-overlayfs /usr/bin/fuse-overlayfs

USER ${NON_ROOT_UID}

# --------------------------------------------------
# crun
# --------------------------------------------------
ARG CRUN_VERSION='1.14.2'

USER root

RUN set -ex; \
	wget -O /usr/local/bin/crun https://github.com/containers/crun/releases/download/$CRUN_VERSION/crun-${CRUN_VERSION}-linux-amd64-disable-systemd \
	&& wget -O /tmp/crun.asc https://github.com/containers/crun/releases/download/$CRUN_VERSION/crun-${CRUN_VERSION}-linux-amd64-disable-systemd.asc \
	&& gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 027F3BD58594CA181BB5EC50E4730F97F60286ED \
	&& gpg --batch --verify /tmp/crun.asc /usr/local/bin/crun \
	&& chmod +x /usr/local/bin/crun

COPY files/crun-containers.conf /usr/containers/containers.conf

USER ${NON_ROOT_UID}

# --------------------------------------------------
# AWS CLI v2 (latest)
# --------------------------------------------------
USER root

RUN curl -o "awscliv2.zip"\
    "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -f awscliv2.zip

USER ${NON_ROOT_UID}

# --------------------------------------------------
# AWS Nuke
# --------------------------------------------------
ARG AWSNUKE_VERSION='2.25.0'

USER root

RUN mkdir -p /usr/local/aws-nuke/${AWSNUKE_VERSION} \
    && cd /usr/local/aws-nuke/${AWSNUKE_VERSION} \
    && curl -fsSL \
        -o 'aws-nuke.targ.gz' \
        https://github.com/rebuy-de/aws-nuke/releases/download/v${AWSNUKE_VERSION}/aws-nuke-v${AWSNUKE_VERSION}-linux-amd64.tar.gz \
    && tar xvzf 'aws-nuke.targ.gz' \
    && ln -sf /usr/local/aws-nuke/${AWSNUKE_VERSION}/aws-nuke-v${AWSNUKE_VERSION}-linux-amd64 /usr/bin/aws-nuke

USER ${NON_ROOT_UID}

# --------------------------------------------------
# Entrypoint
# --------------------------------------------------
USER root

COPY scripts/run-hooks.sh scripts/entrypoint.sh /usr/local/bin/
RUN fix-permissions "/usr/local/bin/"
ENTRYPOINT ["tini", "-g", "--", "/usr/local/bin/entrypoint.sh"]

USER ${NON_ROOT_UID}
WORKDIR "/home/${NON_ROOT_UID}/"