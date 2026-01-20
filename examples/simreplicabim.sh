#!/bin/bash

## ============================================================================
## simreplicabim.sh - slurm submit script
##
## creates a per-job directory under jobs/<JOBID> so Slurm logs land inside it,
## snapshots the exact code/model used, runs the r entrypoint, then renames the
## job directory to YYMMDD-HHMM_JOBID.
## ============================================================================

## --- required variables ---

# set these two variables, 
export PROJECT_NAME="simreplicabim"   # set name explicitly!

# TODO
export R_VERSION=4.4                  # set version explicitly!

## --- project structure ---

# ~/projects/{PROJECT_NAME}/
# |├── {PROJECT_NAME}.sh             # submit entrypoint
# |├── {PROJECT_NAME}.R              # r entrypoint 
# |├── README.md    
# |├── .gitignore
# |├── data/                         # input data 
# |├── stan
# |   |├── stanmodel.stan            # stan source
# |   |└── stanmodel                 # stan compiled
# |├── jobs/                         # job-specific dirs
# |   |└── {TS}_{SLURM_JOB_ID/}     
# |       |├── stdout.log            # slurm stdout
# |       |├── stderr.log            # slurm stderr
# |       |├── snapshots/            # snapshot(s) of code and models
# |       |│   ├── env.txt           # compute environment snapshot
# |       |│   ├── rsessioninfo.txt  
# |       |│   ├── projectname.sh
# |       |│   ├── projectname.R
# |       |│   └── stanmodel.stan     
# |       |└── results/              # model outputs only
# |           └── fit_stanmodel.rds
#
# Important:  data/, jobs/, and stan/ are part of the project structure and 
# must exist before you submit! (see: project-level checks > sanity check)

## --- slurm specifics ---

#SBATCH --job-name=srb             # job name (abbreviated project name)

#SBATCH --time=02:30:00            # format:HH:MM:SS
#SBATCH --mem=16GB                 # options: K M G T 
                                   # Tip: add ~10% safety margin

#SBATCH --nodes=1                  # 1 physical node
#SBATCH --ntasks-per-node=1        # 1 task(s) or processe(s) / node
#SBATCH --cpus-per-task=4          # 4 CPU core(s) / task 
#SBATCH --hint=nomultithread       # avoid hardware hyper-threading (intel) 
                                   # or smt (amd)

#SBATCH --output=jobs/%j/stdout.log     # %j: <JOBID> 
#SBATCH --error=jobs/%j/stderr.log      # %j: <JOBID> 

#SBATCH --mail-type=END            # options: END, FAIL, ALL
                            
## --- global sanity checks ---

set -euo pipefail                  # strict shell mode: fail fast on 
                                   # -e: errors, -u: unset variables, 
                                   # -o pipefail: broken pipeline

## --- project-level checks ---

# sanity check: data/, stan/, jobs/ must exist before you submit
for d in data stan jobs; do
  [ -d "${SLURM_SUBMIT_DIR}/$d" ] || { echo "Missing required directory: $d"; exit 1; }
done

## --- environment variables ---

# create and export required structural directories and environment variables
export DATA_DIR="${SLURM_SUBMIT_DIR}/data"
export STAN_DIR="${SLURM_SUBMIT_DIR}/stan"
export JOB_DIR="${SLURM_SUBMIT_DIR}/jobs/"   

# create and export job-specific directories and environment variables
export JOB_DIR_ID="${JOB_DIR}/${SLURM_JOB_ID}"   # job-specific   
export RESULT_DIR="${JOB_DIR_ID}/results"           # job-specific
export SNAPSHOT_DIR="${JOB_DIR_ID}/snapshots"       # job-specific 

# threading policy: 1 thread / task (avoid oversubscription) 
export NUM_THREADS=1

# create and export all thread-related environment variables
export STAN_NUM_THREADS="${NUM_THREADS}"
export OMP_NUM_THREADS="${NUM_THREADS}"
export MKL_NUM_THREADS="${NUM_THREADS}"
export OPENBLAS_NUM_THREADS="${NUM_THREADS}"
export NUMEXPR_NUM_THREADS="${NUM_THREADS}"

# ---job directory setup ---

mkdir -p "${JOB_DIR_ID}" "${RESULT_DIR}" "${SNAPSHOT_DIR}"
cd "${JOB_DIR_ID}"

## --- environment reproducibility snapshot ---

# record all environment variables
env | sort > "${SNAPSHOT_DIR}/env.txt"

## --- file reproducibility snapshot ---

# snapshot exact code and stan sources used for this job
cp -f "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}.sh" "${SNAPSHOT_DIR}/" || true
cp -f "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}.R"  "${SNAPSHOT_DIR}/" || true
cp -f "${STAN_DIR}"/*.stan "${SNAPSHOT_DIR}/" || true

## --- logging (start) ---

echo "Start: $(date -Is)"
echo
echo "Project name: ${PROJECT_NAME}"
echo "Job name: ${SLURM_JOB_NAME}"
echo "Job ID: ${SLURM_JOB_ID}"
echo "Node: ${SLURMD_NODENAME:-$SLURM_NODELIST}"
echo "Partition: ${SLURM_JOB_PARTITION}"
echo "JOB_DIR_ID: ${JOB_DIR_ID}"
echo "RESULT_DIR: ${RESULT_DIR}"
echo

## --- modules ---

module purge
module load R/${R_VERSION}

## --- run ---

srun Rscript "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}.R"

## --- finalize: rename job directory ---

# rename jobs/<JOBID> to jobs/<YYMMDD-HHMM_JOBID> for sorting
TS="$(date +%y%m%d-%H%M)"
cd "${SLURM_SUBMIT_DIR}/jobs"

OLD_ID="${SLURM_JOB_ID}"
NEW_ID="${TS}_${SLURM_JOB_ID}"

# avoid failing the whole job if rename is not possible (e.g., name collision).
if [ -d "${OLD_ID}" ] && [ ! -e "${NEW_ID}" ]; then
  mv "${OLD_ID}" "${NEW_ID}"
fi

# --- logging (end) ---

echo
echo "End: $(date -Is)"
