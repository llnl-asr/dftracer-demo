#!/bin/bash
# DLIO step 4: peek at the compacted traces (notebook steps 8 and 10). Besides
# POSIX calls you will see AI/ML events such as ai_root, train, epoch,
# fetch.iter, fetch.block, item, compute and checkpoint.
# Only reads a few lines, so it runs directly on the login node.
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"

demo_show_traces "${TRACE_DIR}/compact"
log "Event counts by category:"
{ gzip -dc "${TRACE_DIR}"/compact/*.pfw.gz || true; } \
    | grep -o '"cat":"[^"]*"' | sort | uniq -c | sort -rn
