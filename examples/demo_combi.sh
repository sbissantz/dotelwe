#!/usr/bin/env bash
#
# Slurm wrapper: readable, robust, low-maintenance
#
# Goals:
# - Works for array + non-array jobs
# - Stable job directory:           jobs/<JOB_ID>/
# - Array task run directory:       jobs/<JOB_ID>/a<TASK_ID>/
# - Slurm logs are bootstrap only:  jobs/%A/{stdout.log,stderr.log}
# - Real logs live in RUN_DIR:      <RUN_DIR>/{stdout.log,stderr.log}
# - Snapshots (optional): copy R/ and stan/ into <RUN_DIR>/snapshots only if non-empty
# - Duration: SECONDS (reset after redirect)
#
# IMPORTANT (Slurm output paths):
# Slurm opens --output/--error very early. Ensure the submit directory contains a
# "jobs/" directory before sbatch on clusters that don’t auto-create nested paths.

#SBATCH --job-name=srb
#SBATCH --time=00:01:00
#SBATCH --mem=1M
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --hint=nomultithread
#SBATCH --mail-type=END
#SBATCH --signal=B:USR1@5

#SBATCH --output=jobs/%A/stdout.log
#SBATCH --error=jobs/%A/stderr.log

## Optional:
##SBATCH --array=1-2

# ==============================================================================
# opertation mode: strict 
# ==============================================================================

set -eEuo pipefail

# ==============================================================================
# user parameters 
# ==============================================================================

PROJECT_NAME="demo_combi"
R_FILE="demo_combi.R"
R_VERSION="4.4"
# STAN_MODEL="foobar"

# Export what downstream programs may read (e.g. R via Sys.getenv()).
export PROJECT_NAME R_VERSION STAN_MODEL

# ==============================================================================
# helper functions
# ==============================================================================
 
# ISO 8601 timestamps, 
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }

# STATUS updated when RUNNING
#
# RUNNING  ──▶  OK
#    │
#    ├──▶  FAILED
#    ├──▶  TIMEOUT
#    └──▶  KILLED
#
set_final_status() {
  local new="$1"
  local cur
  cur="$(cat "$STATUS_FILE" 2>/dev/null || true)"
  [[ "$cur" == "RUNNING" ]] && echo "$new" > "$STATUS_FILE"
}

# near walltime warning (from --signal=B:USR1@...)
on_timeout() {
  set_final_status "TIMEOUT"
  log "STATUS=TIMEOUT (USR1: nearing walltime)"
  exit 99
}

# external termination (scancel, Ctrl-C)
on_kill() {
  set_final_status "KILLED"
  log "STATUS=KILLED (termination signal)"
  exit 143
}

# unexpected error (triggered by set -eE)
on_err() {
  set_final_status "FAILED"
  log "STATUS=FAILED (line ${LINENO}: ${BASH_COMMAND})"
}

# clean exit (only if nothing else happened)
on_exit() {
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    set_final_status "OK"
    log "STATUS=OK"
  fi
}

# ==============================================================================
# execution mode (sourced vs executed)
# ==============================================================================

# bash detail:
# - BASH_SOURCE[0] is the file being sourced
# - $0 is the script being executed
# If they differ, we are being sourced (interactive/debug), so we skip payload.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  SOURCED=1
  log "mode: sourced (payload disabled)"
else
  SOURCED=0
  log "mode: executed "
fi

# ==============================================================================
# Slurm vs debug mode
# ==============================================================================

# bash detail:
# - -z checks for empty string
# - ${VAR:-} expands to empty if VAR is unset (needed with set -u)
if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  SLURM_JOB_ID="debug_$(date +%Y%m%d-%H%M%S)"
  export SLURM_JOB_ID
  log "debug: running outside Slurm (SLURM_JOB_ID=${SLURM_JOB_ID})"
fi

# ==============================================================================
# project root and standard paths
# ==============================================================================

PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$PWD}"
# TODO: fallback message

JOB_DIR="${PROJECT_ROOT}/jobs"

DATA_DIR="${PROJECT_ROOT}/data"
R_DIR="${PROJECT_ROOT}/R"        
STAN_DIR="${PROJECT_ROOT}/stan"  

export PROJECT_ROOT JOB_DIR DATA_DIR

# export: only if non-empty (string check; usually non-empty).
[[ -n "${R_DIR}" ]] && export R_DIR
[[ -n "${STAN_DIR}" ]] && export STAN_DIR

# Create core dirs used by the job itself.
mkdir -p "${JOB_DIR}" "${DATA_DIR}"

log "paths: PROJECT_ROOT=${PROJECT_ROOT}"
log "paths: JOB_DIR=${JOB_DIR}"

# ==============================================================================
# job identity (array vs non-array)
# ==============================================================================

