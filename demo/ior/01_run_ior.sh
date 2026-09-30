#!/bin/bash
# IOR step 1: clean the IOR data/trace/result directories, then run IOR with
# DFTracer attached through LD_PRELOAD (notebook steps 2-5).
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"
demo_slurm_step "${DEMO_IOR_NODES:-1}" "${DEMO_IOR_TASKS:-}" "${DEMO_SLURM_TIME:-}" "$@"

log "Cleaning ${DATA_DIR}, ${TRACE_DIR}, ${RESULT_DIR}"
demo_fresh_dir "${DATA_DIR}" "${TRACE_DIR}" "${RESULT_DIR}"

# --- DFTracer configuration ---------------------------------------------------
# Enable tracing and use the LD_PRELOAD mode, which intercepts POSIX calls of an
# unmodified binary.
export DFTRACER_ENABLE=1
export DFTRACER_INIT=PRELOAD
# Include file metadata (e.g. file names/sizes) in the events.
demo_export_opt DFTRACER_INC_METADATA "${DEMO_DFTRACER_INC_METADATA:-}"
# Only trace I/O under the benchmark data directory.
export DFTRACER_DATA_DIR="${DATA_DIR}"
# Write block-compressed traces (*.pfw.gz); rank/pid and app name are appended.
demo_export_opt DFTRACER_TRACE_COMPRESSION "${DEMO_DFTRACER_COMPRESSION:-}"
export DFTRACER_LOG_FILE="${TRACE_DIR}/raw/${DEMO_IOR_APP_NAME:-ior}"
mkdir -p "${TRACE_DIR}/raw"
PRELOAD="$(demo_dftracer_preload)"
log "DFTRACER_DATA_DIR=${DFTRACER_DATA_DIR}"
log "DFTRACER_LOG_FILE=${DFTRACER_LOG_FILE}"
log "LD_PRELOAD=${PRELOAD}"

# --- IOR --------------------------------------------------------------------
IOR_ARGS=(-o "${DATA_DIR}/test.bat")
demo_optwords IOR_ARGS "${DEMO_IOR_ARGS:-}"
IOR_ARGS+=(-O summaryFormat=CSV -O summaryFile="${RESULT_DIR}/ior-summary.csv")
log "Running IOR on ${SLURM_NTASKS} ranks"
demo_mpirun --export="ALL,LD_PRELOAD=${PRELOAD}" ior "${IOR_ARGS[@]}" \
    2>&1 | tee "${RESULT_DIR}/ior.log"

log "IOR summary (${RESULT_DIR}/ior-summary.csv):"
cat "${RESULT_DIR}/ior-summary.csv"
log "Raw traces:"
ls -lh "${TRACE_DIR}/raw"
