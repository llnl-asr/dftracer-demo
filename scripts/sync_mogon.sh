#!/bin/bash
# Two-way sync of this repository with MOGON NHR, and running commands there.
#
#   scripts/sync_mogon.sh [sync]        push, then pull (newer file wins)
#   scripts/sync_mogon.sh push|pull     one direction only
#   scripts/sync_mogon.sh run <cmd...>  push, run <cmd> in the remote repo with
#                                       config.mogon-nhr.yaml, then pull; if it
#                                       started a viewer, tunnel it here
#   scripts/sync_mogon.sh shell         push, then open a shell in the remote repo
#   scripts/sync_mogon.sh fetch         copy remote results/ and runs/ (on Lustre)
#                                       into ./mogon-out/
#   scripts/sync_mogon.sh view <bench>  push, start the trace viewer (ior|dlio)
#                                       on a compute node, then tunnel it here
#   scripts/sync_mogon.sh tunnel <bench>
#                                       tunnel an already running viewer here
#
# The viewer path is compute node -> login node (viewer_proxy.py, viewer.proxy)
# -> this machine (ssh -L through viewer.tunnel, default $MOGON_HOST, to the
# URL in runs/<bench>/viewer.url), opened in the
# local browser at http://localhost:<port>/. Ctrl-C closes the tunnel only; the
# viewer job keeps running until viewer.time or `scancel`.
#
# Extra rsync flags go after `push`/`pull`/`sync`, e.g. `sync -n` for a dry run.
#
# Both directions use `rsync --update`: a file is only replaced by a newer copy,
# so edits on either side survive. Deletions are NOT propagated; remove the file
# on both sides (or `push --delete` to mirror local onto the cluster).
# .git, the venv and build trees are machine-specific and never synced; commit
# and push to git from the laptop.
#
# Override the target with MOGON_HOST / MOGON_DIR / MOGON_PFS.

set -euo pipefail

MOGON_HOST="${MOGON_HOST:-mogon-nhr}"
MOGON_DIR="${MOGON_DIR:-/home/haridevar01/projects/dftracer-demo}"
MOGON_PFS="${MOGON_PFS:-/lustre/project/ki-mawahpc/haridevar01/dftracer-demo}"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

EXCLUDES=(
    --exclude=.git/
    --exclude=.DS_Store
    --exclude=__pycache__/
    --exclude='*.pyc'
    --exclude=.ipynb_checkpoints/
    --exclude=/install/
    --exclude=/build/
    --exclude=/software/
    --exclude=/data/
    --exclude=/mogon-out/
)
RSYNC=(rsync -rlptzu --itemize-changes "${EXCLUDES[@]}")

log() { echo "[sync_mogon] $*"; }

push() {
    log "push ${LOCAL_DIR}/ -> ${MOGON_HOST}:${MOGON_DIR}/"
    ssh "${MOGON_HOST}" "mkdir -p '${MOGON_DIR}'"
    "${RSYNC[@]}" "$@" "${LOCAL_DIR}/" "${MOGON_HOST}:${MOGON_DIR}/"
}

pull() {
    log "pull ${MOGON_HOST}:${MOGON_DIR}/ -> ${LOCAL_DIR}/"
    "${RSYNC[@]}" "$@" "${MOGON_HOST}:${MOGON_DIR}/" "${LOCAL_DIR}/"
}

# Make sure a shared ControlMaster connection to <host> is up, so every ssh and
# rsync below reuses it (one login prompt, e.g. for the OTP, per session).
ensure_master() {
    ssh -O check "$1" 2>/dev/null && return 0
    log "opening a persistent connection to $1 (stop it with: ssh -O exit $1)"
    ssh -x -f -N -o ControlMaster=yes -o ControlPersist=yes "$1"
}

# Run "$@" on the cluster in the repo, with the Mogon config selected.
remote() {
    local tty=$1; shift
    local cmd
    printf -v cmd '%q ' "$@"
    ssh ${tty} "${MOGON_HOST}" "cd '${MOGON_DIR}' && export DEMO_CONFIG='${MOGON_DIR}/config.mogon-nhr.yaml' && ${cmd}"
}

