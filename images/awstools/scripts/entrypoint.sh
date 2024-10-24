#!/usr/bin/env bash
set -eEuo pipefail

ScriptName=$(basename $0)
# Job=`basename $0 .sh`"_whatever_I_want" # Add _whatever_I_want after basename
Job=$(basename $0 .sh)
JobClass=$(basename $0 .sh)

colblk='\033[0;30m' # Black - Regular
colred='\033[0;31m' # Red
colgrn='\033[0;32m' # Green
colora='\033[0;33m' # Brown/Orange
colblu='\033[0;34m' # Blue
colpur='\033[0;35m' # Purple
colcya='\033[0;36m' # Cyan
collgr='\033[0;36m' # Light Gray
colwht='\033[0;97m' # White
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
function esilent () { verb_lvl=$silent_lvl elog "$@" ;}
function enotify () { verb_lvl=$ntf_lvl elog "$@" ;}
function eok ()    { verb_lvl=$ntf_lvl elog "${colgrn}SUCCESS${colrst} - $@" ;}
function ewarn ()  { verb_lvl=$wrn_lvl elog "${colora}WARNING${colrst} - $@" ;}
function einfo ()  { verb_lvl=$inf_lvl elog "${collgr}INFO${colrst} - $@" ;}
function edebug () { verb_lvl=$dbg_lvl elog "${colcya}DEBUG${colrst} - $@" ;}
function eerror () { verb_lvl=$err_lvl elog "${colred}ERROR${colrst} - $@" ;}
function ecrit ()  { verb_lvl=$crt_lvl elog "${colpur}FATAL${colrst} - $@" ;}
function edumpvar () { for var in $@ ; do edebug "$var=${!var}" ; done }
function elog() {
        if [ $verbosity -ge $verb_lvl ]; then
                datestring=$(date +"%Y-%m-%d %H:%M:%S")
                echo -e "$datestring - $@"
        fi
}

einfo ""


source /etc/os-release
einfo "OS version:                $PRETTY_NAME"
einfo "Python version:            $(python --version)"
einfo "YAML linter version:       $(yamllint --version)"
einfo "Node.JS version:           $(node --version)"
einfo "Yarn version:              $(yarn --version)"
einfo "AWS CLI version:           $(aws --version)"
einfo "AWS CDK version:           $(cdk --version)"
einfo "YQ version:                $(yq --version)"
einfo "JQ version:                $(jq --version)"
einfo "Checkov version:           $(checkov --version)"
einfo "Open Policy Agent version: $(opa version)"

exec "$@"