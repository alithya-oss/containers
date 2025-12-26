ARG BASE_IMAGE_TAG="0.38.0-alpine"

FROM ghcr.io/runatlantis/atlantis:v${BASE_IMAGE_TAG}

ENV NON_ROOT_USER="atlantis"
ARG NON_ROOT_UID="100"
ARG NON_ROOT_GID="1000"

# --------------------------------------------------
# AWS CLI v2 (latest)
# --------------------------------------------------
USER root
RUN apk add --no-cache \
    'aws-cli'

USER ${NON_ROOT_UID}
