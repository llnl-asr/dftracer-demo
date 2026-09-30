#!/bin/bash
# IOR step 2: merge the per-rank raw traces into compact, indexed chunks with
# dftracer_split from dftracer-utils (notebook step 7).
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"
demo_slurm_step 1 1 "${DEMO_SLURM_TIME:-}" "$@"

log "Compacting ${TRACE_DIR}/raw -> ${TRACE_DIR}/compact"
demo_fresh_dir "${TRACE_DIR}/compact"
SPLIT_ARGS=(-f -d "${TRACE_DIR}/raw" -o "${TRACE_DIR}/compact"
    --index-dir "${TRACE_DIR}/compact/.index"
    --executor-threads "$(demo_cpus)" --io-threads "$(demo_cpus)")
demo_opt SPLIT_ARGS -n "${DEMO_IOR_APP_NAME:-}"
log "dftracer_split $(demo_cmdline "${SPLIT_ARGS[@]}")"
dftracer_split "${SPLIT_ARGS[@]}"
ls -lh "${TRACE_DIR}/compact"
