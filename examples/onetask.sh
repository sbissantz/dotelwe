#!/usr/bin/env bash

#SBATCH --job-name=onetask
#SBATCH --time=00:03:00
#SBATCH --mem=100M
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --open-mode=append
#SBATCH --signal=B:USR1@5
#SBATCH --output=jobs/%j/stdout.log
#SBATCH --error=jobs/%j/stderr.log
#SBATCH --mail-type=END            

set -eEuo pipefail

# ==============================================================================
# user config 
# ==============================================================================
PROJECT_NAME="demo_onetask"

# specify directories that live in the project root
INPUT_DIRS=(
  "R"    # R scripts
  "stan" # stan model syntax
  "data" # datasets
) 

# payload entrypoint (relative to PROJECT_ROOT)
ENTRYPOINT=("R/onetask.R") # only one entrypoint supported!

# payload prefix (partial); "${PROJECT_ROOT}/${ENTRYPOINT[0]}" added below
# note that this is a array with three elements:
# PAYLOAD_PREFIX=("srun" "Rscript" "--vanilla") 
PAYLOAD_PREFIX=(srun Rscript --vanilla) # only one command supported

# environment modules to load (in order)
MODULES=(
  "R/4.4"
  # "gcc/12.2.0"
)

# snapshot: if non-empty, saves a copy once per job (relative to PROJECT_ROOT) 
SNAPSHOT_ITEMS=(
  # "onetask.sh"  # script file (optinal: execution code saved)
  "R"           # important: don't use "dir/", use "dir"
  "stan"        # directory
  # "config/settings.yaml"    # file
)

# threading policy (script-owned)
NUM_THREADS=1

# ==============================================================================
# initialize general helper functions 
# ==============================================================================
log() { printf '[%s] %-5s %s\n' "$(date -Is)" "${1}" "${*:2}"; }
die() { log ERROR "$*"; exit 2; }
log_export(){ for name in "$@"; do log INFO "export: ${name}=${!name-}"; done; }

# ==============================================================================
 log STEP "initialize infrastructure"
# ==============================================================================
[[ -n "${SLURM_JOB_ID:-}" ]] || die "SLURM_JOB_ID not set"
[[ -n "${SLURM_SUBMIT_DIR:-}"   ]] || die "SLURM_SUBMIT_DIR not set"
[[ -z "${SLURM_ARRAY_TASK_ID:-}" ]] || die "SLURM_ARRAY_TASK_ID set: array task"

PROJECT_ROOT="${SLURM_SUBMIT_DIR}"
JOB_DIR="${PROJECT_ROOT}/jobs"

JOB_ID="${SLURM_JOB_ID}"

JOB_ROOT="${JOB_DIR}/${JOB_ID}"
RUN_DIR="${JOB_ROOT}"

PROVENANCE_DIR="${JOB_ROOT}/provenance"
SNAPSHOT_DIR="${JOB_ROOT}/snapshots"

RESULT_DIR="${RUN_DIR}/results"

mkdir -p "${RUN_DIR}" "${PROVENANCE_DIR}" "${SNAPSHOT_DIR}" "${RESULT_DIR}"

ln -sfn "$(basename "${JOB_ROOT}")" "${JOB_DIR}/lastjob"

PLATFORM_FILE="${PROVENANCE_DIR}/platform.txt"
JOB_FILE="${PROVENANCE_DIR}/job.txt"
RUN_FILE="${PROVENANCE_DIR}/run.txt"
ENV_FILE="${PROVENANCE_DIR}/env.txt"
SUBMIT_FILE="${PROVENANCE_DIR}/script.sh"

STATUS_FILE="${RUN_DIR}/STATUS"

# finish payload command (note: [first] entrypoint only '[0]')
PAYLOAD_CMD=("${PAYLOAD_PREFIX[@]}")
PAYLOAD_CMD+=("${PROJECT_ROOT}/${ENTRYPOINT[0]}")

# ==============================================================================
log STEP "install status tracking and traps"
# ==============================================================================
echo "RUNNING" > "${STATUS_FILE}"

set_final_status() {
  local new="${1}"
  local cur
  cur="$(cat "${STATUS_FILE}" 2>/dev/null || true)"
  if [[ "${cur}" == "RUNNING" ]]; then
    echo "${new}" > "${STATUS_FILE}"
  fi
}

on_timeout() {
  set_final_status "TIMEOUT"
  log WARN "status: TIMEOUT (USR1: nearing walltime)"
  exit 99
}
on_kill() {
  set_final_status "KILLED"
  log WARN "status: KILLED (termination signal)"
  exit 143
}
on_err() {
  set_final_status "FAILED"
  log ERROR "status: FAILED (line ${LINENO}: ${BASH_COMMAND})"
}
on_exit() {
  local rc=$?
  if [[ ${rc} -eq 0 ]]; then
    set_final_status "OK"
    log INFO "status: OK"
  fi
}

