#!/bin/bash
# IOR step 5: explore the trace timeline in a browser with dftracer_server
# (dftracer-utils). The server runs in its own Slurm job for viewer.time; the
# URL (with an access token) is opened in viewer.browser when $DISPLAY is set.
# Stop it early with `scancel <jobid>`.
source "${DEMO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}/scripts/common.sh"

URL_FILE="${RUN_DIR}/viewer.url"
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    demo_serve_traces "${TRACE_DIR}/compact" "${URL_FILE}"
else
    : > "${URL_FILE}"   # created here so NFS sees the job's write
    demo_slurm_submit 1 1 "${DEMO_VIEWER_TIME}" "$@"
    demo_open_viewer "${DEMO_JOB_ID}" "${URL_FILE}" "${DEMO_JOB_LOG}"
fi
