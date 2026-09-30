#!/bin/bash
# DLIO step 6: DFAnalyzer with the DLIO preset (notebook step 12), which maps
# I/O onto the training structure (epochs, data loading, compute,
# checkpointing) over time windows of analyzer.time_granularity seconds.
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"
demo_slurm_step 1 1 "${DEMO_SLURM_TIME}" "$@"

OUT="${RESULT_DIR}/analysis-dlio"
demo_fresh_dir "${OUT}"
log "Analyzing ${TRACE_DIR}/compact with the dlio preset -> ${OUT}"
cd "${OUT}"
dfanalyzer \
    trace_path="${TRACE_DIR}/compact" \
    analyzer/preset=dlio \
    analyzer.time_granularity="${DEMO_ANALYZER_TIME_GRANULARITY}" \
    hydra.run.dir="${OUT}" \
    2>&1 | tee "${OUT}/dfanalyzer.txt"
