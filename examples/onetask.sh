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
INPUT_DIRS=(R stan data) 

# payload entrypoint (relative to PROJECT_ROOT)
ENTRYPOINT="R/onetask.R"

# environment modules to load (in order)
MODULES=(
  "R/4.4"
  # "gcc/12.2.0"
)

# snapshot: if non-empty, saves a copy once per job (relative to PROJECT_ROOT) 
SNAPSHOT_ITEMS=(
  "R"       # directory
  "stan"    # directory
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
 log STEP "initialize job directories"
# ==============================================================================
[[ -n "${SLURM_JOB_ID:-}" ]] || die "SLURM_JOB_ID not set"
[[ -n "${SLURM_SUBMIT_DIR:-}" ]] || die "SLURM_SUBMIT_DIR not set"
[[ -z "${SLURM_ARRAY_TASK_ID:-}" ]] || die "array task detected"

PROJECT_ROOT="${SLURM_SUBMIT_DIR}"
JOB_DIR="${PROJECT_ROOT}/jobs"

JOB_ID="${SLURM_JOB_ID}"

JOB_ROOT="${JOB_DIR}/${JOB_ID}"
RUN_DIR="${JOB_ROOT}"

JOBINFO_DIR="${JOB_ROOT}/jobinfo"
SNAPSHOT_DIR="${JOB_ROOT}/snapshots"

RUNINFO_DIR="${RUN_DIR}/runinfo"
RESULT_DIR="${RUN_DIR}/results"

mkdir -p "${RUN_DIR}" "${JOBINFO_DIR}" "${SNAPSHOT_DIR}" "${RUNINFO_DIR}" "${RESULT_DIR}"

ln -sfn "$(basename "${JOB_ROOT}")" "${JOB_DIR}/lastjob"

STATUS_FILE="${RUN_DIR}/STATUS"

OS_FILE="${JOBINFO_DIR}/os.txt"
JOB_FILE="${JOBINFO_DIR}/job.txt"
RUN_FILE="${RUNINFO_DIR}/run.txt"
ENV_FILE="${RUNINFO_DIR}/env.txt"

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
[[ -f "${PROJECT_ROOT}/${ENTRYPOINT}" ]] || die "missing entrypoint: ${ENTRYPOINT}"

# ==============================================================================
log STEP "configure runtime environment"
# ==============================================================================
export RUN_DIR RUNINFO_DIR RESULT_DIR

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

log_export RUN_DIR RUNINFO_DIR RESULT_DIR
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
log STEP "snapshot specified items"
# ==============================================================================
for item in "${SNAPSHOT_ITEMS[@]}"; do
  src="${PROJECT_ROOT}/${item}"
  if [[ ! -e "${src}" ]]; then
    # snapshot is best-effort (provenance only); never fails job
    log WARN "snapshot: missing item (skipping): ${item}"
    continue
  fi
  rsync -a -- "${src}/" "${SNAPSHOT_DIR}/${item}/" 2>/dev/null \
    || cp -a -- "${src}" "${SNAPSHOT_DIR}/${item}"
done

# ==============================================================================
log STEP "capture metadata"
# ==============================================================================
{
  # kernel and distro
  uname -srm
  ( . /etc/os-release 2>/dev/null && printf '%s %s\n' "${ID}" "${VERSION_ID}" ) || true
} > "${OS_FILE}"

{
  # job: scheduler view 
  date -Is
  if command -v scontrol >/dev/null 2>&1; then
    scontrol show job "${JOB_ID}"
  else
    echo "(scontrol not available)"
  fi
} > "${JOB_FILE}"

{
  # run-specifics 
  printf 'START_TIME=%s\n' "$(date -Is)"
  printf 'PROJECT_NAME=%s\n' "${PROJECT_NAME}"
  printf 'ENTRYPOINT=%s\n' "${ENTRYPOINT}"
  printf 'NUM_THREADS=%s\n' "${NUM_THREADS}"
  ((${#MODULES[@]})) && printf 'MODULES=%s\n' "${MODULES[*]}"
  printf 'RUN_DIR=%s\n' "${RUN_DIR}"
} > "${RUN_FILE}"

{
  # runtime execution environment
  hostname
  env | grep -E '^(OMP_|MKL_|OPENBLAS_|NUMEXPR_|STAN_)' | sort || true
  echo
  if command -v module >/dev/null 2>&1; then
    module -t list 2>&1
  else
    echo "(modules not available)"
  fi
} > "${ENV_FILE}"

# ==============================================================================
log STEP "execute payload"
# ==============================================================================
SECONDS=0   # reset: track runtime from here 
srun Rscript --vanilla "${PROJECT_ROOT}/${ENTRYPOINT}"
log INFO "finish payload (${SECONDS}s)"
