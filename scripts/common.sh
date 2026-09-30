#!/bin/bash
# Shared helpers for the demo step scripts in demo/<benchmark>/.
#
# A step script sources this file, then calls
#
#   demo_slurm_step <nodes> <tasks> <time> "$@"
#
# Outside a Slurm allocation that re-submits the step with sbatch, streams the
# job log to the terminal and exits with the job's status. Inside an allocation
# (the batch job itself, or an interactive `salloc`) it returns and the step
# body runs in place.

if [[ -z "${DEMO_ROOT:-}" ]]; then
    DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export DEMO_ROOT

# The caller is the step script; inside a batch job $0 is Slurm's spool copy, so
# the original path travels in DEMO_STEP_SCRIPT.
DEMO_STEP_SCRIPT="${DEMO_STEP_SCRIPT:-$(realpath "$0")}"
DEMO_BENCH="$(basename "$(dirname "${DEMO_STEP_SCRIPT}")")"
DEMO_STEP="$(basename "${DEMO_STEP_SCRIPT}" .sh)"
export DEMO_STEP_SCRIPT

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [${DEMO_BENCH}/${DEMO_STEP}] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# Optional arguments. Any config key may be empty or missing; the matching
# flag is then left out of the command entirely, never passed blank.
#   demo_opt        ARRAY --flag "$value"   appends: --flag value
#   demo_optkv      ARRAY key    "$value"   appends: key=value
#   demo_optwords   ARRAY "$words"          appends each word (extra flags)
#   demo_export_opt NAME "$value"           exports NAME=value
demo_opt() {
    local -n __demo_arr="$1"
    [[ -n "${3:-}" ]] && __demo_arr+=("$2" "$3")
    return 0
}
demo_optkv() {
    local -n __demo_arr="$1"
    [[ -n "${3:-}" ]] && __demo_arr+=("$2=$3")
    return 0
}
demo_optwords() {
    local -n __demo_arr="$1"
    local -a __demo_words=()
    read -r -a __demo_words <<< "${2:-}"
    __demo_arr+=("${__demo_words[@]}")
    return 0
}
demo_export_opt() {
    [[ -n "${2:-}" ]] && export "$1=$2"
    return 0
}
# Shell-quoted command line, for logging exactly what runs.
demo_cmdline() {
    printf '%q ' "$@"
}

# shellcheck source=../activate_env.sh
source "${DEMO_ROOT}/activate_env.sh" || die "could not activate the environment"
set -euo pipefail

# Per-benchmark directories, all rooted at the paths in config.yaml.
DATA_DIR="${DEMO_PATHS_DATA}/${DEMO_BENCH}"
TRACE_DIR="${DEMO_PATHS_TRACES}/${DEMO_BENCH}"
RESULT_DIR="${DEMO_PATHS_RESULTS}/${DEMO_BENCH}"
RUN_DIR="${DEMO_PATHS_RUNS}/${DEMO_BENCH}"
mkdir -p "${RUN_DIR}"

# sbatch arguments shared by every submission; the job appends to <log>.
_demo_sbatch_args() {
    local nodes="$1" tasks="$2" time="$3" log_file="$4"
    DEMO_SBATCH_ARGS=(
        --parsable
        --job-name "dftd-${DEMO_BENCH}-${DEMO_STEP}"
        --output "${log_file}" --open-mode append
        --export "ALL,DEMO_ROOT=${DEMO_ROOT},DEMO_STEP_SCRIPT=${DEMO_STEP_SCRIPT}"
    )
    demo_opt DEMO_SBATCH_ARGS --partition "${DEMO_SLURM_PARTITION:-}"
    demo_opt DEMO_SBATCH_ARGS --account "${DEMO_SLURM_ACCOUNT:-}"
    demo_opt DEMO_SBATCH_ARGS --nodes "${nodes}"
    demo_opt DEMO_SBATCH_ARGS --ntasks "${tasks}"
    demo_opt DEMO_SBATCH_ARGS --time "${time}"
    demo_optwords DEMO_SBATCH_ARGS "${DEMO_SLURM_EXTRA:-}"
    return 0
}

