#!/bin/bash
# Run every IOR demo step in order, stopping at the first failure.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for step in 01_run_ior 02_compact_traces 03_inspect_traces 04_analyze 05_visualize; do
    echo "================ ${step} ================"
    "${HERE}/${step}.sh"
done
