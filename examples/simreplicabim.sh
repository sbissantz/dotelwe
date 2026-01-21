#!/bin/bash

## ============================================================================
## simreplicabim.sh - slurm submit script
## 
## creates a per-job directory under jobs/<JOBID> so slurm logs land inside it,
## snapshots the exact code/model used, runs the r entrypoint, then renames the
##   - YYMMDD-HHMM_<JOBID>            on success
##   - YYMMDD-HHMM_<JOBID>__DEBUG     on failure
## ============================================================================

## --- required variables ---

# set these two variables explicitly, the rest is taken care of
export PROJECT_NAME="simreplicabim"   
export R_VERSION="4.4"                 

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
# |   |└── {TS_START}_{SLURM_JOB_ID/}     
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
#SBATCH --mem=16G                  # options: K M G T 
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

## --- environment variables ---

# create and export required structural directories and environment variables
export DATA_DIR="${SLURM_SUBMIT_DIR}/data"
export STAN_DIR="${SLURM_SUBMIT_DIR}/stan"
export JOB_DIR="${SLURM_SUBMIT_DIR}/jobs"   

# create and export job-specific directories and environment variables
export JOB_DIR_ID="${JOB_DIR}/${SLURM_JOB_ID}"      # job-specific   
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

# note: ${JOB_DIR_ID} is created by slurm with the stdout and sterror files
mkdir -p "${JOB_DIR}" "${RESULT_DIR}" "${SNAPSHOT_DIR}"
cd "${JOB_DIR_ID}"

## --- timestamps ---

TS_START="$(date +%y%m%d-%H%M)"       # start time for renaming the job 
TS_START_EPOCH="$(date +%s)"          # for duration

SUFFIX=""                           # empty on success; __DEBUG on failure

rename_job_dir() {
  set +e
  cd "${JOB_DIR}" || return 0

  local old_id="${SLURM_JOB_ID}"
  local new_id="${TS_START}_${SLURM_JOB_ID}${SUFFIX}"

  # avoid failing the whole job if rename is not possible (e.g., collision)
  if [ -d "${old_id}" ] && [ ! -e "${new_id}" ]; then
    mv "${old_id}" "${new_id}"    # rename, but ... 
    ln -sfn "${new_id}" latest    # create a symlink "-s" (see: man ln)
  fi
}

# any error, mark debug
trap 'SUFFIX="__DEBUG"' ERR
# always rename on exit (success or failure)
trap rename_job_dir EXIT

## --- reproducibility snapshots ---

# snapshot all environment variables
env | sort > "${SNAPSHOT_DIR}/env.txt"

# snapshot all project files (required; cp fails if missing) 
cp -f "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}".* "${SNAPSHOT_DIR}/"

# snapshot stan files if present (optional)
shopt -s nullglob   # don't fail if there are no stan files
cp -f "${STAN_DIR}"/*.stan "${SNAPSHOT_DIR}/"
shopt -u nullglob

## --- logging (start) ---

printf '%s\n' \
  "Start project: ${PROJECT_NAME}" \
  "Script: ${PROJECT_NAME}.sh" \
  "Start time: $(date '+%Y-%m-%d %H:%M:%S')" \
  "Submit command: $0 $*" \
  "" \
  "Job ID: ${SLURM_JOB_ID}" \
  "Job name: ${SLURM_JOB_NAME}" \
  "Node: ${SLURMD_NODENAME:-${SLURM_NODELIST}}" \
  "Partition: ${SLURM_JOB_PARTITION}" \
  "" \
  "JOB_DIR: ${JOB_DIR_ID}" \
  "RESULT_DIR: ${RESULT_DIR}"

## --- modules ---

module purge
module load "R/${R_VERSION}"

## --- run ---

srun Rscript "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}.R"

# --- timestamps (again) ---

TS_END_EPOCH="$(date +%s)"
DURATION_SEC=$((END_EPOCH - START_EPOCH)) 

format_duration() {
  local s=$1
  local d h m

  d=$((s / 86400))
  h=$(( (s % 86400) / 3600 ))
  m=$(( (s % 3600) / 60 ))
  s=$((s % 60))

  if [ "$d" -gt 0 ]; then
    printf '%dd %02dh %02dm %02ds\n' "$d" "$h" "$m" "$s"
  elif [ "$h" -gt 0 ]; then
    printf '%02dh %02dm %02ds\n' "$h" "$m" "$s"
  else
    printf '%02dm %02ds\n' "$m" "$s"
  fi
}

DURATION_FMT=$(format_duration "$DURATION_SEC")

# --- logging (end) ---

printf '%s\n' \
  "End project: ${PROJECT_NAME}" \
  "End time: $(date '+%Y-%m-%d %H:%M:%S')" \
  "Duration: ${DURATION_FMT}" \
  "" \
  "Final job directory: ${JOB_DIR}/${TS_START}_${SLURM_JOB_ID}${SUFFIX}"

