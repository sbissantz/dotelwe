## ============================================================================
## onetask.R - r entrypoint for slurm job execution
##
## invoked by `onetask.sh`. consumes environment variables exported by slurm,
## configures runtime constants, snapshots session info, and runs payload code. 
## ============================================================================

# =============================================================================
# initialize general helper functions
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

# =============================================================================
log("STEP", "fetch environment variables")
# =============================================================================
# fetched as character first, then explicitly coerced.

# character-valued (paths, identifiers)
env_chr <- list(
  data_dir = "DATA_DIR",
  stan_dir = "STAN_DIR",
  result_dir = "RESULT_DIR",
  provenance_dir = "PROVENANCE_DIR"
)

## integer-valued (resources, topology)
env_int <- list(
  n_nodes           = "SLURM_JOB_NUM_NODES",    # number of nodes (often: 1)
  n_tasks_per_node  = "SLURM_NTASKS_PER_NODE",  # number of tasks (processes) per node (often: 1)
  n_cpus_per_task   = "SLURM_CPUS_PER_TASK",    # number of CPUs (cores) per task
  threads_per_chain = "STAN_NUM_THREADS"        # number of threads per chain
)

# R var names (R truth): data_dir, stan_dir...
chr_nms <- names(env_chr)
int_nms <- names(env_int)

# env var names (interface truth): DATA_DIR, STAN_DIR...
envars_chr <- unname(env_chr)
envars_int <- unname(env_int)

# raw environment audit (debug)
for (k in c(envars_chr, envars_int)) {
  log("INFO", sprintf("fetch: %s=%s", k, Sys.getenv(k)))
}

# -----------------------------------------------------------------------------
# build environment scaffold
# -----------------------------------------------------------------------------

env <- c( as.list(vapply(env_chr, Sys.getenv, FUN.VALUE = character(1))), 
         as.list(vapply(env_int, Sys.getenv, FUN.VALUE = character(1))))

# missingness check
stopifnot(all(nzchar(unlist(env))))

# -----------------------------------------------------------------------------
# type coercion
# -----------------------------------------------------------------------------

# explicitly coerce integer-valued variables
env[int_nms] <- lapply(env[int_nms], as.integer)

# coercion check
stopifnot(!anyNA(unlist(env[int_nms])))

# -----------------------------------------------------------------------------
# derived quantities
# -----------------------------------------------------------------------------

env <- within(env, {
  process_id <- Sys.getpid()
  n_tasks <- n_nodes * n_tasks_per_node
  n_chains <- n_cpus_per_task
  parallel_chains <- n_chains
  threads_per_task <- threads_per_chain
})
env_nms <- names(env)

# -----------------------------------------------------------------------------
# materialize environment
# -----------------------------------------------------------------------------

# dark magic! from here on, treat imported env vars as read-only constants.
list2env(env, envir = environment())

for (nm in env_nms) {
  log("INFO", sprintf("runtime: %s=%s", nm, get(nm)))
}

# =============================================================================
log("STEP", "snapshot session info")
# =============================================================================

writeLines(
  capture.output(utils::sessionInfo()),
  file.path(provenance_dir, "rsessioninfo.txt")
)

# =============================================================================
log("STEP", "load libraries")
# =============================================================================

pkgs <- c("posterior", "cmdstanr")
lapply(pkgs, library, character.only = TRUE)

# =============================================================================
log("STEP", "start analysis")
# =============================================================================

### --- input(s) ---

#inputs <- c("bfi_jk25a.rda", "Qarr_bfi_jk25a.rda")
#lapply(file.path(data_dir, inputs), load)

## input constraints (resolve later) 

## 1. run model with 100 persons
#bfi <- as.matrix(bfi_jk25a[1:100, ])

## 2. complete case analysis
#cc_pat <- complete.cases(bfi) 
#bficc <- bfi[cc_pat, ]
#bfi <- bficc

### --- derived quantities ---

## q-array
#Qarr <- Qarr_bfi_jk25a

## number of respondents
#P <- nrow(bfi)

## number of items
#I <- ncol(bfi)

## number & labels of dimensions
#D <- dim(Qarr)[2] 

## domain specifics 
#ID <- c(8, 8, 9, 7, 10) 
#dmn_nms <- dimnames(Qarr)$dmn
#names(ID) <- dmn_nms 

## number & labels of modifications
#M <- dim(Qarr)[3] - 1

## number of items dropped per domain 
#n_drop <- 4

## unique strategies
#origmod_nms <- dimnames(Qarr)$mod
#mod_nms <- dimnames(Qarr)$mod[-1]
## number & labels of strategies
#strgy_nms <- c("ao", "ag", "lo", "lg")
#S <- length(strgy_nms)

## hyperparameters 

## important: we need successive integers from 1 to highest number
#C <- 5 # number of response categories

## item threshold hyperparameters
#Thr_mean <- replicate(C - 1, rep(0, I)) # 42 x 4
#THR_cov <- array(0, dim = c(I, C-1, C-1)) # 42 x 4 x 4
#for(d in seq_len(I)) {
  #THR_cov[d , ,] <- diag(1000, C - 1)
#}

## item discrimination/factor loading hyperparameters
#lambda_mean <- rep(0, I)
#Lambda_cov <- diag(1000, I)

## Latent trait hyperparameters
#Theta_mean <- rep(0, D)

### --- stan list ---

#stanls_md2polsi <- list(
  #"P" = P,
  #"I" = I,
  #"C" = C,
  #"D" = D,
  #"Q" = Qarr[,, "orig"],
  ## Important transpose (array in stan are in row major order)
  #"Y" = t(bfi),
  #"thr_mean" = Thr_mean,
  #"Thr_cov" = THR_cov,
  #"lambda_mean" = lambda_mean,
  #"Lambda_cov" = Lambda_cov,
  #"theta_mean" = Theta_mean
#)

### --- model fitting ---

## compile model
#mdl_md2polsi <- cmdstanr::cmdstan_model(
  #file.path(stan_dir, "md2pol_si_cholesky.stan"),
  #pedantic = TRUE
#)

## initialization values
#lambda_init <- rnorm(I, mean = 5, sd = 1)
#sum_scores <- as.matrix(bfi) %*% Qarr[,, "orig"]
#theta_init <- scale(sum_scores)

## run the model
#fit_md2polsi <- mdl_md2polsi$sample( 
  #data = stanls_md2polsi,
  #seed = 112,
  #chains = n_chains,
  #parallel_chains = parallel_chains,
  #threads_per_chain = threads_per_chain,
  ##iter_warmup = 3000,
  #iter_warmup = 100,
  ##iter_sampling = 2000,
  #iter_sampling = 100,
  ## Mean should be below 10, since the log of it is too large
  #init = function() list("lambda" = lambda_init, "theta" = theta_init))

### --- output(s) ---

#outputs <- file.path(result_dir, "fit_md2polsi.rds")
#fit_md2polsi$save_object(outputs)

#cat("Save fit to:", outputs, "\n")
#cat("Done.\n")

## reload
## library(cmdstanr)
## fit_md2polsi <- readRDS("fit_md2polsi.rds")

# =============================================================================
log("STEP", "===== close R session =====")
# =============================================================================
