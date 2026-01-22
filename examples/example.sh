#!/bin/bash

#SBATCH --job-name=eg              # job name (abbreviated project name)

#SBATCH --time=00:05:00            # format:HH:MM:SS
#SBATCH --mem=1M                   # options: K M G T 
                                   # Tip: add ~10% safety margin

#SBATCH --nodes=1                  # 1 physical node
#SBATCH --ntasks-per-node=1        # 1 task(s) or process(es) / node
#SBATCH --cpus-per-task=1          # 4 CPU core(s) / task 
#SBATCH --hint=nomultithread       # avoid hardware hyper-threading (intel) 
                                   # or smt (amd)

#SBATCH --output=jobs/%j/stdout.log     # %j: <JOBID> 
#SBATCH --error=jobs/%j/stderr.log      # %j: <JOBID> 

#SBATCH --mail-type=END            # options: END, FAIL, ALL

## ============================================================================
## example.sh - a documented example slurm submit script
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


## --- global sanity checks ---

set -eEuo pipefail                 # strict shell mode: fail fast on 
                                   # -e: errors, -E: error trap inheritance
                                   # -u: unset variables, 
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

## --- global shell variables ---

TS_PREFIX="$(date +%y%m%d-%H%M)"      # for renaming and sorting
JOB_STATUS_SUFFIX=""                  # empty "" on success; __DEBUG on failure

## --- helper functions ---

# rename the job directory by adding a time stamp as prefix (easier sorting)
rename_job_dir() {
  # initialize as local variables
  local old_id new_id
  old_id="$SLURM_JOB_ID"
  new_id="${TS_PREFIX}_${SLURM_JOB_ID}${JOB_STATUS_SUFFIX:-}"
  # ensure we are in the right directory; then rename
  cd -- "${JOB_DIR}"
  mv -- "${old_id}" "${new_id}"
}

# puts durations in a human-readable format
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

# --- traps ---

# mark failure on any error as suffix
trap 'JOB_STATUS_SUFFIX="__FAIL"' ERR

# always rename at the end (never fail here)
trap 'rename_job_dir || true' EXIT

# ---job directory setup ---

# note: ${JOB_DIR_ID} is created by slurm with the stdout and stderror files
mkdir -p "${JOB_DIR}" "${RESULT_DIR}" "${SNAPSHOT_DIR}"
cd "${JOB_DIR_ID}"

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
  "Project name: ${PROJECT_NAME}" \
  "Script: ${PROJECT_NAME}.sh" \
  "Start time: $(date '+%Y-%m-%d %H:%M:%S')" \
  "Job ID: ${SLURM_JOB_ID}" \
  "Job name: ${SLURM_JOB_NAME}" \
  "Node: ${SLURMD_NODENAME:-${SLURM_NODELIST}}" \
  "Partition: ${SLURM_JOB_PARTITION}" \
  ""

## --- modules ---

module purge
module load "R/${R_VERSION}"

## --- run ---

#srun Rscript "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}.R"

echo "hello world"; sleep 2

## --- global shell variables (again) --

# compute duration from bash builtin SECONDS (seconds since shell start)
DURATION_SEC=$SECONDS
DURATION_FMT=$(format_duration "$DURATION_SEC")
echo "Duration: $DURATION_FMT"

# --- logging (end) ---

printf '%s\n' \ 
  "" \
  "End time: $(date '+%Y-%m-%d %H:%M:%S')" \
  "Duration: ${DURATION_FMT}"
