#!/usr/bin/env bash
set -eEuo pipefail

colred='\033[0;31m' # Red
colgrn='\033[0;32m' # Green
colora='\033[0;33m' # Brown/Orange
colcya='\033[0;36m' # Cyan
collgr='\033[0;36m' # Light Gray
colpur='\033[0;35m' # Purple
colrst='\033[0m'    # Text Reset

verbosity=5

### verbosity levels
silent_lvl=0
crt_lvl=1
err_lvl=2
wrn_lvl=3
ntf_lvl=4
inf_lvl=5
dbg_lvl=6

## esilent prints output even in silent mode
esilent() { elog "${silent_lvl}" "$@"; }
enotify() { elog "${ntf_lvl}" "$@"; }
eok()     { elog "${ntf_lvl}" "${colgrn}SUCCESS${colrst} - $*"; }
ewarn()   { elog "${wrn_lvl}" "${colora}WARNING${colrst} - $*"; }
einfo()   { elog "${inf_lvl}" "${collgr}INFO${colrst} - $*"; }
edebug()  { elog "${dbg_lvl}" "${colcya}DEBUG${colrst} - $*"; }
eerror()  { elog "${err_lvl}" "${colred}ERROR${colrst} - $*"; }
ecrit()   { elog "${crt_lvl}" "${colpur}FATAL${colrst} - $*"; }

elog() {
    local verb_lvl="$1"
    shift
    if [[ "${verbosity}" -ge "${verb_lvl}" ]]; then
        local datestring
        datestring="$(date +"%Y-%m-%d %H:%M:%S")"
        echo -e "${datestring} - $*"
    fi
}

# Report the version of a tool without aborting the entrypoint when the
# tool is missing (set -e would otherwise stop the container from starting).
report() {
    local label="$1"
    shift
    local version
    if version="$("$@" 2>&1 | head -n 1)"; then
        einfo "${label} ${version}"
    else
        ewarn "${label} not available"
    fi
}

# shellcheck disable=SC1091
source /etc/os-release
einfo "OS version:            ${PRETTY_NAME}"
report "Python version:       " python --version
report "Node.JS version:      " node --version
report "npm version:          " npm --version
report "Yarn version:         " yarn --version
report "pnpm version:         " pnpm --version
report "Playwright version:   " playwright --version
report "LikeC4 version:       " likec4 --version
report "CALM CLI version:     " calm --version
report "pdftotext version:    " pdftotext -v
report "jq version:           " jq --version
report "LuaLaTeX version:     " lualatex --version
report "XeLaTeX version:      " xelatex --version
report "Bun version:          " bun --version

exec "$@"
