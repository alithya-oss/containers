#!/bin/bash
# Set permissions on a directory
# After any installation, if a directory needs to be (human) user-writable, run this script on it.
# It will make everything in the directory owned by the group ${NON_ROOT_GID} and writable by that group.
# Deployments that want to set a specific user id can preserve permissions
# by adding the `--group-add users` line to `docker run`.

# Uses find to avoid touching files that already have the right permissions,
# which would cause a massive image explosion

# Right permissions are:
# group=${NON_ROOT_GID}
# AND permissions include group rwX (directory-execute)
# AND directories have setuid,setgid bits set

set -e

for d in "$@"; do
    find "${d}" \
        ! \( \
            -group "${NON_ROOT_GID}" \
            -a -perm -g+rwX \
        \) \
        -exec chgrp "${NON_ROOT_GID}" -- {} \+ \
        -exec chmod g+rwX -- {} \+
    # setuid, setgid *on directories only*
    find "${d}" \
        \( \
            -type d \
            -a ! -perm -6000 \
        \) \
        -exec chmod +6000 -- {} \+
done