# New job log path. It is created here, on the submit host, because NFS
# caches "file not found" for files that another node creates later.
_demo_new_log() {
    local file
    file="${RUN_DIR}/${DEMO_STEP}-$(date '+%Y%m%d-%H%M%S').out"
    : > "${file}"
    echo "${file}"
}

demo_slurm_step() {
    local nodes="$1" tasks="$2" time="$3"
    shift 3
    if [[ -n "${SLURM_JOB_ID:-}" ]]; then
        log "Running in Slurm job ${SLURM_JOB_ID} on $(hostname) (${SLURM_NTASKS:-1} tasks)"
        return 0
    fi

    local out idfile
    out="$(_demo_new_log)"
    idfile="$(mktemp)"
    _demo_sbatch_args "${nodes}" "${tasks}" "${time}" "${out}"
    log "sbatch --wait $(demo_cmdline "${DEMO_SBATCH_ARGS[@]}" "${DEMO_STEP_SCRIPT}" "$@")"
    sbatch --wait "${DEMO_SBATCH_ARGS[@]}" "${DEMO_STEP_SCRIPT}" "$@" > "${idfile}" &
    local sbatch_pid=$!

    # Wait for the job id, then follow the job log until sbatch returns.
    local jobid=""
    while [[ -z "${jobid}" ]] && kill -0 "${sbatch_pid}" 2>/dev/null; do
        sleep 1
        jobid="$(cut -d';' -f1 "${idfile}")"
    done
    jobid="${jobid:-$(cut -d';' -f1 "${idfile}")}"
    local rc=0
    if [[ -n "${jobid}" ]]; then
        log "Submitted job ${jobid} (partition ${DEMO_SLURM_PARTITION:-default}); log: ${out}"
        demo_follow_log "${out}" "${sbatch_pid}"
    fi
    wait "${sbatch_pid}" || rc=$?
    rm -f "${idfile}"
    if [[ -z "${jobid}" ]]; then
        log "sbatch submission failed (exit ${rc})"
        rc=$(( rc ? rc : 1 ))
    elif [[ ${rc} -ne 0 ]]; then
        log "Job ${jobid} failed (exit ${rc}); see ${out}"
    else
        log "Job ${jobid} completed"
    fi
    exit "${rc}"
}

# Print a job log as it grows until <pid> exits. Polls by byte offset, opening
# the file each time (NFS revalidates on open; `tail -F`/stat can lag).
demo_follow_log() {
    local file="$1" pid="$2" offset=0 size idle=0
    while :; do
        local running=0
        kill -0 "${pid}" 2>/dev/null && running=1
        size="$(wc -c < "${file}")"
        if (( size > offset )); then
            tail -c +"$(( offset + 1 ))" "${file}" | head -c "$(( size - offset ))"
            offset="${size}"
            idle=0
        elif (( ! running )); then
            # Give NFS a few seconds to deliver the end of the log.
            (( ++idle > 3 )) && break
        fi
        sleep 2
    done
}

# Submit the step without waiting (long-running services). Sets DEMO_JOB_ID
# and DEMO_JOB_LOG.
demo_slurm_submit() {
    local nodes="$1" tasks="$2" time="$3"
    shift 3
    DEMO_JOB_LOG="$(_demo_new_log)"
    _demo_sbatch_args "${nodes}" "${tasks}" "${time}" "${DEMO_JOB_LOG}"
    log "sbatch $(demo_cmdline "${DEMO_SBATCH_ARGS[@]}" "${DEMO_STEP_SCRIPT}" "$@")"
    DEMO_JOB_ID="$(sbatch "${DEMO_SBATCH_ARGS[@]}" "${DEMO_STEP_SCRIPT}" "$@" | cut -d';' -f1)"
    [[ -n "${DEMO_JOB_ID}" ]] || die "sbatch submission failed"
}

