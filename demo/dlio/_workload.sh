#!/bin/bash
# DLIO workload overrides shared by the generate and train steps (from the
# dlio section of config.yaml). Sourced, not run.
DLIO_ARGS=(
    "workload=${DEMO_DLIO_WORKLOAD}"
    "++workload.dataset.num_files_train=${DEMO_DLIO_NUM_FILES_TRAIN}"
    "++workload.dataset.record_length_bytes=${DEMO_DLIO_RECORD_LENGTH_BYTES}"
    "++workload.dataset.record_length_bytes_stdev=0"
    "++workload.dataset.data_folder=${DATA_DIR}/${DEMO_DLIO_WORKLOAD}/data"
    "++workload.checkpoint.checkpoint_folder=${DATA_DIR}/${DEMO_DLIO_WORKLOAD}/checkpoint"
    "++workload.reader.batch_size=${DEMO_DLIO_BATCH_SIZE}"
    "++workload.train.epochs=${DEMO_DLIO_EPOCHS}"
)
# shellcheck disable=SC2206
DLIO_ARGS+=(${DEMO_DLIO_EXTRA})
