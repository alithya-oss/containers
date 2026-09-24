# Added by the kirocrew custom image (see images/kirocrew/Dockerfile)
#
# Exports the tool env for the extra tooling this image layers on top of the
# base (Node via nvm under /opt, Bun, TinyTeX, Playwright browsers) and sources
# nvm.sh so the `nvm` shell function is defined.
#
# `nvm` is a shell function, not a binary — it only exists in shells that source
# this file. node/npm/npx/bun/latex are also symlinked into /usr/local/bin, so
# those resolve even in a non-interactive stripped exec shell that reads neither
# profile.d nor bash.bashrc.
#
# Everything here lives under /opt (outside the mounted /home/kirocrew volume)
# so a data-home mount cannot shadow it.

export NVM_DIR="/opt/nvm"
export BUN_INSTALL="/opt/bun"
export PLAYWRIGHT_BROWSERS_PATH="/opt/ms-playwright"

# Glob the installed Node version so a Renovate bump of NODE_VERSION needs no
# edit here; falls back cleanly if the dir is absent.
for _kc_node_bin in /opt/nvm/versions/node/*/bin; do
    [ -d "${_kc_node_bin}" ] && PATH="${_kc_node_bin}:${PATH}"
done
unset _kc_node_bin
export PATH="/opt/bun/bin:/opt/.TinyTeX/bin/x86_64-linux:${PATH}"

[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"