trap on_timeout USR1
trap on_kill TERM INT
trap on_err ERR
trap on_exit EXIT

# ==============================================================================
log STEP "validate input directories"
# ==============================================================================
for d in "${INPUT_DIRS[@]}"; do
  [[ -d "${PROJECT_ROOT}/${d}" ]] || die "missing input dir: ${d}/"
done
[[ -f "${PROJECT_ROOT}/${ENTRYPOINT[0]}" ]] || die "missing entrypoint: ${ENTRYPOINT[0]}"

# ==============================================================================
log STEP "configure runtime environment"
# ==============================================================================
export PROVENANCE_DIR RESULT_DIR RUN_DIR 

# threading policy for all of them (often: THREADS=1)
THREAD_VARS=(
  OMP_NUM_THREADS
  MKL_NUM_THREADS
  OPENBLAS_NUM_THREADS
  NUMEXPR_NUM_THREADS
  STAN_NUM_THREADS
)
for var in "${THREAD_VARS[@]}"; do
  export "${var}=${NUM_THREADS}"
done

# input directories
INPUT_VARS=()
for d in "${INPUT_DIRS[@]}"; do
  base="${d^^}"
  var="${base//[^A-Z0-9_]/_}_DIR"
  INPUT_VARS+=("${var}")
  export "${var}=${PROJECT_ROOT}/${d}"
done

log_export JOB_ID PROVENANCE_DIR RUN_DIR RESULT_DIR 
log_export "${THREAD_VARS[@]}"
log_export "${INPUT_VARS[@]}"

# ==============================================================================
log STEP "load environment modules"
# ==============================================================================
if command -v module >/dev/null 2>&1; then
  module purge
  for m in "${MODULES[@]}"; do
    module load "${m}"
  done
else
  log WARN "module command not available; assuming tools on PATH"
fi

# ==============================================================================
log STEP "capture execution code"
# ==============================================================================
rsync -a -- "$0" "${SUBMIT_FILE}" \
  || log WARN "snapshot: failed to save execution code"

# ==============================================================================
log STEP "snapshot specified items"
# ==============================================================================
for item in "${SNAPSHOT_ITEMS[@]}"; do
  rsync -a -- "${PROJECT_ROOT}/${item}" "${SNAPSHOT_DIR}/" \
    || log WARN "snapshot: failed for item: ${item}"
done

# ==============================================================================
log STEP "capture provenance"
# ==============================================================================

# --- platform.txt: where it ran ---
{
  echo "Time: $(date -Is)"
  echo "Node: $(hostname)"
  echo "Arch: $(uname -m)"
  echo "Kernel: $(uname -srm)"
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "Operating system: ${PRETTY_NAME}"
  fi
} >"${PLATFORM_FILE}"

# --- job.txt: what Slurm did ---
{
  echo "Time: $(date -Is)"
  if command -v scontrol >/dev/null 2>&1; then
    scontrol show job "$JOB_ID"
  else
    env | grep '^SLURM_' | sort || true
  fi
} >"${JOB_FILE}"

# --- run.txt: what you ran (intent + identity) ---
{
  echo "Start time: $(date -Is)"
  echo "Project name: ${PROJECT_NAME}"
  printf 'Entrypoint: '
  printf '%q ' "${ENTRYPOINT[0]}"
  printf '\n'
  printf 'Command: '
  printf '%q ' "${PAYLOAD_CMD[@]}"
  printf '\n'
  echo "Threads: ${NUM_THREADS}"
  ((${#MODULES[@]})) && echo "Requested modules: ${MODULES[*]}"
  echo "Project root: ${PROJECT_ROOT}"
  echo "Job root: ${JOB_ROOT}"
  echo "Run directoy: ${RUN_DIR}"
} >"${RUN_FILE}"

# --- env.txt: effective runtime environment ---
{
  if command -v module >/dev/null 2>&1; then
    module -t list 2>&1
  else
    echo "(modules not available)"
  fi
  echo
  echo "Environment variables:"
  env | grep -E '^(SLURM_|OMP_|MKL_|OPENBLAS_|NUMEXPR_|STAN_|PATH=|LANG=|LC_|TZ=)' | sort || true
} >"${ENV_FILE}"

# ==============================================================================
log STEP "execute payload"
# ==============================================================================
SECONDS=0   # reset: track runtime from here 
"${PAYLOAD_CMD[@]}" # execute payload command(s)
log INFO "finish payload (${SECONDS}s)"
