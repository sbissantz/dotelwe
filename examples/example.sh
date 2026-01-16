#!/bin/bash

#SBATCH --job-name=foobar          # job name (required; used below: '%x')
                               
#SBATCH --time=00:05:00            # format:HH:MM:SS
                                   # Tip: add ~10% safety margin, because a high
                                   # load might negatively impact runtime of your job(s)!

#SBATCH --mem=1GB                   # options: K M G T 

# #SBATCH --partition=epyc-768    # see: sumpartpro output for more
                                   # use for projects or specfic parititons

# ressource layout: global
# #SBATCH --ntasks=1               # total number of tasks (processes)
# (commented out)                   # e.g. 24 independent R processes
                                    # let slurm decide the placement across nodes
                                   
# ressource layout: local
#SBATCH --nodes=1                   # allocate exactly 1 physical node
#SBATCH --ntasks-per-node=1         # place 1 task(s)/processe(s) on that node
#SBATCH --cpus-per-task=1           # 1 CPU core per task (no threading)
                                    # force all tasks onto a single node
                                    # useful when running many independent processes

#SBATCH --hint=nomultithread        # avoid hardware hyper-threading (intel) / smt (amd)

#SBATCH --output=$HOME/outgoing/%x-%j.out    # %x: job name %j: jobid
#SBATCH --error=$HOME/outgoing/%x-%j.err     # %x: job name %j: jobid  

#SBATCH --mail-type=END                # options: END, FAIL, ALL

#SBATCH --export=ALL                # start job in a clean environment 
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

# mkdir -p "$HOME/outgoing"

# --- logging (start) ---

echo "Job ID: $SLURM_JOB_ID"                          # unique job identifier
echo "Name: $SLURM_JOB_NAME"                          # job name (%x)
echo "Node: ${SLURMD_NODENAME:-$SLURM_NODELIST}"      # single node or fallback: compact nodelist
echo "Partition: $SLURM_JOB_PARTITION"                # partition used
echo "start: $(date -Is)"                             # ISO-8601 start time
echo

# --- modules ---

module purge
module load R/latest       # version, e.g., in r session info
# module load R/4.3         # set version explicitly

# --- environment ---

# thread safety: use envar value if it exists, otherwise default: 1
THREADS=${SLURM_CPUS_PER_TASK:-1}

export OMP_NUM_THREADS="$THREADS"
export MKL_NUM_THREADS="$THREADS"
export OPENBLAS_NUM_THREADS="$THREADS"
export NUMEXPR_NUM_THREADS="$THREADS"
export STAN_NUM_THREADS="$THREADS"

# Optional: record environment for reproducibility
env | sort > "$HOME/outgoing/env-${SLURM_JOB_NAME}-${SLURM_JOB_ID}.txt"

# --- run ---

# Put the following on top of the R script:
# outdir <- Sys.getenv("OUTDIR", ".")
# sink(file.path(outdir,
#     sprintf("rsesinfo-%s.txt", Sys.getenv("SLURM_JOB_ID"))))
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

Rscript example.R 

# --- logging (end) ---

echo
echo "end: $(date -Is)"