# SLURM_ARRAY_TASK_ID weird default for non-array tasks
if [[ -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  JOB_ID="${SLURM_ARRAY_JOB_ID}"       # stable id shared by all tasks
  TASK_ID="${SLURM_ARRAY_TASK_ID}"     # this task index
  log "slurm: array job (JOB_ID=${JOB_ID}, TASK_ID=${TASK_ID})"
else
  JOB_ID="${SLURM_JOB_ID}"
  TASK_ID="0"
  log "slurm: non-array job (JOB_ID=${JOB_ID})"
fi

export JOB_ID TASK_ID

# ==============================================================================
#  directory layout (JOB_ROOT and RUN_DIR)
# ==============================================================================

JOB_ROOT="${JOB_DIR}/${JOB_ID}"

# RUN_DIR is where *this run* writes everything:
# - arrays: jobs/<JOB_ID>/a<TASK_ID>/
# - non-arrays: jobs/<JOB_ID>/
if [[ "${TASK_ID}" != "0" ]]; then
  RUN_DIR="${JOB_ROOT}/a${TASK_ID}"
else
  RUN_DIR="${JOB_ROOT}"
fi

RESULT_DIR="${RUN_DIR}/results"
SNAPSHOT_DIR="${RUN_DIR}/snapshots"

export JOB_ROOT RUN_DIR RESULT_DIR SNAPSHOT_DIR

mkdir -p "${RUN_DIR}" "${RESULT_DIR}" "${SNAPSHOT_DIR}"

# ==============================================================================
# STATUS + traps (machine-readable outcome + early timeout handling)
# ==============================================================================

STATUS_FILE="${RUN_DIR}/STATUS"
echo "RUNNING" > "${STATUS_FILE}"

trap on_timeout USR1
trap on_kill TERM INT
trap on_err ERR
trap on_exit EXIT

# ==============================================================================
# symlink 
# ==============================================================================

# Convenience: jobs/lastjob -> jobs/<JOB_ID>
ln -sfn "$(basename "${JOB_ROOT}")" "${JOB_DIR}/lastjob"

# TODO: Why here?
log "dirs: JOB_ROOT=${JOB_ROOT}"
log "dirs: RUN_DIR=${RUN_DIR}"

# ==============================================================================
# 7) Bootstrap logs -> real logs
# ==============================================================================

# These lines go to Slurm bootstrap logs (jobs/%A/...) and tell you where the real logs are.
echo "redirect: stdout to ${RUN_DIR}/stdout.log"
echo "redirect: stderr to ${RUN_DIR}/stderr.log" >&2

# After this point, logs are per-run (array-safe, no interleaving).
exec >"${RUN_DIR}/stdout.log" 2>"${RUN_DIR}/stderr.log"
cd "${RUN_DIR}"

# measure *run time* from here onward.
SECONDS=0

log "logging redirected; run-local execution begins"

# ==============================================================================
# snapshots (only if directories exist and are non-empty)
# ==============================================================================

# snapshot R/ only if it exists & has contents
if [[ -d "${R_DIR}" ]] && [[ -n "$(ls -A "${R_DIR}" 2>/dev/null || true)" ]]; then
  log "snapshot: copying R/ to snapshots/"
  cp -a "${R_DIR}" "${SNAPSHOT_DIR}/"
else
  log "snapshot: skipping R/ (missing or empty)"
fi

# snapshot stan/: if it exists & has contents
if [[ -d "${STAN_DIR}" ]] && [[ -n "$(ls -A "${STAN_DIR}" 2>/dev/null || true)" ]]; then
  log "snapshot: copying stan/ to snapshots/"
  cp -a "${STAN_DIR}" "${SNAPSHOT_DIR}/"
else
  log "snapshot: skipping stan/ (missing or empty)"
fi

# ==============================================================================
# minimal run record (start-of-run)
# ==============================================================================

{
  echo "PROJECT_NAME=${PROJECT_NAME}"
  echo "SCRIPT=${BASH_SOURCE[0]}"
  echo "START_TIME=$(date -Is)"
  echo "PROJECT_ROOT=${PROJECT_ROOT}"
  echo "JOB_ID=${JOB_ID}"
  echo "TASK_ID=${TASK_ID}"
  echo "JOB_ROOT=${JOB_ROOT}"
  echo "RUN_DIR=${RUN_DIR}"
  echo "R_DIR=${R_DIR}"
  echo "STAN_DIR=${STAN_DIR}"
  echo "HOST=${HOSTNAME:-}"
  echo "KERNEL=$(uname -srm)"
  echo
  echo "# --- SLURM (selected) ---"
  echo "SLURM_JOB_ID=${SLURM_JOB_ID:-}"
  echo "SLURM_ARRAY_JOB_ID=${SLURM_ARRAY_JOB_ID:-}"
  echo "SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID:-}"
  echo "SLURM_JOB_PARTITION=${SLURM_JOB_PARTITION:-}"
} > record.txt

log "record: wrote record.txt"

# ==============================================================================
# threading policy 
# ==============================================================================

NUM_THREADS="${NUM_THREADS:-1}"

export NUM_THREADS
export OMP_NUM_THREADS="${NUM_THREADS}"
export MKL_NUM_THREADS="${NUM_THREADS}"
export OPENBLAS_NUM_THREADS="${NUM_THREADS}"
export NUMEXPR_NUM_THREADS="${NUM_THREADS}"

log "threads: policy is NUM_THREADS=${NUM_THREADS}"

# ==============================================================================
# modules 
# ==============================================================================

# TODO: ?

# guard: some environments don’t have module system available.
if [[ "${SOURCED}" -eq 0 ]]; then
  if [[ "$(type -t module || true)" == "function" || "$(type -t module || true)" == "file" ]]; then
    log "modules: purge"
    module purge
    log "modules: load R/${R_VERSION}"
    module load "R/${R_VERSION}"
  else
    log "modules: not available (assuming Rscript is on PATH)"
  fi
fi

# ==============================================================================
# payload (aka. actual work)
# ==============================================================================

if [[ "${SOURCED}" -eq 0 ]]; then
  log "payload: start"

  # fail loudly and early: if entrypoint is missing (strict mode stops job).
  [[ -f "${R_DIR}/${R_FILE}" ]]

  srun Rscript "${R_DIR}/${R_FILE}"

  log "payload: done"
else
  log "payload: skipped (sourced mode)"
fi

# ==============================================================================
# end-of-run record + duration
# ==============================================================================

{
  echo
  echo "END_TIME=$(date -Is)"
  echo "DURATION_SECONDS=${SECONDS}"
} >> record.txt

log "finished (duration ${SECONDS}s)"

