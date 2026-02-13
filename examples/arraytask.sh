#!/usr/bin/env bash

#SBATCH --job-name=combitask
#SBATCH --time=00:02:00
#SBATCH --mem=200M
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --open-mode=append
#SBATCH --signal=B:USR1@30
#SBATCH --output=jobs/%A/a%a/bootstrap.stdout.log
#SBATCH --error=jobs/%A/a%a/bootstrap.stderr.log
#SBATCH --mail-type=END
#SBATCH --array=1-2
 
set -eEuo pipefail

# default bootstrap file descriptors to stdout/stderr so early blog_* calls
# never fail; later reassigned to log files
BOOTSTRAP_FD_OUT=1
BOOTSTRAP_FD_ERR=2

# ==============================================================================
# user config
# ==============================================================================
PROJECT_NAME="arraytask"

# specify directories that live in the project root
INPUT_DIRS=(
  "R"    # R scripts
  "stan" # stan model syntax
  "data" # datasets
)

# payload entrypoint (relative to PROJECT_ROOT)
ENTRYPOINT=("R/arraytask.R") # only one entrypoint supported

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
_blog_post() {
  local fd="$1"; shift
  local level="$1"; shift
  local msg="${*//$'\r'/}"
  local ts job task id
  ts="$(date -Is)"
  job="${SLURM_ARRAY_JOB_ID}"
  task="${SLURM_ARRAY_TASK_ID}"
  id="${job}.a${task}"
  printf '[%s] %-5s %-10s | %s\n' \
    "$ts" "$level" "$id" "$msg" >&"${fd}"
}
blog_step()  { _blog_post "${BOOTSTRAP_FD_OUT}" STEP  "$@"; }
blog_info()  { _blog_post "${BOOTSTRAP_FD_OUT}" INFO  "$@"; }
blog_warn()  { _blog_post "${BOOTSTRAP_FD_ERR}" WARN  "$@"; }
blog_error() { _blog_post "${BOOTSTRAP_FD_ERR}" ERROR "$@"; }
blog_die() { blog_error "$@"; exit 2; }
blog_export() {
  local name
  for name in "$@"; do
    blog_info "export: ${name}=${!name-}"
  done
}

# ==============================================================================
blog_step "initialize infrastructure"
# ==============================================================================
[[ -n "${SLURM_SUBMIT_DIR:-}" ]] || blog_die "SLURM_SUBMIT_DIR not set"
[[ -n "${SLURM_ARRAY_JOB_ID:-}" ]] || blog_die "SLURM_ARRAY_JOB_ID not set"
[[ -n "${SLURM_ARRAY_TASK_ID:-}" ]] || blog_die "SLURM_ARRAY_TASK_ID not set"

PROJECT_ROOT="${SLURM_SUBMIT_DIR}"
JOB_ID="${SLURM_ARRAY_JOB_ID}"
TASK_ID="${SLURM_ARRAY_TASK_ID}"

JOB_DIR="${PROJECT_ROOT}/jobs"
JOB_ROOT="${JOB_DIR}/${JOB_ID}"

# per job
RUN_DIR="${JOB_ROOT}/a${TASK_ID}"
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

# ------------------------------------------------------------------------------
# provenance files
# ------------------------------------------------------------------------------

# bootstrap/payload logs in job dir
BOOTSTRAP_STDOUT="${RUN_DIR}/bootstrap.stdout.log"
BOOTSTRAP_STDERR="${RUN_DIR}/bootstrap.stderr.log"
PAYLOAD_STDOUT="${RUN_DIR}/payload.stdout.log"
PAYLOAD_STDERR="${RUN_DIR}/payload.stderr.log"

exec 8>>"${BOOTSTRAP_STDOUT}" 
exec 9>>"${BOOTSTRAP_STDERR}" 
BOOTSTRAP_FD_OUT=8
BOOTSTRAP_FD_ERR=9

PLATFORM_FILE="${JOB_PROVENANCE_DIR}/platform.txt"   # once per job
JOB_FILE="${JOB_PROVENANCE_DIR}/job.txt"             # ... 
SUBMIT_FILE="${JOB_PROVENANCE_DIR}/script.sh"        # ... 

RUN_FILE="${TASK_PROVENANCE_DIR}/run.txt"            # per task
ENV_FILE="${TASK_PROVENANCE_DIR}/env.txt"            # ... 

STATUS_FILE="${RUN_DIR}/STATUS"

# lock to ensure files are written once per job (even with arrays)
JOB_LOCK="${JOB_PROVENANCE_DIR}/.written"

# finish payload command (note: [first] entrypoint at [0])
PAYLOAD_CMD=("${PAYLOAD_PREFIX[@]}")
PAYLOAD_CMD+=("${PROJECT_ROOT}/${ENTRYPOINT[0]}")

