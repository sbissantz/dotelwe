#!/usr/bin/env bash

#SBATCH --job-name=combitask
#SBATCH --time=00:03:00
#SBATCH --mem=100M
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --open-mode=append
#SBATCH --signal=B:USR1@5
#SBATCH --output=jobs/%j/bootstrap.stdout.log
#SBATCH --error=jobs/%j/bootstrap.stderr.log
#SBATCH --mail-type=END
# optional
#SBATCH --array=1-2

set -eEuo pipefail

# ==============================================================================
# user config
# ==============================================================================
PROJECT_NAME="combitask"

# specify directories that live in the project root
INPUT_DIRS=(
  "R"    # R scripts
  "stan" # stan model syntax
  "data" # datasets
)

# payload entrypoint (relative to PROJECT_ROOT)
ENTRYPOINT=("R/combitask.R") # only one entrypoint supported

# payload prefix (partial); "${PROJECT_ROOT}/${ENTRYPOINT[0]}" appended below
# note: this is an array:
#   PAYLOAD_PREFIX=("srun" "Rscript" "--vanilla")
# only one command supported
PAYLOAD_PREFIX=(srun --kill-on-bad-exit=1 Rscript --vanilla)

# environment modules to load (in order)
MODULES=(
  "R/4.4"
  # "gcc/12.2.0"
)

# snapshot: if non-empty, saves a copy once per job (relative to PROJECT_ROOT)
SNAPSHOT_ITEMS=(
  # "combitask.sh"  # script file (optional; execution code saved anyway)
  "R"              # important: don't use "dir/", use "dir"
  "stan"           # directory
  # "config/settings.yaml" # file
)

# threading policy (script-owned)
NUM_THREADS=1

# ==============================================================================
# helper functions
# ==============================================================================
log() { printf '[%s] %-5s %s\n' "$(date -Is)" "${1}" "${*:2}"; }
die() { log ERROR "$*"; exit 2; }
log_export(){ for name in "$@"; do log INFO "export: ${name}=${!name-}"; done; }

# ==============================================================================
log STEP "initialize infrastructure"
# ==============================================================================
[[ -n "${SLURM_SUBMIT_DIR:-}" ]] || die "SLURM_SUBMIT_DIR not set"

PROJECT_ROOT="${SLURM_SUBMIT_DIR}"
JOB_DIR="${PROJECT_ROOT}/jobs"

