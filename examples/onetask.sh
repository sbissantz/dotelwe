#!/usr/bin/env bash
#SBATCH --job-name=onetask
#SBATCH --time=00:03:00
#SBATCH --mem=100M
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --open-mode=append
#SBATCH --signal=B:USR1@5
#SBATCH --mail-type=END
#SBATCH --output=jobs/%j/bootstrap.stdout.log
#SBATCH --error=jobs/%j/bootstrap.stderr.log

set -eEuo pipefail

# ==============================================================================
# user config
# ==============================================================================

PROJECT_NAME="demo_onetask"
INPUT_DIRS=( R stan data )
ENTRYPOINT=("R/onetask.R") # only one entrypoint supported
PAYLOAD_PREFIX=( srun Rscript --vanilla )
MODULES=( "R/4.4" )
SNAPSHOT_ITEMS=( R stan )
NUM_THREADS=1

# ==============================================================================
# logging (bootstrap + payload separation)
# ==============================================================================
# default bootstrap file descriptors to stdout/stderr so early blog_* calls
# never fail; later reassigned to log files
BOOTSTRAP_FD_OUT=1
BOOTSTRAP_FD_ERR=2

# ==============================================================================
# helper functions
# ==============================================================================
_blog_post() {
  local fd="$1"; shift
  local level="$1"; shift
  local msg="${*//$'\r'/}"
  printf '[%s] %-5s | %s\n' "$(date -Is)" "$level" "$msg" >&"${fd}"
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
[[ -n "${SLURM_JOB_ID:-}" ]] || blog_die "SLURM_JOB_ID not set"
[[ -n "${SLURM_SUBMIT_DIR:-}" ]] || blog_die "SLURM_SUBMIT_DIR not set"
[[ -z "${SLURM_ARRAY_TASK_ID:-}" ]] || blog_die "SLURM_ARRAY_TASK_ID set"

PROJECT_ROOT="${SLURM_SUBMIT_DIR}"
JOB_ID="${SLURM_JOB_ID}"

JOB_DIR="${PROJECT_ROOT}/jobs"
JOB_ROOT="${JOB_DIR}/${JOB_ID}"

RUN_DIR="${JOB_ROOT}"
RESULT_DIR="${RUN_DIR}/results"
PROVENANCE_DIR="${RUN_DIR}/provenance"
SNAPSHOT_DIR="${RUN_DIR}/snapshots"

mkdir -p \
  "${RUN_DIR}" \
  "${SNAPSHOT_DIR}" \
  "${PROVENANCE_DIR}" \
  "${RESULT_DIR}"
# convenience symlink: jobs/lastjob to jobs/<JOB_ID>
ln -sfn "$(basename "${JOB_ROOT}")" "${JOB_DIR}/lastjob"

# bootstrap/payload logs in job dir
BOOTSTRAP_STDOUT="${RUN_DIR}/bootstrap.stdout.log"
BOOTSTRAP_STDERR="${RUN_DIR}/bootstrap.stderr.log"
PAYLOAD_STDOUT="${RUN_DIR}/payload.stdout.log"
PAYLOAD_STDERR="${RUN_DIR}/payload.stderr.log"

exec 8>>"${BOOTSTRAP_STDOUT}"
exec 9>>"${BOOTSTRAP_STDERR}"
BOOTSTRAP_FD_OUT=8
BOOTSTRAP_FD_ERR=9

STATUS_FILE="${RUN_DIR}/STATUS"
PLATFORM_FILE="${PROVENANCE_DIR}/platform.txt"
JOB_FILE="${PROVENANCE_DIR}/job.txt"
RUN_FILE="${PROVENANCE_DIR}/run.txt"
ENV_FILE="${PROVENANCE_DIR}/env.txt"
SUBMIT_FILE="${PROVENANCE_DIR}/script.sh"

PAYLOAD_CMD=("${PAYLOAD_PREFIX[@]}")
PAYLOAD_CMD+=("${PROJECT_ROOT}/${ENTRYPOINT[0]}")

blog_info "JOB_ID=${JOB_ID}"
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
blog_step "validate inputs"
# ==============================================================================
for d in "${INPUT_DIRS[@]}"; do
  [[ -d "${PROJECT_ROOT}/${d}" ]] || blog_die "missing input dir: ${d}/"
done
[[ -f "${PROJECT_ROOT}/${ENTRYPOINT[0]}" ]] || blog_die "missing entrypoint: ${ENTRYPOINT[0]}"

# ==============================================================================
blog_step "configure runtime environment"
# ==============================================================================
export RUN_DIR RESULT_DIR PROVENANCE_DIR JOB_ID

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

blog_export JOB_ID RUN_DIR RESULT_DIR PROVENANCE_DIR
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
blog_step "capture execution code and snapshots"
# ==============================================================================
rsync -a --quiet -- "$0" "${SUBMIT_FILE}" \
  || blog_warn "snapshot: failed to save execution code"

for item in "${SNAPSHOT_ITEMS[@]}"; do
  rsync -a --quiet -- \
    "${PROJECT_ROOT}/${item}" \
    "${SNAPSHOT_DIR}/" \
    || blog_warn "snapshot: failed for item: ${item}"
done

# ==============================================================================
blog_step "capture provenance"
# ==============================================================================
{
  echo "Time: $(date -Is)"
  echo "Node: $(hostname)"
  echo "Arch: $(uname -m)"
  echo "Kernel: $(uname -srm)" 
  if [[ -r /etc/os-release ]]; then 
    . /etc/os-release 
    echo "Distribution: ${PRETTY_NAME}"
  fi
} > "${PLATFORM_FILE}"

{
  echo "Time: $(date -Is)"
  if command -v scontrol >/dev/null 2>&1; then
    scontrol show job "${JOB_ID}"
  else
    env | grep '^SLURM_' | sort || true
  fi
} > "${JOB_FILE}"

{
  echo "Start time: $(date -Is)"
  echo "Project name: ${PROJECT_NAME}"
  printf 'Entrypoint: %q\n' "${ENTRYPOINT[0]}"
  printf 'Command: '; printf '%q ' "${PAYLOAD_CMD[@]}"; echo
  echo "Threads: ${NUM_THREADS}"
  ((${#MODULES[@]})) && echo "Requested modules: ${MODULES[*]}"
  echo "Project root: ${PROJECT_ROOT}"
  echo "Job root: ${JOB_ROOT}"
  echo "Run directory: ${RUN_DIR}"
} >"${RUN_FILE}"

{
  if command -v module >/dev/null 2>&1; then
    module -t list 2>&1
  else
    echo "(modules not available)"
  fi
  echo
  echo "Environment variables:"
  env | grep -E \
    '^(SLURM_|OMP_|MKL_|OPENBLAS_|NUMEXPR_|STAN_|JOB_ID=|PATH=|LANG=|LC_|TZ=)' \
    | sort \
    || true

} > "${ENV_FILE}"

# ==============================================================================
blog_step "redirect logs to payload files"
# ==============================================================================
blog_info "payload stdout: ${PAYLOAD_STDOUT}"
blog_info "payload stderr: ${PAYLOAD_STDERR}"

# ==============================================================================
blog_step "execute payload"
# ==============================================================================
SECONDS=0

blog_info "payload cmd: $(printf '%q ' "${PAYLOAD_CMD[@]}")"

cd "${RUN_DIR}"

(
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


