#!/bin/bash
# IOR step 3: peek at the compacted traces (notebook steps 6 and 8).
# Each line is one JSON event: name (open/write/close...), cat (POSIX),
# ts/dur (microseconds), pid/tid and args such as the file name and size.
# Only reads a few lines, so it runs directly on the login node.
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"

demo_show_traces "${TRACE_DIR}/compact"