# determine job/task identity (array optional)
if [[ -n "${SLURM_ARRAY_JOB_ID:-}" && -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  JOB_ID="${SLURM_ARRAY_JOB_ID}"
  TASK_ID="${SLURM_ARRAY_TASK_ID}"
else
  [[ -n "${SLURM_JOB_ID:-}" ]] || die "SLURM_JOB_ID not set"
  JOB_ID="${SLURM_JOB_ID}"
  TASK_ID="0"
fi

JOB_ROOT="${JOB_DIR}/${JOB_ID}"
RUN_DIR="${JOB_ROOT}/a${TASK_ID}"

# per job
JOB_PROVENANCE_DIR="${JOB_ROOT}/provenance"
JOB_SNAPSHOT_DIR="${JOB_ROOT}/snapshots"

# per task
TASK_PROVENANCE_DIR="${RUN_DIR}/provenance"
RESULT_DIR="${RUN_DIR}/results"

mkdir -p \
  "${RUN_DIR}" \
  "${JOB_PROVENANCE_DIR}" \
  "${JOB_SNAPSHOT_DIR}" \
  "${TASK_PROVENANCE_DIR}" \
  "${RESULT_DIR}"

# convenience link: jobs/lastjob to jobs/<JOB_ID>
ln -sfn "$(basename "${JOB_ROOT}")" "${JOB_DIR}/lastjob"

# switch to run directory (so relative outputs are per-task by default)
cd "${RUN_DIR}"

# ------------------------------------------------------------------------------
# provenance files
# ------------------------------------------------------------------------------
PLATFORM_FILE="${JOB_PROVENANCE_DIR}/platform.txt"   # once per job
JOB_FILE="${JOB_PROVENANCE_DIR}/job.txt"             # ... 
SUBMIT_FILE="${JOB_PROVENANCE_DIR}/script.sh"        # ... 

TASK_FILE="${TASK_PROVENANCE_DIR}/task.txt"          # per task
RUN_FILE="${TASK_PROVENANCE_DIR}/run.txt"            # ... 
ENV_FILE="${TASK_PROVENANCE_DIR}/env.txt"            # ... 

STATUS_FILE="${RUN_DIR}/STATUS"

# lock to ensure files are written once per job (even with arrays)
JOB_LOCK="${JOB_PROVENANCE_DIR}/.written"

# finish payload command (note: [first] entrypoint at [0])
PAYLOAD_CMD=("${PAYLOAD_PREFIX[@]}")
PAYLOAD_CMD+=("${PROJECT_ROOT}/${ENTRYPOINT[0]}")

log INFO "JOB_ID=${JOB_ID}"
log INFO "TASK_ID=${TASK_ID}"
log INFO "RUN_DIR=${RUN_DIR}"

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
  if [[ $rc -eq 0 ]]; then
    set_final_status "OK"
    log INFO "status: OK"
  else
    set_final_status "FAILED"
    log ERROR "status: FAILED (exit code ${rc})"
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
export JOB_ID TASK_ID
# task directories (payload-owned)
export RUN_DIR RESULT_DIR
# task-level provenance (payload-owned)
export PROVENANCE_DIR="${TASK_PROVENANCE_DIR}"

# threading policy (often; 1)
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

# input dir: envars exported as <DIR>_DIR 
INPUT_VARS=()
for d in "${INPUT_DIRS[@]}"; do
  base="${d^^}"
  var="${base//[^A-Z0-9_]/_}_DIR"
  INPUT_VARS+=("${var}")
  export "${var}=${PROJECT_ROOT}/${d}"
done

log_export JOB_ID TASK_ID RUN_DIR RESULT_DIR PROVENANCE_DIR
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
log STEP "capture execution code + snapshots (once per job)"
# ==============================================================================
if ( set -o noclobber; : >"${JOB_LOCK}" ) 2>/dev/null; then
  # save the exact submitted script once per job
  rsync -a --quiet -- "$0" "${SUBMIT_FILE}" \
    || log WARN "snapshot: failed to save execution code"

  log STEP "snapshot specified items (once per job)"
  for item in "${SNAPSHOT_ITEMS[@]}"; do
    rsync -a --quiet -- "${PROJECT_ROOT}/${item}" "${JOB_SNAPSHOT_DIR}/" \
      || log WARN "snapshot: failed for item: ${item}"
  done

  # ==============================================================================
  log STEP "capture job-level provenance (once per job)"
  # ==============================================================================
  # --- platform.txt: where it ran (job-level) ---
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

  # --- job.txt: what Slurm did (job-level) ---
  {
    echo "Time: $(date -Is)"
    if command -v scontrol >/dev/null 2>&1; then
      # In arrays, this typically describes the array master.
      scontrol show job "${JOB_ID}"
    else
      env | grep '^SLURM_' | sort || true
    fi
  } >"${JOB_FILE}"
fi

# ==============================================================================
log STEP "capture task-level provenance"
# ==============================================================================
# --- task.txt: what Slurm did (task-level) ---
{
  if command -v scontrol >/dev/null 2>&1; then
    # SLURM_JOB_ID is the concrete task job id in arrays; use it when available.
    if [[ -n "${SLURM_JOB_ID:-}" ]]; then
      scontrol show job "${SLURM_JOB_ID}"
    else
      scontrol show job "${JOB_ID}"
    fi
  else
    env | grep '^SLURM_' | sort || true
  fi
} >"${TASK_FILE}"

# --- run.txt: what you ran (per task) ---
{
  echo "Start time: $(date -Is)"
  echo "Project name: ${PROJECT_NAME}"
  echo "Job ID: ${JOB_ID}"
  echo "Task ID: ${TASK_ID}"
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
  echo "Run directory: ${RUN_DIR}"
} >"${RUN_FILE}"

# --- env.txt: effective runtime environment (per task) ---
{
  if command -v module >/dev/null 2>&1; then
    module -t list 2>&1
  else
    echo "(modules not available)"
  fi
  echo
  echo "Environment variables:"
  env | grep -E '^(SLURM_|OMP_|MKL_|OPENBLAS_|NUMEXPR_|STAN_|TASK_ID=|JOB_ID=|PATH=|LANG=|LC_|TZ=)' | sort || true
} >"${ENV_FILE}"

# ------------------------------------------------------------------------------
log STEP "redirect logs to per-task files"
log STEP "redirect logs to per-task files" >&2
# ------------------------------------------------------------------------------
# save original stdout/stderr (bootstrap logs) to print a final message there.
exec 3>&1 4>&2
# from now on: write to per-task logs only.
exec >"${RUN_DIR}/stdout.log" 2>"${RUN_DIR}/stderr.log"

log INFO "logging redirected; run-local execution begins"

# ==============================================================================
log STEP "execute payload"
# ==============================================================================
SECONDS=0

"${PAYLOAD_CMD[@]}"

# bring it home: finish message to bootstrap stdout 
printf '[%s] %-5s %s\n' "$(date -Is)" INFO \
  "finish payload (${SECONDS}s); task=${TASK_ID}; logs in ${RUN_DIR}" >&3

