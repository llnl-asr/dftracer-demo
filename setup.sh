#!/bin/bash
# Build a fresh dftracer-demo environment from config.yaml.
#
#   ./setup.sh
#
#   1. clean     remove the previous venv (paths.install) and builds (paths.build)
#   2. venv      load modules and create a new python virtual environment
#   3. activate  source activate_env.sh (modules + venv)
#   4. install   Node.js via nodeenv (for the dftracer_server web UI), the pip
#                packages in software.python, mpi4py from source against the
#                loaded MPI, and IOR from software.ior
#
# Run on a login node: the installation clones from GitHub.
# A full log is written to paths.runs/setup-<timestamp>.log.

set -euo pipefail

# Everything runs inside main() so bash parses the whole script before
# executing it; editing setup.sh while it runs cannot corrupt the run.
main() {
    DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export DEMO_ROOT

    log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [setup] $*"; }

    # Config first, so the log can go to paths.runs.
    eval "$(python3 "${DEMO_ROOT}/scripts/load_config.py" "${DEMO_CONFIG:-${DEMO_ROOT}/config.yaml}")"
    mkdir -p "${DEMO_PATHS_RUNS}"
    SETUP_LOG="${DEMO_PATHS_RUNS}/setup-$(date '+%Y%m%d-%H%M%S').log"
    exec > >(tee "${SETUP_LOG}") 2>&1
    log "Log file: ${SETUP_LOG}"

    # --- 1. clean ----------------------------------------------------------------
    for dir in "${DEMO_PATHS_INSTALL}" "${DEMO_PATHS_BUILD}"; do
        if [[ -z "${dir}" || "${dir}" == "/" || "${dir}" == "${DEMO_ROOT}" ]]; then
            log "Refusing to remove suspicious path '${dir}'"; exit 1
        fi
        log "Removing ${dir}"
        rm -rf "${dir}"
    done

    # --- 2. venv -----------------------------------------------------------------
    set +u  # module/venv scripts reference unset variables
    source "${DEMO_ROOT}/activate_env.sh" 2>/dev/null   # modules only; no venv yet
    log "Modules: ${DEMO_MODULES_LOAD:-none}"
    log "Creating virtual environment with $(command -v python) ($(python --version 2>&1))"
    python -m venv "${DEMO_PATHS_INSTALL}"

    # --- 3. activate -------------------------------------------------------------
    source "${DEMO_ROOT}/activate_env.sh"
    set -u
    log "Active python: $(command -v python)"

    # --- 4. install --------------------------------------------------------------
    python -m pip install --upgrade pip setuptools wheel

    # Node.js (into the venv via nodeenv) so dftracer-utils can build the
    # dftracer_server web UI; without it the server only serves a placeholder page.
    log "Installing Node.js ${DEMO_SOFTWARE_NODE:-latest} into the venv (nodeenv)"
    python -m pip install nodeenv
    local nodeenv_args=(--python-virtualenv --prebuilt)
    [[ -n "${DEMO_SOFTWARE_NODE:-}" ]] && nodeenv_args+=(--node="${DEMO_SOFTWARE_NODE}")
    nodeenv "${nodeenv_args[@]}"
    hash -r
    log "node $(node --version), npm $(npm --version)"
    export SKBUILD_CMAKE_DEFINE="DFTRACER_UTILS_BUILD_WEB_UI=ON"

    for pkg in ${DEMO_SOFTWARE_PYTHON:-}; do
        log "pip install ${pkg}"
        python -m pip install "${pkg}"
    done

    # A later package can pull a PyPI release over an earlier git install (e.g.
    # dftracer requires pydftracer>=2.0.4, which a 2.0.4.devN head does not meet).
    # Reinstall, without dependencies, every git package that was replaced.
    for pkg in $(python "${DEMO_ROOT}/scripts/replaced_git_packages.py" ${DEMO_SOFTWARE_PYTHON:-}); do
        log "Re-pinning ${pkg} (replaced by a PyPI release)"
        python -m pip install --no-deps --force-reinstall "${pkg}"
    done

    # mpi4py from source with the MPI compiler wrappers. LDSHARED is needed too:
    # LLNL's python modules are Anaconda builds whose default link line
    # (-L<anaconda>/lib) would resolve -lmpi to Anaconda's bundled MPICH instead of
    # the loaded MPI module.
    log "Rebuilding mpi4py from source against $(command -v mpicc)"
    CC="$(command -v mpicc)" CXX="$(command -v mpic++)" \
    LDSHARED="$(command -v mpicc) -shared -pthread" \
        python -m pip install --force-reinstall --no-cache-dir --no-deps --no-binary mpi4py mpi4py
    python -c "from mpi4py import MPI; print('mpi4py uses:', MPI.Get_library_version().splitlines()[0])"

    if [[ -n "${DEMO_SOFTWARE_IOR_REPO:-}" ]]; then
        log "Building IOR ${DEMO_SOFTWARE_IOR_REF:-(default branch)}"
        mkdir -p "${DEMO_PATHS_BUILD}"
        local clone_args=(--depth 1)
        [[ -n "${DEMO_SOFTWARE_IOR_REF:-}" ]] && clone_args+=(--branch "${DEMO_SOFTWARE_IOR_REF}")
        git clone "${clone_args[@]}" "${DEMO_SOFTWARE_IOR_REPO}" "${DEMO_PATHS_BUILD}/ior"
        (
            cd "${DEMO_PATHS_BUILD}/ior"
            ./bootstrap
            ./configure --prefix="${DEMO_PATHS_INSTALL}" CC=mpicc
            make -j "$(nproc)"
            make install
        )
    else
        log "software.ior.repo not set; skipping IOR"
    fi

    log "Installed versions:"
    python -m pip list 2>/dev/null | grep -iE '^(dftracer|pydftracer|dlio|mpi4py)' || true
    for bin in ior dlio_benchmark dftracer_split dftracer_server; do
        printf '  %-16s %s\n' "${bin}" "$(command -v "${bin}" || echo MISSING)"
    done
    log "Setup completed. Activate with: source ${DEMO_ROOT}/activate_env.sh"
}

main "$@"
exit
