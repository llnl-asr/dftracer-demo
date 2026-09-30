#!/bin/bash
# DLIO workload overrides shared by the generate and train steps (from the
# dlio section of config.yaml). Sourced, not run. Keys left empty in the config
# are not passed, so DLIO's workload defaults apply.
DLIO_WORKLOAD_DIR="${DATA_DIR}/${DEMO_DLIO_WORKLOAD:-default}"
DLIO_ARGS=()
demo_optkv DLIO_ARGS workload "${DEMO_DLIO_WORKLOAD:-}"
demo_optkv DLIO_ARGS ++workload.dataset.num_files_train "${DEMO_DLIO_NUM_FILES_TRAIN:-}"
demo_optkv DLIO_ARGS ++workload.dataset.record_length_bytes "${DEMO_DLIO_RECORD_LENGTH_BYTES:-}"
[[ -n "${DEMO_DLIO_RECORD_LENGTH_BYTES:-}" ]] \
    && DLIO_ARGS+=(++workload.dataset.record_length_bytes_stdev=0)
DLIO_ARGS+=(
    "++workload.dataset.data_folder=${DLIO_WORKLOAD_DIR}/data"
    "++workload.checkpoint.checkpoint_folder=${DLIO_WORKLOAD_DIR}/checkpoint"
)
demo_optkv DLIO_ARGS ++workload.reader.batch_size "${DEMO_DLIO_BATCH_SIZE:-}"
demo_optkv DLIO_ARGS ++workload.train.epochs "${DEMO_DLIO_EPOCHS:-}"
demo_optwords DLIO_ARGS "${DEMO_DLIO_EXTRA:-}"