# Forward the viewer of <bench> (URL from runs/<bench>/viewer.url on the
# cluster) to a local port and open it in the local browser.
tunnel() {
    local bench="$1" url via hostport lport tries=0
    # "<viewer.tunnel> <url>" from the cluster config and the step's URL file.
    read -r via url < <(remote -x bash -lc "eval \"\$(python3 scripts/load_config.py \"\$DEMO_CONFIG\")\" && echo \"\${DEMO_VIEWER_TUNNEL:--}\" \"\$(cat \"\$DEMO_PATHS_RUNS/${bench}/viewer.url\")\"" 2>/dev/null) || true
    [[ "${url:-}" == http://* ]] || { log "no viewer URL for ${bench}; start one with: $0 view ${bench}"; exit 1; }
    [[ "${via}" == - ]] && via="${MOGON_HOST}"
    hostport="${url#http://}"
    hostport="${hostport%%/*}"
    lport="$(python3 - "${MOGON_VIEW_PORT:-8080}" <<'EOF'
import socket, sys
for port in [int(sys.argv[1]), 0]:
    with socket.socket() as s:
        try:
            s.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(s.getsockname()[1])
        break
EOF
)"
    # Login needs keyboard-interactive auth, so the forward rides on the
    # ControlMaster connection; Ctrl-C cancels just this forward.
    ensure_master "${via}"
    ssh -O forward -L "${lport}:${hostport}" "${via}" 2>/dev/null \
        || { log "could not forward localhost:${lport} -> ${hostport} via ${via}"; exit 1; }
    trap "ssh -O cancel -L '${lport}:${hostport}' '${via}' 2>/dev/null" EXIT
    trap 'exit 130' INT TERM
    until nc -z localhost "${lport}" 2>/dev/null; do
        (( tries++ < 15 )) || { log "tunnel to ${hostport} failed"; exit 1; }
        sleep 1
    done
    local_url="http://localhost:${lport}/${url#http://*/}"
    log "localhost:${lport} -> ${hostport} (via ${via})"
    log "Open the viewer: ${local_url}"
    log "Ctrl-C closes the tunnel; the viewer job keeps running"
    open "${local_url}" 2>/dev/null || xdg-open "${local_url}" 2>/dev/null || true
    while ssh -O check "${via}" 2>/dev/null; do sleep 5; done
    log "connection to ${via} closed"
}

cmd="${1:-sync}"
[[ $# -gt 0 ]] && shift

case "${cmd}" in
    -h|--help|help) ;;
    *) ensure_master "${MOGON_HOST}" ;;
esac

case "${cmd}" in
    push) push "$@" ;;
    pull) pull "$@" ;;
    sync) push "$@"; pull "$@" ;;
    run)
        [[ $# -gt 0 ]] || { echo "usage: $0 run <command...>" >&2; exit 2; }
        push
        out="$(mktemp)"
        tty=""; [[ -t 0 ]] && tty=-t
        set +e
        remote "${tty}" bash -lc "$*" | tee "${out}"
        rc=${PIPESTATUS[0]}
        set -e
        pull
        # A viewer step with viewer.tunnel set asks for a tunnel to this machine.
        bench="$(grep -oE 'sync_mogon\.sh tunnel [A-Za-z0-9_-]+' "${out}" | tail -n1 | awk '{print $3}' || true)"
        rm -f "${out}"
        [[ ${rc} -eq 0 && -n "${bench}" ]] && tunnel "${bench}"
        exit "${rc}"
        ;;
    shell)
        push
        remote -t bash -l
        ;;
    fetch)
        mkdir -p "${LOCAL_DIR}/mogon-out"
        for d in results runs; do
            log "fetch ${MOGON_HOST}:${MOGON_PFS}/${d}/ -> mogon-out/${d}/"
            rsync -rlptzu --itemize-changes "${MOGON_HOST}:${MOGON_PFS}/${d}/" "${LOCAL_DIR}/mogon-out/${d}/" || true
        done
        ;;
    view|tunnel)
        bench="${1:-}"
        [[ -d "${LOCAL_DIR}/demo/${bench}" && -n "${bench}" ]] \
            || { echo "usage: $0 ${cmd} <$(ls "${LOCAL_DIR}/demo" | paste -sd'|' -)>" >&2; exit 2; }
        if [[ "${cmd}" == view ]]; then
            push >/dev/null
            # -x: no X11, so the step does not open a cluster-side browser.
            remote -x bash -lc "demo/${bench}/*_visualize.sh"
        fi
        tunnel "${bench}"
        ;;
    -h|--help|help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0" ;;
    *) echo "unknown command '${cmd}' (see $0 --help)" >&2; exit 2 ;;
esac
