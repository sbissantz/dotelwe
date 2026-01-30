#!/usr/bin/env bash
#
# slurm wrapper: readable, robust, low-maintenance
#
# goals:
# - Works for array + non-array jobs
# - Stable job directory:           jobs/<JOB_ID>/
# - Array task run directory:       jobs/<JOB_ID>/a<TASK_ID>/
# - Slurm logs are bootstrap only:  jobs/%A/{stdout.log,stderr.log}
# - Real logs live in RUN_DIR:      <RUN_DIR>/{stdout.log,stderr.log}
# - Snapshots (optional): copy R/ and stan/ into <RUN_DIR>/snapshots only if non-empty
# - Duration: SECONDS (reset after redirect)
#
# important (Slurm output paths): Slurm opens --output/--error very early.
# Ensure the submit directory contains a "jobs/" directory before sbatch on
# clusters that don’t auto-create nested paths. note.

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

# array: specify pre-defined directories
INPUT_DIRS=(data R stan)

# export: what downstream programs may read (e.g. R via Sys.getenv()).
export PROJECT_NAME R_VERSION 

# ==============================================================================
# helper functions
# ==============================================================================
 
# ISO 8601 timestamps, 
log() {
  # usage: log LEVEL MESSAGE...
  # LEVEL: INFO | WARN | STEP
  # log levels:
  #   STEP  – major phase transitions (e.g. "starting payload")
  #   INFO  – normal progress & decisions (e.g. "input dir OK: data/")
  #   WARN  – non-fatal but noteworthy (e.g. "input directory is empty")
  local level="$1"
  shift
  printf '[%s] %-5s %s\n' "$(date -Is)" "$level" "$*"
}

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

## ==============================================================================
## execution mode: sourced vs executed
## ==============================================================================
log STEP "determining execution mode"

## bash detail:
## - BASH_SOURCE[0] is the file being sourced
## - $0 is the script being executed
## if they differ, we are being sourced (interactive/debug), so we skip payload.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  SOURCED=1
  log INFO "execution mode: sourced (payload disabled)"
else
  SOURCED=0
  log INFO "execution mode: executed (payload enabled)"
fi

## ==============================================================================
## execution environment: slurm vs debug mode
## ==============================================================================
log STEP "determining execution environment"

# bash detail:
# - -z checks for empty string
# - ${VAR:-} expands to empty if VAR is unset (needed with set -u)
if [[ -z "${SLURM_JOB_ID:-}" ]]; then
  SLURM_JOB_ID="debug_$(date +%Y%m%d-%H%M%S)"
  export SLURM_JOB_ID
  log WARN "execution environment: outside slurm; using fallback (SLURM_JOB_ID=${SLURM_JOB_ID})"
else
  log INFO "execution environment: under slurm (SLURM_JOB_ID=${SLURM_JOB_ID})"
fi

## ==============================================================================
## infrastructure: project root & standard paths
## ==============================================================================

##--- project root ---
log STEP "determining project root"

if [[ -n "${SLURM_SUBMIT_DIR:-}" ]]; then
  PROJECT_ROOT="${SLURM_SUBMIT_DIR}"
  log INFO "project root: using SLURM_SUBMIT_DIR (${PROJECT_ROOT})"
else
  PROJECT_ROOT="${PWD}"
  log WARN "project root: SLURM_SUBMIT_DIR not set; using PWD (${PROJECT_ROOT})"
fi

export PROJECT_ROOT

## --- input directories ---
log STEP "checking input directories"

for d in "${INPUT_DIRS[@]}"; do
  dir="${PROJECT_ROOT}/${d}"

  # hard error: directory must exist
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: missing input directory: $dir" >&2
    exit 2
  fi

  # soft warning: directory exists but is empty
  if [[ -z "$(ls -A "$dir" 2>/dev/null || true)" ]]; then
    log WARN "input directory is empty: ${d}/"
  else
    log INFO "input directory OK: ${d}/"
  fi
done

## --- job directory --- ##
log STEP "exporting input directories"

for d in "${INPUT_DIRS[@]}"; do
  var_name="$(printf '%s_DIR' "$d" | tr '[:lower:]' '[:upper:]')"
  var_value="${PROJECT_ROOT}/${d}"

  export "${var_name}=${var_value}"
  log INFO "export: ${var_name}=${var_value}"
done

## --- job directory --- ##
log STEP "initializing job directory"

JOB_DIR="${PROJECT_ROOT}/jobs"
mkdir -p "${JOB_DIR}"

# TODO: Do I need to export?
export JOB_DIR
log INFO "export: JOB_DIR (${JOB_DIR})"

## ==============================================================================
## job id(entitiy): array vs non-array
## ==============================================================================

log STEP "determining job identity (array vs non-array)"

