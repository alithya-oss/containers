#!/usr/bin/env bash
# =============================================================================
# multica-kiro-daemon entrypoint
#
# Resolves ALIT-9's open point #1: `multica` has no documented environment
# variable for non-interactive authentication. The real mechanism is the CLI
# command `multica login --token <mul_...>` (see CLI_AND_DAEMON.md). This
# script bridges the ECS-injected secret (env var, from Secrets Manager via
# the task definition's native `secrets` block — never baked into the image)
# into that CLI invocation, once, on container start.
# =============================================================================
set -euo pipefail

if [ -z "${MULTICA_TOKEN:-}" ]; then
    echo "FATAL: MULTICA_TOKEN is not set (expected to be injected via ECS" \
         "task definition 'secrets', from Secrets Manager)." >&2
    exit 1
fi

# `multica auth status` exits 0 only when a valid session already exists for
# this profile's state directory (persisted on the EFS-backed home volume) —
# skip re-authenticating on every task restart/redeploy so a token rotation
# is picked up without clobbering a still-valid session.
if ! multica auth status >/dev/null 2>&1; then
    echo "No valid Multica session found — authenticating with the injected token."
    # --token=<value> is used (not interactive --token with a bare arg) so the
    # token never appears in `ps` output on this single-tenant task.
    multica login --token="${MULTICA_TOKEN}"
else
    echo "Existing Multica session is valid — skipping login."
fi

# `multica login` already discovers and watches every workspace the token's
# user belongs to, and `daemon start --foreground` is what keeps the
# container's PID 1 alive for ECS (no backgrounding: a backgrounded daemon
# would let the entrypoint exit and the task would be reported unexpectedly
# stopped despite the daemon still running).
exec multica daemon start --foreground
