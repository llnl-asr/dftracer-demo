#!/bin/bash
# Run every DLIO demo step in order, stopping at the first failure.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for step in 01_generate_data 02_train 03_compact_traces 04_inspect_traces \
            05_analyze 06_analyze_dlio 07_visualize; do
    echo "================ ${step} ================"
    "${HERE}/${step}.sh"
done
