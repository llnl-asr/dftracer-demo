#!/bin/bash
# DLIO step 5: generic DFAnalyzer POSIX analysis of the training traces
# (notebook step 11).
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"
demo_slurm_step 1 1 "${DEMO_SLURM_TIME}" "$@"

OUT="${RESULT_DIR}/analysis-posix"
demo_fresh_dir "${OUT}"
log "Analyzing ${TRACE_DIR}/compact -> ${OUT}"
cd "${OUT}"
dfanalyzer \
    trace_path="${TRACE_DIR}/compact" \
    analyzer/preset=posix \
    hydra.run.dir="${OUT}" \
    2>&1 | tee "${OUT}/dfanalyzer.txt"
