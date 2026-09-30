#!/bin/bash
# IOR step 4: analyze the traces with DFAnalyzer using the POSIX preset
# (notebook steps 9-11). The summary tables are printed to the job log; the
# analyzer's checkpoints and logs land in results/ior/analysis.
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"
demo_slurm_step 1 1 "${DEMO_SLURM_TIME}" "$@"

OUT="${RESULT_DIR}/analysis"
demo_fresh_dir "${OUT}"
log "Analyzing ${TRACE_DIR}/compact -> ${OUT}"
cd "${OUT}"
dfanalyzer \
    trace_path="${TRACE_DIR}/compact" \
    analyzer/preset=posix \
    hydra.run.dir="${OUT}" \
    2>&1 | tee "${OUT}/dfanalyzer.txt"
