#!/bin/bash
# DLIO step 1: clean the DLIO data/trace/result directories and generate the
# UNet3D training dataset (notebook steps 2-6). Tracing is off for this phase.
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"
demo_slurm_step "${DEMO_DLIO_NODES:-1}" "${DEMO_DLIO_TASKS:-}" "${DEMO_SLURM_TIME:-}" "$@"
source "$(dirname "${DEMO_STEP_SCRIPT}")/_workload.sh"

log "Cleaning ${DATA_DIR}, ${TRACE_DIR}, ${RESULT_DIR}"
demo_fresh_dir "${DATA_DIR}" "${TRACE_DIR}" "${RESULT_DIR}"

OUT="${RESULT_DIR}/generate"
log "Generating the ${DEMO_DLIO_WORKLOAD:-default} dataset into ${DLIO_WORKLOAD_DIR}"
export DFTRACER_ENABLE=0
demo_mpirun dlio_benchmark "${DLIO_ARGS[@]}" \
    ++workload.workflow.generate_data=True \
    ++workload.workflow.train=False \
    hydra.run.dir="${OUT}" \
    ++workload.output.folder="${OUT}" \
    2>&1 | tee "${OUT}.log"

log "Generated dataset:"
du -sh --apparent-size "${DLIO_WORKLOAD_DIR}/data"/*