# Serve a trace directory with dftracer_server (from dftracer-utils) and write
# the viewer URL to <url_file>. Runs in the foreground until the job ends.
demo_serve_traces() {
    local trace_dir="$1" url_file="$2"
    local port token host
    port="$(python - "${DEMO_VIEWER_PORT:-8080}" <<'EOF'
import socket, sys
port = int(sys.argv[1])
for candidate in [port, 0]:
    with socket.socket() as s:
        try:
            s.bind(("", candidate))
        except OSError:
            continue
        print(s.getsockname()[1])
        break
EOF
)"
    token="$(python -c 'import secrets; print(secrets.token_hex(16))')"
    host="$(hostname -s)"
    local url="http://${host}:${port}/?token=${token}"
    chmod 600 "${url_file}"
    echo "${url}" > "${url_file}"
    log "Serving ${trace_dir}"
    log "Viewer URL: ${url}"
    log "From your workstation: ssh -L ${port}:${host}:${port} ${SLURM_SUBMIT_HOST:-<login-node>}, then open http://localhost:${port}/?token=${token}"
    # Bind all interfaces so the login node (and a tunnel) can reach the
    # compute node; the token keeps other users out.
    local threads
    threads="$(demo_cpus)"
    local cmd=(dftracer_server -b 0.0.0.0 -p "${port}" -d "${trace_dir}"
        --token "${token}" --index-dir "${trace_dir}/.dftindex"
        --executor-threads "${threads}" --io-threads "${threads}")
    log "$(demo_cmdline "${cmd[@]}" | sed "s/${token}/<token>/")"
    "${cmd[@]}"
}

# Wait for a viewer job to publish its URL, then (viewer.proxy) relay it
# through this login node so it opens directly at http://<login>:<port>/.
# Opens the URL in a browser on the cluster when $DISPLAY is set. The URL file
# must already exist (created on this host, see _demo_new_log).
demo_open_viewer() {
    local jobid="$1" url_file="$2" job_log="$3" url=""
    log "Waiting for viewer job ${jobid} to start (log: ${job_log})"
    while [[ -z "${url}" ]]; do
        [[ -n "$(squeue -h -j "${jobid}" -o %T 2>/dev/null)" ]] \
            || die "viewer job ${jobid} ended; see ${job_log}"
        sleep 2
        url="$(cat "${url_file}")"
    done
    log "Viewer is up on the compute node: ${url}"

    if [[ "${DEMO_VIEWER_PROXY:-0}" == "1" ]]; then
        # http://<node>:<port>/?token=<token>
        local hostport="${url#http://}"
        hostport="${hostport%%/*}"
        local proxy_log="${RUN_DIR}/viewer_proxy-${jobid}.log" port="" tries=0
        setsid nohup python3 "${DEMO_ROOT}/scripts/viewer_proxy.py" 0.0.0.0 "${DEMO_VIEWER_PORT:-8080}" \
            "${hostport%%:*}" "${hostport##*:}" "${jobid}" > "${proxy_log}" 2>&1 < /dev/null &
        while [[ -z "${port}" ]] && (( tries++ < 20 )); do
            sleep 0.5
            port="$(head -n1 "${proxy_log}" | grep -E '^[0-9]+$' || true)"
        done
        [[ -n "${port}" ]] || die "login-node proxy failed; see ${proxy_log}"
        url="http://$(hostname -s):${port}/${url#http://*/}"
        echo "${url}" > "${url_file}"
        log "Proxied through $(hostname -s):${port} (stops with the job)"
    fi

    local host_port="${url#http://}"
    host_port="${host_port%%/*}"
    log "Open the viewer: ${url}"
    log "If ${host_port%%:*} is not reachable from your machine: ssh -L ${host_port##*:}:${host_port} $(hostname -s), then open http://localhost:${host_port##*:}/${url#http://*/}"
    log "Stop it with: scancel ${jobid}"
    if [[ -n "${DEMO_VIEWER_TUNNEL:-}" ]]; then
        # viewer.tunnel: no VS Code or X display; tunnel from the workstation.
        # scripts/sync_mogon.sh run looks for the next line and opens the tunnel.
        log "On your workstation: scripts/sync_mogon.sh tunnel ${DEMO_BENCH}"
        log "  or: ssh -N -L ${host_port##*:}:${host_port} ${DEMO_VIEWER_TUNNEL}, then open http://localhost:${host_port##*:}/${url#http://*/}"
    elif [[ "${DEMO_VIEWER_PROXY:-0}" == "1" && -n "${BROWSER:-}" && -n "${VSCODE_IPC_HOOK_CLI:-}" ]]; then
        # VS Code Remote-SSH: its $BROWSER helper forwards a localhost port to
        # your machine and opens it there. The relay listens on localhost too.
        local local_url="http://localhost:${host_port##*:}/${url#http://*/}"
        log "Opening ${local_url} through VS Code (port ${host_port##*:} is forwarded; see the Ports panel)"
        "${BROWSER}" "${local_url}" || true
    elif [[ -n "${DISPLAY:-}" && -n "${DEMO_VIEWER_BROWSER:-}" ]] \
            && command -v "${DEMO_VIEWER_BROWSER}" >/dev/null 2>&1; then
        log "Opening ${DEMO_VIEWER_BROWSER} on $(hostname -s)"
        nohup "${DEMO_VIEWER_BROWSER}" "${url}" >/dev/null 2>&1 &
    fi
}

