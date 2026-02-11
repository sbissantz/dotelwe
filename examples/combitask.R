## ============================================================================
## combitask.R - R entrypoint for slurm job execution 
##
## invoked by `combitask.sh`. consumes environment variables exported by slurm,
## configures runtime constants, snapshots session info, and runs payload code. 
## ============================================================================
options(error = function() {
  message("FATAL: unhandled R error")
  traceback(2)
  quit(status = 1, save = "no")
})

# =============================================================================
# helper logging 
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
log("STEP", "====== start R session ======")
# =============================================================================

djalsjdalksdj

# =============================================================================
log("STEP", "fetch environment variables")
# =============================================================================
# fetched as character first, then explicitly coerced 

# character-valued (paths, identifiers)
env_chr <- list(
  data_dir       = "DATA_DIR",
  stan_dir       = "STAN_DIR",
  result_dir     = "RESULT_DIR",
  provenance_dir = "PROVENANCE_DIR",  # <-- task-level provenance
  run_dir        = "RUN_DIR",
  job_id         = "JOB_ID"
)

# integer-valued (resources, identity)
env_int <- list(
  n_nodes           = "SLURM_JOB_NUM_NODES",
  n_tasks_per_node  = "SLURM_NTASKS_PER_NODE",
  n_cpus_per_task   = "SLURM_CPUS_PER_TASK",
  threads_per_chain = "STAN_NUM_THREADS",
  task_id           = "TASK_ID"
)

chr_nms <- names(env_chr)
int_nms <- names(env_int)

envars_chr <- unname(env_chr)
envars_int <- unname(env_int)

# raw audit (debug trace)
for (k in c(envars_chr, envars_int)) {
  log("INFO", sprintf("fetch: %s=%s", k, Sys.getenv(k, unset = "")))
}

# -----------------------------------------------------------------------------
# build environment scaffold
# -----------------------------------------------------------------------------
env <- c(
  as.list(vapply(env_chr, Sys.getenv, FUN.VALUE = character(1), unset = "")),
  as.list(vapply(env_int, Sys.getenv, FUN.VALUE = character(1), unset = ""))
)

# missingness check
stopifnot(!anyNA(unlist(env[int_nms])))

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

  # These can be NA on some systems; keep the policy but allow NA if Slurm didn’t provide.
  n_tasks <- n_nodes * n_tasks_per_node
  n_chains <- n_cpus_per_task
  parallel_chains <- n_chains
  threads_per_task <- threads_per_chain
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
# task-level provenance directory 
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
# Differences between single and array runs should be handled via task_id.
# Example patterns:
#   - map task_id -> dataset shard
#   - map task_id -> parameter grid point
#   - map task_id -> model variant
#
# saveRDS(fit, fit_path)

# =============================================================================
log("STEP", "===== close R session =====")
# =============================================================================

