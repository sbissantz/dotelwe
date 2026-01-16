#!/bin/bash

# project structure:
#
# ~/projects/simreplicabim/
# |├── simreplicabim.sh
# |├── simreplicabim.R
# |├── runs/
# |   |└── 20498908/
# |       |├── stdout.log
# |       |├── stderr.log
# |       |├── env.txt
# |       |├── sessioninfo.txt
# |       |└── results/
#
# Important: create /run before your submit!

#SBATCH --job-name=srb   # job name (required; used below: '%x')
                               
#SBATCH --time=00:05:00            # format:HH:MM:SS
                                   # Tip: add ~10% safety margin

#SBATCH --mem=500M                 # options: K M G T 

# #SBATCH --partition=epyc-768     # see: sumpartpro output for more

#SBATCH --nodes=1                  # 1 physical node
#SBATCH --ntasks-per-node=1        # 1 task(s)/processe(s) on node
#SBATCH --cpus-per-task=1          # 1 CPU core per task (no threading)

#SBATCH --hint=nomultithread       # avoid hardware hyper-threading (intel) 
                                   # or smt (amd)

#SBATCH --output=runs/%j/stdout.log     # create ./runs/%j/stdout.log
#SBATCH --error=runs/%j/stderr.log      # create ./runs/%j/stderr.log

#SBATCH --mail-type=END            # options: END, FAIL, ALL
                            
# --- sanity checks ---

set -euo pipefail                  # strict shell mode: fail fast on 
                                   # -e: errors, -u: unset variables, 
                                   # -o pipefail: broken pipeline

# --- files / logging ---

RUN_DIR="$SLURM_SUBMIT_DIR/runs/$SLURM_JOB_ID" 
mkdir -p "$RUN_DIR" # create per-job run directory 
cd "$RUN_DIR"       # switch into it

# create folder inside RUN_DIR/<jobid>
mkdir -p results                  # store the results 
mkdir -p scripts                  # keep copy of scripts that were run

cp -f "$SLURM_SUBMIT_DIR/simreplicabim.sh" scripts/ || true
cp -f "$SLURM_SUBMIT_DIR/simreplicabim.R"  scripts/ || true

# --- logging (start) ---

echo "Job ID: $SLURM_JOB_ID"                          # unique job identifier
echo "Name: $SLURM_JOB_NAME"                          # job name (%x)
echo "Node: ${SLURMD_NODENAME:-$SLURM_NODELIST}"      # single node or fallback: compact nodelist
echo "Partition: $SLURM_JOB_PARTITION"                # partition used
echo "Start: $(date -Is)"                             # ISO-8601 start time
echo

# --- modules ---

module purge
module load R/latest       # version, e.g., in r session info
# module load R/4.3        # set version explicitly

# --- environment ---

# thread safety: use envar value if it exists, otherwise default: 1
THREADS=${SLURM_CPUS_PER_TASK:-1}

export OMP_NUM_THREADS="$THREADS"
export MKL_NUM_THREADS="$THREADS"
export OPENBLAS_NUM_THREADS="$THREADS"
export NUMEXPR_NUM_THREADS="$THREADS"
export STAN_NUM_THREADS="$THREADS"

env | sort > "env.txt" # record environment: reproducibility

# --- run ---

# Put the following at the top of simreplicabim.R:
# rundir <- Sys.getenv("RUNDIR", ".")
# sink(file.path(rundir, "rsessioninfo.txt"))
# sessioninfo::session_info()
# sink()

# options(mc.cores = 4)
# fit <- mod$sample(
  # chains = 4,
  # parallel_chains = 4,
  # threads_per_chain = 1
# )
# 4 chains x 1 core/chain = 4 cores total
#

srun Rscript "$SLURM_SUBMIT_DIR/simreplicabim.R"

# --- move files ---

#mkdir -p $HOME/outgoing/simreplicabim
#cp -r * $HOME/outgoint

# --- logging (end) ---

echo
echo "End: $(date -Is)"