# Launch an MPI program across the ranks of the current allocation, giving
# each rank an equal share of the node's allocated cores (DLIO's DataLoader
# workers run inside that share). slurm.launcher picks srun (default) or the
# MPI library's mpirun, for sites whose Slurm lacks the PMI plugin the MPI
# needs (Mogon: OpenMPI 5 wants PMIx, srun only offers pmi2). A leading
# --export=ALL,K=V,... applies K=V to the ranks with either launcher.
demo_mpirun() {
    local ranks_per_node=$(( ${SLURM_NTASKS:-1} / ${SLURM_NNODES:-1} ))
    local cpus=$(( $(demo_cpus) / (ranks_per_node > 0 ? ranks_per_node : 1) ))
    (( cpus > 0 )) || cpus=1
    local args
    if [[ "${DEMO_SLURM_LAUNCHER:-srun}" == "mpirun" ]]; then
        args=(mpirun -np "${SLURM_NTASKS:-1}" --map-by "slot:PE=${cpus}" --bind-to core)
        if [[ "${1:-}" == --export=* ]]; then
            local kv
            IFS=',' read -ra kv <<< "${1#--export=}"
            for kv in "${kv[@]}"; do
                [[ "${kv}" == ALL ]] || args+=(-x "${kv}")
            done
            shift
        fi
    else
        args=(srun --ntasks="${SLURM_NTASKS:-1}" --cpus-per-task="${cpus}")
        demo_optkv args --mpi "${DEMO_SLURM_MPI:-}"
    fi
    log "$(demo_cmdline "${args[@]}" "$@")"
    "${args[@]}" "$@"
}

# CPUs Slurm allocated on this node (nproc counts hyperthreads, which srun
# does not hand out).
demo_cpus() {
    echo "${SLURM_CPUS_ON_NODE:-$(nproc)}"
}

# Remove and recreate directories (refuses empty or root paths).
demo_fresh_dir() {
    local dir
    for dir in "$@"; do
        [[ -n "${dir}" && "${dir}" != "/" ]] || die "refusing to clean '${dir}'"
        rm -rf "${dir}"
        mkdir -p "${dir}"
    done
}

# Absolute path of DFTracer's LD_PRELOAD library inside the venv.
demo_dftracer_preload() {
    local lib
    lib="$(find "${DEMO_PATHS_INSTALL}" -name 'libdftracer_preload.so' -print -quit 2>/dev/null)"
    [[ -n "${lib}" ]] || die "libdftracer_preload.so not found under ${DEMO_PATHS_INSTALL}"
    echo "${lib}"
}

# Print the first and last events of the compacted traces in a directory.
demo_show_traces() {
    local dir="$1"
    log "Trace files in ${dir}:"
    ls -lh "${dir}"/*.pfw.gz
    log "First 10 and last 5 events:"
    # Each .pfw.gz is gzip-compressed JSON lines, one event per line.
    { gzip -dc "${dir}"/*.pfw.gz || true; } | { head -n 10; echo "..."; tail -n 5; }
}
