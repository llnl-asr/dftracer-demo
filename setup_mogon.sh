#!/bin/bash

set -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Current script directory: $SCRIPT_DIR"

log "Loading modules..."
module load mpi/OpenMPI/5.0.3-GCC-13.3.0 lang/Python/3.12.3-GCCcore-13.3.0

log "Creating Python virtual environment..."
python -m venv ./install

log "Upgrading pip in the virtual environment..."
./install/bin/python -m pip install --upgrade pip

log "Building and installing IOR..."
if [ ! -d "${SCRIPT_DIR}/software/ior" ]; then
    log "Cloning IOR repository..."
    git clone https://github.com/hpc/ior.git "${SCRIPT_DIR}/software/ior"
    cd "${SCRIPT_DIR}/software/ior"
    git checkout tags/4.0.0 -b v4.0.0
    cd -
fi
cd software/ior
./bootstrap
./configure --prefix=${SCRIPT_DIR}/install
make
make install
cd -

log "Building and installing DLIO benchmark..."
if [ ! -d "${SCRIPT_DIR}/software/dlio_benchmark" ]; then
    log "Cloning DLIO benchmark repository..."
    git clone https://github.com/argonne-lcf/dlio_benchmark.git "${SCRIPT_DIR}/software/dlio_benchmark"
fi

log "Activating Python virtual environment..."
source ./install/bin/activate


log "Installing Python requirements..."
pip install -r requirements_mogon.txt

export CC=$(which mpicc)
export CXX=$(which mpic++)

pip install --force-reinstall --no-binary "mpi4py" mpi4py

log "Setup completed successfully."
