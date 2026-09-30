#!/bin/bash
# DLIO step 2: train UNet3D on the generated data with DFTracer enabled
# (notebook step 7). DLIO calls pydftracer itself, so DFTRACER_ENABLE=1 is
# enough to capture the AI/ML events (train, epoch, fetch.*, compute,
# checkpoint) together with the POSIX I/O on the data/checkpoint folders.
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"
demo_slurm_step "${DEMO_DLIO_NODES}" "${DEMO_DLIO_TASKS}" "${DEMO_SLURM_TIME}" "$@"
source "$(dirname "${DEMO_STEP_SCRIPT}")/_workload.sh"

[[ -d "${DATA_DIR}/${DEMO_DLIO_WORKLOAD}/data" ]] || die "no dataset; run 01_generate_data.sh first"

# --- DFTracer configuration ---------------------------------------------------
export DFTRACER_ENABLE=1
export DFTRACER_INC_METADATA="${DEMO_DFTRACER_INC_METADATA}"
export DFTRACER_TRACE_COMPRESSION="${DEMO_DFTRACER_COMPRESSION}"

OUT="${RESULT_DIR}/train"
demo_fresh_dir "${OUT}" "${TRACE_DIR}/raw"
log "Training ${DEMO_DLIO_WORKLOAD} on ${SLURM_NTASKS} ranks"
demo_mpirun dlio_benchmark "${DLIO_ARGS[@]}" \
    ++workload.workflow.generate_data=False \
    ++workload.workflow.train=True \
    hydra.run.dir="${OUT}" \
    ++workload.output.folder="${OUT}" \
    2>&1 | tee "${OUT}.log"

# DLIO writes trace-<rank>-of-<n>.pfw.gz next to its results; keep traces in
# paths.traces with the other benchmark.
mv "${OUT}"/*.pfw* "${TRACE_DIR}/raw/"
log "DLIO results in ${OUT}:"
ls "${OUT}"
log "Raw traces:"
ls -lh "${TRACE_DIR}/raw"
