#!/bin/bash
# Load the dftracer-demo environment: config.yaml -> modules -> python venv.
#
#   source ./activate_env.sh
#
# Safe to source repeatedly. Exports DEMO_ROOT, DEMO_CONFIG and every
# config.yaml key as DEMO_<SECTION>_<KEY>.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "activate_env.sh must be sourced: source ${BASH_SOURCE[0]}" >&2
    exit 1
fi

export DEMO_ROOT="${DEMO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export DEMO_CONFIG="${DEMO_CONFIG:-${DEMO_ROOT}/config.yaml}"

_demo_config="$(python3 "${DEMO_ROOT}/scripts/load_config.py" "${DEMO_CONFIG}")" || {
    echo "activate_env.sh: failed to read ${DEMO_CONFIG}" >&2
    return 1
}
eval "${_demo_config}"
unset _demo_config

# Lmod is not always initialised in non-interactive shells (e.g. batch jobs).
if ! type module >/dev/null 2>&1; then
    for _init in /usr/share/lmod/lmod/init/bash /etc/profile.d/modules.sh; do
        [[ -f "${_init}" ]] && source "${_init}" && break
    done
    unset _init
fi

if [[ "${DEMO_MODULES_PURGE:-0}" == "1" ]]; then
    module purge
fi
if [[ -n "${DEMO_MODULES_LOAD:-}" ]]; then
    # shellcheck disable=SC2086
    module load ${DEMO_MODULES_LOAD} || {
        echo "activate_env.sh: module load ${DEMO_MODULES_LOAD} failed" >&2
        return 1
    }
fi

if [[ -f "${DEMO_PATHS_INSTALL}/bin/activate" ]]; then
    source "${DEMO_PATHS_INSTALL}/bin/activate"
else
    echo "activate_env.sh: no virtual environment at ${DEMO_PATHS_INSTALL} (run ./setup.sh)" >&2
fi
