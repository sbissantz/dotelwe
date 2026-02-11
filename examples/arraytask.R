## ============================================================================
## arraytask.R - r entrypoint for slurm job execution
##
## invoked by `arraytask.sh`. consumes environment variables exported by slurm,
## configures runtime constants, snapshots session info, and runs payload code. 
## ============================================================================

# =============================================================================
# helper logging (unchanged)
# =============================================================================
log <- function(level, ..., sep = " ", file = stdout()) {
  t <- proc.time()[["elapsed"]]
  if (t < 60) {
    ts <- sprintf("%.1fs", t)
  } else if (t < 3600) {
    ts <- sprintf("%.1fm", t / 60)
  } else {
    ts <- sprintf("%.2fh", t / 3600)
  }
  cat(sprintf("[+%s] %-5s %s\n", ts, level, paste(..., sep = sep)), file = file)
}

# =============================================================================
log("STEP", "====== start R session (array task) ======")
# =============================================================================

# =============================================================================
log("STEP", "fetch environment variables")
# =============================================================================
# fetched as character first, then explicitly coerced.

# character-valued (paths, identifiers)
env_chr <- list(
  data_dir       = "DATA_DIR",
  stan_dir       = "STAN_DIR",
  result_dir     = "RESULT_DIR",
  provenance_dir = "PROVENANCE_DIR",  # <-- task-level provenance
  run_dir        = "RUN_DIR"
)

# integer-valued (resources + identity)
env_int <- list(
  n_nodes           = "SLURM_JOB_NUM_NODES",
  n_tasks_per_node  = "SLURM_NTASKS_PER_NODE",
  n_cpus_per_task   = "SLURM_CPUS_PER_TASK",
  threads_per_chain = "STAN_NUM_THREADS",

  array_job_id  = "SLURM_ARRAY_JOB_ID",
  array_task_id = "SLURM_ARRAY_TASK_ID"
)

chr_nms <- names(env_chr)
int_nms <- names(env_int)

envars_chr <- unname(env_chr)
envars_int <- unname(env_int)

# raw audit (debug trace)
for (k in c(envars_chr, envars_int)) {
  log("INFO", sprintf("fetch: %s=%s", k, Sys.getenv(k)))
}

# -----------------------------------------------------------------------------
# build environment scaffold
# -----------------------------------------------------------------------------
env <- c(
  as.list(vapply(env_chr, Sys.getenv, FUN.VALUE = character(1))),
  as.list(vapply(env_int, Sys.getenv, FUN.VALUE = character(1)))
)

# strict missingness check (same philosophy as onetask.R)
stopifnot(all(nzchar(unlist(env))))

# -----------------------------------------------------------------------------
# type coercion
# -----------------------------------------------------------------------------
env[int_nms] <- lapply(env[int_nms], as.integer)
stopifnot(!anyNA(unlist(env[int_nms])))

# -----------------------------------------------------------------------------
# derived quantities (unchanged policy)
# -----------------------------------------------------------------------------
env <- within(env, {
  process_id <- Sys.getpid()

  n_tasks <- n_nodes * n_tasks_per_node
  n_chains <- n_cpus_per_task
  parallel_chains <- n_chains
  threads_per_task <- threads_per_chain

  job_id  <- array_job_id
  task_id <- array_task_id
})

env_nms <- names(env)

# -----------------------------------------------------------------------------
# materialize environment
# -----------------------------------------------------------------------------
# from here on: treat these as read-only runtime constants
list2env(env, envir = environment())

for (nm in env_nms) {
  log("INFO", sprintf("runtime: %s=%s", nm, get(nm)))
}

# =============================================================================
log("STEP", "snapshot session info (task provenance)")
# =============================================================================

writeLines(
  capture.output(utils::sessionInfo()),
  file.path(provenance_dir, "rsessioninfo.txt")
)

# =============================================================================
log("STEP", "load libraries")
# =============================================================================
pkgs <- c("posterior", "cmdstanr")
invisible(lapply(pkgs, library, character.only = TRUE))

# =============================================================================
log("STEP", "start analysis")
# =============================================================================

# ---- task-unique output paths (policy lives here, not filesystem creation) ----
fit_path <- file.path(
  result_dir,
  sprintf("fit_task%03d.rds", task_id)
)

log("INFO", sprintf("output: %s", fit_path))

# ---- your analysis code goes here ----
# Only differences from onetask.R should be:
#   - use task_id where needed
#   - ensure filenames include task_id
#   - optionally map task_id -> model/data variant

# =============================================================================
log("STEP", "===== close R session (array task) =====")
# =============================================================================