blog_info "JOB_ID=${JOB_ID}"
blog_info "TASK_ID=${TASK_ID}"
blog_info "RUN_DIR=${RUN_DIR}"

# ==============================================================================
blog_step "install status tracking and traps"
# ==============================================================================
echo "RUNNING" > "${STATUS_FILE}"

set_status() {
  local cur
  cur="$(head -n1 "${STATUS_FILE}" 2>/dev/null || true)"
  [[ "$cur" == "RUNNING" ]] && echo "$1" > "${STATUS_FILE}"
  return 0
}
on_timeout() {
  set_status "TIMEOUT"
  # don't let logging failure change exit behavior
  blog_warn "status: TIMEOUT (USR1: nearing walltime)" || true
  exit 99
}
on_kill() {
  set_status "KILLED"
  blog_warn "status: KILLED (termination signal)" || true
  exit 143
}
on_err() {
  local rc=$?                     # exit code of failing command
  local line="${BASH_LINENO[0]}"  # line where failure occurred 
  local cmd="${BASH_COMMAND}"     # command that failed
  # prevent recursive ERR trap if something here fails
  trap - ERR
  set_status "FAILED"
  blog_error "status: FAILED (rc=${rc}, line=${line}, cmd=${cmd})" || true
  exit "${rc}"
}
on_exit() {
  local rc=$? 
  # read current status (first line)
  local cur="$(head -n1 "${STATUS_FILE}" 2>/dev/null || true)"
  # if still RUNNING (or malformed), finalize based on rc
  if [[ -z "$cur" || "$cur" == "RUNNING" ]]; then
    if (( rc == 0 )); then
      cur="COMPLETED"
    else
      cur="FAILED"
    fi
    echo "$cur" > "${STATUS_FILE}"
  fi
  blog_info "status: ${cur} (exit code ${rc})"
}

trap on_timeout USR1
trap on_kill TERM INT
trap on_err ERR
trap on_exit EXIT

# ==============================================================================
blog_step "validate input directories"
# ==============================================================================
for d in "${INPUT_DIRS[@]}"; do
  [[ -d "${PROJECT_ROOT}/${d}" ]] || blog_die "missing input dir: ${d}/"
done
[[ -f "${PROJECT_ROOT}/${ENTRYPOINT[0]}" ]] || blog_die "missing entrypoint: ${ENTRYPOINT[0]}"

# ==============================================================================
blog_step "configure runtime environment"
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

blog_export JOB_ID TASK_ID RUN_DIR RESULT_DIR PROVENANCE_DIR
blog_export "${THREAD_VARS[@]}"
blog_export "${INPUT_VARS[@]}"

# ==============================================================================
blog_step "load environment modules"
# ==============================================================================
if command -v module >/dev/null 2>&1; then
  module purge
  for m in "${MODULES[@]}"; do
    module load "${m}"
  done
else
  blog_warn "module command not available; assuming tools on PATH"
fi

# ==============================================================================
blog_step "capture execution code"
# ============================================================================== 

if ( set -o noclobber; : >"${JOB_LOCK}" ) 2>/dev/null; then
  # save the exact submitted script once per job
  rsync -a --quiet -- "$0" "${SUBMIT_FILE}" \
    || blog_warn "snapshot: failed to save execution code"

  # ==============================================================================
    blog_step "snapshot specified items"
  # ==============================================================================
  
  for item in "${SNAPSHOT_ITEMS[@]}"; do
    rsync -a --quiet -- "${PROJECT_ROOT}/${item}" "${JOB_SNAPSHOT_DIR}/" \
      || blog_warn "snapshot: failed for item: ${item}"
  done

  # ==============================================================================
  blog_step "capture job-level provenance (once per job)"
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
blog_step "capture task-level provenance"
# ==============================================================================

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

# ==============================================================================
blog_step "redirect logs to per-task files"
# ==============================================================================
blog_info "payload stdout: ${PAYLOAD_STDOUT}"
blog_info "payload stderr: ${PAYLOAD_STDERR}"

# ==============================================================================
blog_step "execute payload"
# ==============================================================================
SECONDS=0

blog_info "payload cmd: $(printf '%q ' "${PAYLOAD_CMD[@]}")"

# switch to run directory (so relative outputs are per-task by default)
cd "${RUN_DIR}"

( # run in a sub-shell
  trap - ERR
  exec >"${PAYLOAD_STDOUT}" 2>"${PAYLOAD_STDERR}"
  "${PAYLOAD_CMD[@]}"
)
rc=$?

if (( rc == 0 )); then
  blog_info "finish payload (${SECONDS}s)"
  exit 0
else
  blog_error "payload failed (rc=${rc})"
  exit "${rc}"
fi
