# dftracer-demo

Hands-on demo of [DFTracer](https://github.com/llnl-asr/dftracer): trace an HPC
I/O benchmark (**IOR**) and a deep-learning I/O benchmark (**DLIO**), then
compact, inspect, analyze ([DFAnalyzer](https://github.com/llnl-asr/dfanalyzer))
and visualize ([dftracer-utils](https://github.com/llnl-asr/dftracer-utils)
`dftracer_server`) the traces.

Every step is a script that runs through Slurm. The defaults target
**Matrix @ LLNL**. A ready-made config for **MOGON NHR @ JGU Mainz**, plus a
script to sync, run and view it from your workstation, is described in
[Running on MOGON NHR](#5-running-on-mogon-nhr).

```text
config.yaml ──> setup.sh ──> activate_env.sh ──> demo/ior/*   (5 steps)
                                             └─> demo/dlio/*  (7 steps)
```

## 1. Configure

All settings live in [config.yaml](config.yaml). The scripts never hard-code
modules, paths or parameters.

- Values may use environment variables (`${USER}`, `${HOME}`, …) and
  `${DEMO_ROOT}`, the repository root.
- Each key is exported to the shell as `DEMO_<SECTION>_<KEY>`. For example,
  `paths.traces` becomes `$DEMO_PATHS_TRACES` and `ior.tasks` becomes
  `$DEMO_IOR_TASKS`. Lists are exported space separated.
- Each `paths` key is also exported as `DEMO_<KEY>`, so you can define your
  own paths and reuse them in any value below them:

  ```yaml
  paths:
    pfs: /p/lustre5/${USER}          # -> $DEMO_PFS
    data: ${DEMO_PFS}/dftracer-demo  # -> $DEMO_DATA
    scratch: ${DEMO_PFS}/scratch     # -> $DEMO_SCRATCH
  ior:
    args: -b 32m -t 1m -o ${DEMO_SCRATCH}/ior.dat
  ```

  References resolve in file order. The standard paths (`$DEMO_INSTALL`,
  `$DEMO_DATA`, `$DEMO_TRACES`, …) work anywhere, even when left out. A
  `${DEMO_…}` that isn't defined above its use is reported as a warning.
- To use another file: `export DEMO_CONFIG=/path/to/my-config.yaml`.
  [config.mogon-nhr.yaml](config.mogon-nhr.yaml) is an example for another
  site.
- **Every key is optional.** If a key is removed or left empty (`""`, `[]`,
  `{}`), its flag or variable is left out of the command entirely, and the
  tool's or Slurm's own default applies. For example, no `slurm.mpi` means no
  `--mpi`, no `slurm.time` means no `--time`, an empty `env` entry is not
  exported, and no `dlio.epochs` means DLIO uses the workload's epochs. The
  exceptions are `paths.*`, which falls back to `${DEMO_ROOT}/<name>`
  (`install`, `build`, `data`, `traces`, `results`, `runs`), and
  `ior.nodes`/`dlio.nodes`, which default to 1 because Matrix rejects jobs that
  request no size.
- Every step logs the exact `sbatch`, `srun` and tool command it runs.

### `modules`

| Key | Default | Meaning |
|-----|---------|---------|
| `purge` | `false` | run `module purge` before loading |
| `load` | `gcc/12.1.1`, `openmpi/4.1.2`, `python/3.11.5` | modules loaded in order by `activate_env.sh` (a Mogon set is in the comments) |

### `env`

These are exported as-is by `activate_env.sh`. Add any variable the site needs.

| Key | Default | Meaning |
|-----|---------|---------|
| `OMPI_MCA_btl` | `^openib` | silences Open MPI openib warnings on Matrix |
| `OMPI_MCA_opal_common_ucx_opal_mem_hooks` | `1` | silences the UCX `VM_UNMAP` warning |
| `PIP_EXTRA_INDEX_URL` | `https://pypi.org/simple` | overrides unreachable extra indexes from a personal `pip.conf` |

### `paths`

| Key | Default | Contents |
|-----|---------|----------|
| `pfs` | `/p/lustre5/${USER}` | parallel file system root, reused as `${DEMO_PFS}` (an example of your own path; add as many as you need) |
| `install` | `${DEMO_ROOT}/install` | Python venv, Node.js, IOR binaries |
| `build` | `${DEMO_ROOT}/build` | source checkouts built by `setup.sh` |
| `data` | `${DEMO_PFS}/dftracer-demo` | benchmark data, i.e. the I/O being traced (use a parallel file system) |
| `traces` | `${DEMO_ROOT}/traces` | DFTracer traces: `<bench>/raw/` and `<bench>/compact/` |
| `results` | `${DEMO_ROOT}/results` | benchmark output and analysis reports |
| `runs` | `${DEMO_ROOT}/runs` | setup log and the Slurm job logs of every step |

### `software`

| Key | Default | Meaning |
|-----|---------|---------|
| `ior.repo`, `ior.ref` | `hpc/ior`, `4.0.0` | IOR source, built by `setup.sh` |
| `node` | `lts` | Node.js version installed with `nodeenv`; needed to build the `dftracer_server` web UI |
| `python` | see file | pip packages, installed in order: latest `develop` of dftracer-utils, pydftracer, dftracer and dfanalyzer from **llnl-asr**, and `main` of dlio_benchmark |

### `slurm`

| Key | Default | Meaning |
|-----|---------|---------|
| `partition` | `pdebug` | partition for every step |
| `account` | `""` | bank. Empty uses your default |
| `time` | `00:15:00` | time limit per step (short limits backfill sooner) |
| `extra` | `""` | extra `sbatch` flags, e.g. `--qos=standby` |
| `mpi` | `pmix_v3` | `srun --mpi` plugin used to launch MPI ranks |
| `launcher` | `srun` | how MPI ranks are started: `srun`, or `mpirun` (the MPI library's own launcher, run inside the allocation) when the site's `srun` lacks the PMI plugin the MPI needs |

### Benchmark and tool parameters

| Key | Default | Meaning |
|-----|---------|---------|
| `dftracer.inc_metadata` | `1` | `DFTRACER_INC_METADATA`: record file names/sizes |
| `dftracer.compression` | `1` | `DFTRACER_TRACE_COMPRESSION`: write `*.pfw.gz` |
| `ior.nodes`, `ior.tasks` | `1`, `2` | IOR job size |
| `ior.app_name` | `ior` | trace file prefix |
| `ior.args` | `-b 32m -t 1m -i 5 -F -w -m` | IOR options (32 MB block, 1 MB transfer, 5 iterations, file per process, write) |
| `dlio.nodes`, `dlio.tasks` | `1`, `2` | DLIO job size |
| `dlio.app_name` | `unet3d` | compacted trace prefix |
| `dlio.workload` | `unet3d_a100` | DLIO workload config |
| `dlio.num_files_train` | `32` | dataset files |
| `dlio.record_length_bytes` | `1048576` | bytes per sample |
| `dlio.batch_size`, `dlio.epochs` | `1`, `1` | training loop size |
| `dlio.extra` | `""` | extra Hydra overrides, e.g. `++workload.reader.read_threads=2` |
| `analyzer.time_granularity` | `10` | window (seconds) for the DLIO-preset analysis |
| `viewer.port` | `8080` | `dftracer_server` port (a free one is picked if taken) |
| `viewer.time` | `01:00:00` | how long the viewer job stays up |
| `viewer.browser` | `firefox` | browser opened on the login node when `$DISPLAY` is set |
| `viewer.proxy` | `true` | relay the viewer through the login node, so it opens at `http://<login-node>:<port>/` |
| `viewer.tunnel` | `""` | SSH host of the login node as seen from your workstation (e.g. `mogon-nhr`). Set it when neither VS Code Remote-SSH nor `$DISPLAY` is available. The step then prints the tunnel command instead of opening a browser, and [sync_mogon.sh](#5-running-on-mogon-nhr) opens the viewer in your local browser |

## 2. Set up the environment

Run this once, on a login node (the install clones from GitHub):

```bash
./setup.sh
```

`setup.sh` takes about 15 minutes and logs to `runs/setup-<timestamp>.log`. It:

1. **cleans**: removes `paths.install` and `paths.build`,
2. **creates a venv**: loads `modules.load` and runs `python -m venv`,
3. **activates**: sources `activate_env.sh` (modules + venv + config),
4. **installs**:
   - Node.js via `nodeenv`,
   - the `software.python` packages (dftracer-utils is built with its web UI),
   - mpi4py from source against the loaded MPI,
   - IOR.

In every new shell, before running anything by hand:

```bash
source ./activate_env.sh
```

The demo scripts source it themselves, so this is only needed for your own
commands (`dftracer_split --help`, `dfanalyzer --help`, …).

## 3. Run the demos

Run from the repository root on a login node. Each step script submits itself
with `sbatch`, streams the job output to your terminal and exits with the job's
status. If you are already inside an allocation (`salloc`), it runs in place
instead.

### All in one go

```bash
demo/ior/run_all.sh      # IOR: 5 steps
demo/dlio/run_all.sh     # DLIO: 7 steps
```

`run_all.sh` runs the steps in order and stops at the first failure. The last
step of each leaves a viewer job running (see [Visualize](#4-visualize)).

To keep a run going after you log out and follow it from anywhere:

```bash
nohup demo/ior/run_all.sh > runs/ior/run_all.log 2>&1 &
tail -f runs/ior/run_all.log
```

### Step by step: IOR (traditional HPC I/O)

```bash
demo/ior/01_run_ior.sh
demo/ior/02_compact_traces.sh
demo/ior/03_inspect_traces.sh
demo/ior/04_analyze.sh
demo/ior/05_visualize.sh
```

| Step | What it does | Output |
|------|--------------|--------|
| [01_run_ior](demo/ior/01_run_ior.sh) | Cleans the IOR data/trace/result directories, then runs IOR on `ior.tasks` ranks with DFTracer injected through `LD_PRELOAD` (`DFTRACER_ENABLE=1`, `DFTRACER_INIT=PRELOAD`, tracing only `DFTRACER_DATA_DIR`) | `traces/ior/raw/*.pfw.gz`, `results/ior/ior-summary.csv` |
| [02_compact_traces](demo/ior/02_compact_traces.sh) | Merges the per-rank traces into compact, indexed chunks with `dftracer_split` | `traces/ior/compact/` |
| [03_inspect_traces](demo/ior/03_inspect_traces.sh) | Prints the first and last events. Each line is one JSON event (`name`, `cat`, `ts`, `dur`, `pid`, `args`). Runs on the login node | terminal |
| [04_analyze](demo/ior/04_analyze.sh) | DFAnalyzer with the POSIX preset: job time, file/process counts, bandwidth, layer breakdown | `results/ior/analysis/dfanalyzer.txt` |
| [05_visualize](demo/ior/05_visualize.sh) | Starts `dftracer_server` on the compacted traces and prints the viewer URL | viewer job |

### Step by step: DLIO (deep-learning I/O, UNet3D)

```bash
demo/dlio/01_generate_data.sh
demo/dlio/02_train.sh
demo/dlio/03_compact_traces.sh
demo/dlio/04_inspect_traces.sh
demo/dlio/05_analyze.sh
demo/dlio/06_analyze_dlio.sh
demo/dlio/07_visualize.sh
```

| Step | What it does | Output |
|------|--------------|--------|
| [01_generate_data](demo/dlio/01_generate_data.sh) | Cleans the DLIO directories and generates the dataset (tracing off) | `${paths.data}/dlio/unet3d_a100/data/` |
| [02_train](demo/dlio/02_train.sh) | Trains with `DFTRACER_ENABLE=1`. DLIO's pydftracer annotations record AI/ML events (`train`, `epoch`, `fetch.*`, `compute`, `checkpoint`) together with POSIX I/O, including the forked DataLoader workers | `traces/dlio/raw/*.pfw.gz`, `results/dlio/train/` |
| [03_compact_traces](demo/dlio/03_compact_traces.sh) | `dftracer_split` into compact, indexed chunks | `traces/dlio/compact/` |
| [04_inspect_traces](demo/dlio/04_inspect_traces.sh) | First/last events and event counts per category. Runs on the login node | terminal |
| [05_analyze](demo/dlio/05_analyze.sh) | DFAnalyzer, POSIX preset | `results/dlio/analysis-posix/` |
| [06_analyze_dlio](demo/dlio/06_analyze_dlio.sh) | DFAnalyzer, DLIO preset: I/O broken down by checkpoint, data loader, fork and reader over `analyzer.time_granularity` windows | `results/dlio/analysis-dlio/` |
| [07_visualize](demo/dlio/07_visualize.sh) | Starts `dftracer_server` on the compacted traces and prints the viewer URL | viewer job |

Each step depends only on the previous step's files, so you can re-run any step
on its own. For example, change `analyzer.time_granularity` and re-run just
`06_analyze_dlio.sh`.

### Tracking a run

| What | Where |
|------|-------|
| Live output of a step | your terminal (the job log is streamed) |
| Job log of each step | `runs/<ior\|dlio>/<step>-<timestamp>.out` |
| Queue | `squeue -u $USER` (jobs are named `dftd-<bench>-<step>`) |
| Finished jobs | `sacct -u $USER --name=dftd-ior-01_run_ior` |
| Setup log | `runs/setup-<timestamp>.log` |

For interactive use, grab an allocation once and run the steps inside it. They
run in place, with no queue wait between steps:

```bash
salloc -p pdebug -N 1 -n 2 -t 01:00:00
demo/ior/01_run_ior.sh
...
```

## 4. Visualize

`05_visualize.sh` (IOR) and `07_visualize.sh` (DLIO) start `dftracer_server` on
the compacted traces in a Slurm job that lasts `viewer.time`. The server runs on
a compute node and requires a random access token.

With `viewer.proxy: true` (the default), the script also starts a small relay
([scripts/viewer_proxy.py](scripts/viewer_proxy.py)) on the login node. You then
open the viewer directly at the login node:

```
Viewer is up on the compute node: http://matrix9:8080/?token=c7bb…
Proxied through matrix1:8080 (stops with the job)
Open the viewer: http://matrix1:8080/?token=c7bb…
Stop it with: scancel 351250
```

- **Directly**: open the printed `http://<login-node>:<port>/?token=…` from any
  machine that can reach the login node. On a busy login node, the next free
  port after `viewer.port` is used.
- **Browser on the cluster**: with X11 forwarding (`ssh -X`) or a VNC session,
  the script opens the URL in `viewer.browser` (Firefox) itself.
- **SSH tunnel**: if the login node is not reachable from your machine, run the
  printed `ssh -L …` command and open `http://localhost:<port>/?token=…`.
- **Tunnel from your workstation** (`viewer.tunnel` set): the step prints
  `scripts/sync_mogon.sh tunnel <bench>` and an equivalent `ssh -N -L …`
  command to run on your workstation. See
  [Viewing traces](#viewing-traces-in-your-local-browser).
- **VS Code Remote-SSH**: when the step runs in a VS Code terminal, it opens
  `http://localhost:<port>/?token=…` through VS Code, which forwards the port
  to your machine automatically. To do it by hand, add `<port>` in the *Ports*
  panel and open `http://localhost:<port>/?token=…`. The integrated browser
  (*Simple Browser: Show*) only works with such a forwarded `localhost` URL,
  not with `http://matrix1:…`.

The relay only forwards bytes, so the token is still checked by the server, and
the relay exits by itself when the viewer job ends. The URL of the latest viewer
is saved in `runs/<bench>/viewer.url`, and the relay log in
`runs/<bench>/viewer_proxy-<jobid>.log`. Stop the viewer with
`scancel <jobid>` when you are done.

`dftracer_server` indexes the traces when it starts, so the page can take a
minute to load after the URL is printed.

## 5. Running on MOGON NHR

You edit the repository on your workstation; `scripts/sync_mogon.sh` copies it
to `~/projects/dftracer-demo` on MOGON NHR, runs the steps there with
[config.mogon-nhr.yaml](config.mogon-nhr.yaml), and tunnels the viewer back to
your local browser.

### Prerequisites

An SSH host `mogon-nhr` in `~/.ssh/config` (login through the `hpcgate` jump
host) with connection sharing:

```sshconfig
Host mogon-nhr
    HostName mogon-nhr-01
    User <your-user>
    ProxyJump hpcgate
    IdentityFile ~/.ssh/<your-key>
    ControlMaster auto
    ControlPath /tmp/%r@%h:%p
```

The login node asks for keyboard-interactive authentication (OTP), so the
script keeps one shared connection open and runs every `ssh`/`rsync` through
it: you log in once per session. Close it with `ssh -O exit mogon-nhr`.

### Where things go

HOME is small, so only the repository lives there. Everything the demo writes
is under `${DEMO_PFS}/dftracer-demo` on Lustre, with
`paths.pfs: /lustre/project/ki-mawahpc/${USER}`:

| What | Where |
|------|-------|
| repository | `~/projects/dftracer-demo` |
| venv, Node.js, IOR (`paths.install`) | `${DEMO_PFS}/dftracer-demo/install` |
| builds, data, traces, results, runs | `${DEMO_PFS}/dftracer-demo/{build,data,traces,results,runs}` |

### Sync

```bash
scripts/sync_mogon.sh              # two-way: push, then pull
scripts/sync_mogon.sh push         # workstation -> cluster only
scripts/sync_mogon.sh pull         # cluster -> workstation only
scripts/sync_mogon.sh sync -n      # dry run (extra flags go to rsync)
```

- Both directions use `rsync --update`: a file is replaced only by a newer copy,
  so edits on either side survive. If the same file changed on both sides, the
  newer one wins.
- Deletions are not propagated. Delete on both sides, or use
  `push --delete` to mirror the workstation onto the cluster.
- `.git`, `install/`, `build/`, `data/` and `software/` are never synced. Commit
  and push to git from the workstation.
- Override the target with `MOGON_HOST`, `MOGON_DIR` and `MOGON_PFS`.

### Run

```bash
scripts/sync_mogon.sh run ./setup.sh                # once, on the login node
scripts/sync_mogon.sh run demo/ior/run_all.sh
scripts/sync_mogon.sh run demo/dlio/02_train.sh
scripts/sync_mogon.sh shell                         # interactive shell in the repo
scripts/sync_mogon.sh fetch                         # results/ and runs/ -> ./mogon-out/
```

`run` pushes, runs the command in the remote repository with
`DEMO_CONFIG=config.mogon-nhr.yaml`, then pulls. When you log in to the cluster
yourself instead, select the config first (or add this to `~/.bashrc` there):

```bash
export DEMO_CONFIG=~/projects/dftracer-demo/config.mogon-nhr.yaml
```

### Viewing traces in your local browser

VS Code Remote-SSH is not available on MOGON, so `viewer.tunnel: mogon-nhr` is
set. The viewer goes compute node -> login-node relay (`viewer.proxy`) ->
workstation (SSH port forward on the shared connection):

```bash
scripts/sync_mogon.sh run demo/ior/run_all.sh   # opens the viewer when the last step starts it
scripts/sync_mogon.sh view dlio                 # start only the viewer, then open it
scripts/sync_mogon.sh tunnel ior                # reconnect to a viewer that is already running
```

The viewer opens at `http://localhost:8080/?token=…` (the next free port if
8080 is taken; set `MOGON_VIEW_PORT` to choose another). Ctrl-C closes only the
tunnel; the viewer job runs until `viewer.time` or `scancel <jobid>`.

### Notes for MOGON NHR

- **MPI launch**: Slurm's `srun` offers only the `pmi2` and `cray_shasta`
  plugins, while OpenMPI 5 needs PMIx. Launched with `srun`, every rank starts
  as its own rank 0 (IOR then fails with `stat(... test.bat.00000000.0)`). The
  config sets `slurm.launcher: mpirun`, which starts the ranks with OpenMPI's
  `mpirun` inside the allocation; `LD_PRELOAD` still reaches only the ranks
  (`-x LD_PRELOAD=…`).
- **Modules**: `mpi/OpenMPI/5.0.3-GCC-13.3.0` and
  `lang/Python/3.12.3-GCCcore-13.3.0`.
- **Read-only venv scripts**: the EasyBuild Python installs its venv templates
  read-only, so `bin/activate` came out read-only and `nodeenv` could not write
  to it. `setup.sh` now makes the venv owner-writable right after creating it.
- **Slurm**: account `ki-mawahpc`, partition `ki-quick`.

## Layout

```
config.yaml               all settings (Matrix)
config.mogon-nhr.yaml     all settings for MOGON NHR
setup.sh                  clean, fresh venv, activate, install
activate_env.sh           module load + venv + config variables (source it)
scripts/common.sh         step helpers (Slurm self-submission, srun/mpirun, viewer)
scripts/load_config.py    config.yaml -> DEMO_* shell variables
scripts/viewer_proxy.py   login-node relay to dftracer_server
scripts/sync_mogon.sh     workstation <-> MOGON NHR sync, remote run, viewer tunnel
demo/ior/                 IOR steps + run_all.sh
demo/dlio/                DLIO steps + run_all.sh (_workload.sh: shared DLIO overrides)
install/  build/          created by setup.sh
traces/<bench>/           raw/ and compact/ DFTracer traces
results/<bench>/          benchmark output and analysis
runs/<bench>/             Slurm job logs, viewer.url
mogon-out/                results/ and runs/ fetched from MOGON NHR (git-ignored)
```

The original notebooks (`demo/*/demo.ipynb`) are kept for reference. This
version of the demo runs entirely through the scripts.

## Notes for Matrix

- pdebug is often busy. The short default `slurm.time` lets jobs backfill
  quickly. Switch `slurm.partition` to `pbatch` if pdebug is full.
- Matrix allocates CPUs per GPU share (28 cores). Do not add `--cpus-per-task`
  to `slurm.extra`, or the job is rejected. The scripts split the allocated
  cores between the ranks themselves.
- LC's Python modules are Anaconda builds that ship their own MPICH.
  `setup.sh` builds mpi4py from source with `CC=mpicc`, `CXX=mpic++` and
  `LDSHARED="mpicc -shared"`, so it links the loaded Open MPI.
