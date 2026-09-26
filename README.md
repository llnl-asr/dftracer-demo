# dftracer-demo

A demo to run dftracer with different workloads.

## Getting Started

### Option 1: Docker Development Container (Recommended)

The easiest way to get started is using the Docker development container:

1. **Prerequisites**: Install [Docker](https://docs.docker.com/get-docker/) and [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

2. **Open in VS Code**: Open this project in VS Code

3. **Start Dev Container**: Use Command Palette (`Cmd+Shift+P`) → "Dev Containers: Reopen in Container"

4. **Launch Jupyter**: Once the container is ready, run:
   ```bash
   jupyter lab
   ```

5. **Access Jupyter Lab**: Open <http://localhost:8888> in your browser

📖 **For detailed Docker setup instructions, see [.devcontainer/README.md](.devcontainer/README.md)**

### Option 2: Local Installation

1. **Setup the environment**:

   ```bash
   ./setup.sh
   source ./install/bin/activate
   ```

2. **Launch Jupyter**:

   ```bash
   jupyter lab
   ```

3. **Follow the demo guides**:
   - **Quick Start**: See `QUICK_START.md` for a brief overview
   - **Complete Guide**: See `DEMO_NARRATIVE_GUIDE.md` for detailed instructions

## Demo Contents

- **IOR Benchmark Demo** (`demo/ior/demo.ipynb`): Traditional I/O benchmarking with DFTracer
- **DLIO Benchmark Demo** (`demo/dlio/demo.ipynb`): Deep learning I/O pattern analysis


### Option 3: Cluster Installation

1. **Load the required modules**

   ```bash
   module load gcc
   module load python
   module load mvapich
   ```

2. **Setup the environment**:

   ```bash
   ./setup.sh
   source ./install/bin/activate
   ```

3. **Allocate compute node**:


   ```bash
   # For Slurm
   salloc -N 1 -t 2:00:00

   # For Cobalt
   qsub -I -n 1 -t 120 -q default

   # For Flux
   flux alloc -N 1 -t 2h
   ```

Specifically for OSU cluster Pitzer

   ```bash
   salloc -N 1 -t 2:00:00 --ntasks-per-node=48 --constraint=48core -A PAS3034
   ```

4. **Activate the environment**:

   ```bash
   source ./install/bin/activate
   ```

5. **Launch Jupyter**:

   ```bash
   jupyter lab --ip=$(hostname) --port=8888 --no-browser --allow-root
   ```

Copy the URL that is output. It will look like:
```
http://p0840.ten.osc.edu:8888/lab?token=b1320a0da58dbbd165ee1628469a06be1f1dd1d1a2a89f1a
```

6. **Open notebook**:

1. Open the notebook at ./demo/dlio/demo.ipynb
2. Select Kernel (you may have to install the jupyter plugin) and use the link copied above
3. **Follow the demo guides**:
   - **Quick Start**: See `QUICK_START.md` for a brief overview
   - **Complete Guide**: See `DEMO_NARRATIVE_GUIDE.md` for detailed instructions

## Demo Contents

- **IOR Benchmark Demo** (`demo/ior/demo.ipynb`): Traditional I/O benchmarking with DFTracer
- **DLIO Benchmark Demo** (`demo/dlio/demo.ipynb`): Deep learning I/O pattern analysis


## What You'll Learn

- How to configure and use DFTracer for I/O profiling
- Understanding different I/O patterns in HPC workloads
- Analyzing trace data to identify performance bottlenecks
- Using DFAnalyzer for visualization and insights

## License

DFTracer Demo is distributed under the terms of the MIT license.
All new contributions must be made under this license.

See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.

SPDX-License-Identifier: MIT

LLNL-CODE-2024514 — Applied Storage Research (ASR)