if [[ -n "${SLURM_ARRAY_JOB_ID:-}" && -n "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  JOB_ID="${SLURM_ARRAY_JOB_ID}"
  TASK_ID="${SLURM_ARRAY_TASK_ID}"
  log INFO "job identity: array (JOB_ID=${JOB_ID}, TASK_ID=${TASK_ID})"
else
  JOB_ID="${SLURM_JOB_ID}"
  TASK_ID="0"
  log INFO "job identity: non-array (JOB_ID=${JOB_ID})"
fi

export JOB_ID TASK_ID

## ==============================================================================
##  directory layout: JOB_ROOT & RUN_DIR
## ==============================================================================

#JOB_ROOT="${JOB_DIR}/${JOB_ID}"

## RUN_DIR is where *this run* writes everything:
## - arrays: jobs/<JOB_ID>/a<TASK_ID>/
## - non-arrays: jobs/<JOB_ID>/
#if [[ "${TASK_ID}" != "0" ]]; then
  #RUN_DIR="${JOB_ROOT}/a${TASK_ID}"
#else
  #RUN_DIR="${JOB_ROOT}"
#fi

#RESULT_DIR="${RUN_DIR}/results"
#SNAPSHOT_DIR="${RUN_DIR}/snapshots"

#export JOB_ROOT RUN_DIR RESULT_DIR SNAPSHOT_DIR

#mkdir -p "${RUN_DIR}" "${RESULT_DIR}" "${SNAPSHOT_DIR}"

## ==============================================================================
## status & traps 
## ==============================================================================

## (machine-readable outcome + early timeout handling)
#STATUS_FILE="${RUN_DIR}/STATUS"
#echo "RUNNING" > "${STATUS_FILE}"

#trap on_timeout USR1
#trap on_kill TERM INT
#trap on_err ERR
#trap on_exit EXIT

## ==============================================================================
## symlink 
## ==============================================================================

## Convenience: jobs/lastjob -> jobs/<JOB_ID>
#ln -sfn "$(basename "${JOB_ROOT}")" "${JOB_DIR}/lastjob"

## TODO: Why here?
#log "dirs: JOB_ROOT=${JOB_ROOT}"
#log "dirs: RUN_DIR=${RUN_DIR}"

## ==============================================================================
## log files: central vs. run-specific 
## ==============================================================================

## These lines go to Slurm bootstrap logs (jobs/%A/...) and tell you where the real logs are.
## TODO: No log()?
#echo "redirect: stdout to ${RUN_DIR}/stdout.log"
#echo "redirect: stderr to ${RUN_DIR}/stderr.log" >&2

## After this point, logs are per-run (array-safe, no interleaving).
#exec >"${RUN_DIR}/stdout.log" 2>"${RUN_DIR}/stderr.log"
#cd "${RUN_DIR}"

#log "setup: ok"
#log "logging redirected; run-local execution begins"

## ==============================================================================
## snapshots: reproducibility
## ==============================================================================

#log "snapshot: checking source directories"

#log STEP "snapshotting input directories"

#for d in "${INPUT_DIRS[@]}"; do
  #src="${PROJECT_ROOT}/${d}"

  #if [[ -d "$src" ]] && [[ -n "$(ls -A "$src" 2>/dev/null || true)" ]]; then
    #log INFO "snapshot: ${d}/ to snapshots/"
    #cp -a "$src" "${SNAPSHOT_DIR}/"
  #else
    #log INFO "snapshot: skipping ${d}/ (missing or empty)"
  #fi
#done

## ==============================================================================
## run record (minimal)
## ==============================================================================

#{
  #echo "PROJECT_NAME=${PROJECT_NAME}"
  #echo "SCRIPT=${BASH_SOURCE[0]}"
  #echo "START_TIME=$(date -Is)"
  #echo "PROJECT_ROOT=${PROJECT_ROOT}"
  #echo "JOB_ID=${JOB_ID}"
  #echo "TASK_ID=${TASK_ID}"
  #echo "JOB_ROOT=${JOB_ROOT}"
  #echo "RUN_DIR=${RUN_DIR}"
  #echo "R_DIR=${R_DIR}"
  #echo "STAN_DIR=${STAN_DIR}"
  #echo "HOST=${HOSTNAME:-}"
  #echo "KERNEL=$(uname -srm)"
  #echo
  #echo "# --- SLURM (selected) ---"
  #echo "SLURM_JOB_ID=${SLURM_JOB_ID:-}"
  #echo "SLURM_ARRAY_JOB_ID=${SLURM_ARRAY_JOB_ID:-}"
  #echo "SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID:-}"
  #echo "SLURM_JOB_PARTITION=${SLURM_JOB_PARTITION:-}"
#} > record.txt

#log "record: wrote record.txt"

## ==============================================================================
## threading policy 
## ==============================================================================

#NUM_THREADS="${NUM_THREADS:-1}"
## TODO: information message

#export NUM_THREADS
#export OMP_NUM_THREADS="${NUM_THREADS}"
#export MKL_NUM_THREADS="${NUM_THREADS}"
#export OPENBLAS_NUM_THREADS="${NUM_THREADS}"
#export NUMEXPR_NUM_THREADS="${NUM_THREADS}"

#log "threads: policy is NUM_THREADS=${NUM_THREADS}"

## ==============================================================================
## modules 
## ==============================================================================

## measure run time from here onward.
#SECONDS=0

## TODO: ?

## guard: some environments don’t have module system available.
#if [[ "${SOURCED}" -eq 0 ]]; then
  #if [[ "$(type -t module || true)" == "function" || "$(type -t module || true)" == "file" ]]; then
    #log "modules: purge"
    #module purge
    #log "modules: load R/${R_VERSION}"
    #module load "R/${R_VERSION}"
  #else
    #log "modules: not available (assuming Rscript is on PATH)"
  #fi
#fi

## ==============================================================================
## payload (aka. actual work)
## ==============================================================================

#if [[ "${SOURCED}" -eq 0 ]]; then
  #log "payload: start"

  ## fail loudly and early: if entrypoint is missing (strict mode stops job).
  #[[ -f "${R_DIR}/${R_FILE}" ]]

  #srun Rscript "${R_DIR}/${R_FILE}"

  #log "payload: done"
#else
  #log "payload: skipped (sourced mode)"
#fi

## ==============================================================================
## end-of-run record + duration
## ==============================================================================

#{
  #echo
  #echo "END_TIME=$(date -Is)"
  #echo "DURATION_SECONDS=${SECONDS}"
#} >> record.txt

#log "finished (duration ${SECONDS}s)"

