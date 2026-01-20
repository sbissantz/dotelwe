#!/bin/bash

# project structure: 
#
# ~/projects/foobar/
# |├── foobar.sh
# |├── foobar.R
# |├── runs/
# |   |└── 20498908/
# |       |├── stdout.log
# |       |├── stderr.log
# |       |├── env.txt
# |       |├── rsessioninfo.txt
# |       |└── results/
#
# Important: create /run before your submit!

#SBATCH --job-name=foobar          # job name 
                               
#SBATCH --time=00:05:00            # format:HH:MM:SS
                                   # Tip: add ~10% safety margin, because a high
                                   # load might negatively impact runtime of your job(s)!

#SBATCH --mem=1G                   # options: K M G T 

#SBATCH --partition=epyc-768       # see: lsparts output for more
                                   # use for projects or specfic parititons

# important: you can only use one ressource layout!

# ressource layout: global         # slurm decides the placement across nodes
# #SBATCH --ntasks=1               # total number of tasks (processes)
# (commented out)                  # e.g. 24 independent R processes

# ressource layout: local
#SBATCH --nodes=1                   # allocate exactly 1 physical node
#SBATCH --ntasks-per-node=1         # place 1 task(s)/processe(s) on that node
#SBATCH --cpus-per-task=1           # 1 CPU core per task (no threading)
                                    # force all tasks onto a single node
                                    # useful when running many independent processes

#SBATCH --hint=nomultithread        # avoid hardware hyper-threading (intel) / smt (amd)

#SBATCH --array=1-10                # for array jobs

#SBATCH --output=runs/%j/stdout.log   # create ./runs/%j/stdout.log
#SBATCH --error=runs/%j/stderr.log    # create ./runs/%j/stderr.log
                                     
#SBATCH --mail-type=END              # options: END, FAIL, ALL

                                     # Option "NONE" does not work (?)
#SBATCH --export=ALL                 # start job in a clean environment 
                                     # no inherited shell vars (only SLURM_*)
                                     # variables defined below (see: export)
                                     # default: ALL (all variables inherited)
                            
# --- sanity checks ---

set -euo pipefail                      # strict shell mode: fail fast on 
                                       # -e: errors, -u: unset variables, 
                                       # -o pipefail: broken pipeline
                                       # Note: Under zsh use
                                       # set -eu
                                       # setopt pipefail

# --- files / logging ---

RUN_DIR="$SLURM_SUBMIT_DIR/runs/$(date +%H%M-%Y%m%d)_$SLURM_JOB_ID" 
mkdir -p "$RUN_DIR"                             # create per-job run directory 
cd "$RUN_DIR"                                   # switch into it

# create folder inside RUN_DIR/<jobid>
mkdir -p results                                # store the results 
mkdir -p scripts                                # keep copy of original scripts 

cp -f "$SLURM_SUBMIT_DIR/foobar.sh" scripts/ || true
cp -f "$SLURM_SUBMIT_DIR/foobar.R"  scripts/ || true

# --- logging (start) ---

echo "Job ID: $SLURM_JOB_ID"                        # unique job identifier
echo "Name: $SLURM_JOB_NAME"                        # job name (%x)
echo "Node: ${SLURMD_NODENAME:-$SLURM_NODELIST}"    # single node or fallback: compact nodelist
echo "Partition: $SLURM_JOB_PARTITION"              # partition used
echo "start: $(date -Is)"                           # ISO-8601 start time
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

# optional: record environment for reproducibility
env | sort > "env.txt" # record environment: reproducibility

# --- run ---
#
# put the following at the top of simreplicabim.R:
# writeLines(
#   capture.output(utils::sessionInfo()),
#   "sessioninfo.txt"
#)
# output goes to stdout.log

# options(mc.cores = 4)
# fit <- mod$sample(
  # chains = 4,
  # parallel_chains = 4,
  # threads_per_chain = 1
# )
# 4 chains x 1 core/chain = 4 cores total
#

srun Rscript "$SLURM_SUBMIT_DIR/foobar.R"

# --- logging (end) ---

echo
echo "end: $(date -Is)"
