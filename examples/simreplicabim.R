## ============================================================================
## simreplicabim.R - r entrypoint for slurm job execution
##
## This script is invoked by the slurm submit script `simreplicabim.sh`.
## it consumes job-specific environment variables exported by slurm and the
## submit script, performs model fitting, and writes all outputs into the
## job directory under: jobs/<JOBID>/
##
## The enclosing job directory is renamed by the Slurm script after completion
## to the form: YYMMDD-HHMM_<JOBID>
## ============================================================================

## --- project name & job id ---

project_name <- Sys.getenv("PROJECT_NAME", "")
job_id <- Sys.getenv("SLURM_JOB_ID", "local")

## --- logging (start) ---

cat("=== Start R session (job:", job_id, ") ===\n")
cat("Time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

## --- (more) environment variables ---

# import path-specific environment variables 
submit_dir <- Sys.getenv("SLURM_SUBMIT_DIR", ".") # project root
data_dir   <- Sys.getenv("DATA_DIR", "")
stan_dir   <- Sys.getenv("STAN_DIR", "")
job_dir   <- Sys.getenv("JOB_DIR", "")

# import job-specifif environment variable
job_dir_id <- Sys.getenv("JOB_DIR_ID", "") 
result_dir <- Sys.getenv("RESULT_DIR", "")
snapshot_dir   <- Sys.getenv("SNAPSHOT_DIR", "")

# import and define computation-specific environment variables

# number of nodes (often: 1)
n_nodes <- as.integer(Sys.getenv("SLURM_JOB_NUM_NODES", "1"))

# number of, say R, processes per node (often: 1)
n_tasks_per_node <- as.integer(Sys.getenv("SLURM_NTASKS_PER_NODE", "1")) 

# slurm language: number of cpus (cores) per task
n_cpus_per_task <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "4"))
# stan language: number of chains (often: 4 & equals n_cpu_per_task)
n_chains <- n_cpus_per_task

# run all chains in parallel
parallel_chains <- n_chains

# stan language: number of threads per chain (often: 1)
threads_per_chain <- as.integer(Sys.getenv("STAN_NUM_THREADS", "1"))
# slurm language: number of threads per task (same concept, different wording)
threads_per_task <- threads_per_chain

## --- R reproducibility snapshot ---

writeLines(
  capture.output(utils::sessionInfo()),
  file.path(snapshot_dir, "rsessioninfo.txt")
)

## --- metadata (stdout.log) ---

cat(
  "=== Runtime metadata ===\n",
  "[Job]\n",
  "  Project:           ", project_name, "\n",
  "  Job ID:            ", job_id, "\n",
  "\n[Resources]\n",
  "  Nodes:             ", n_nodes, "\n",
  "  Tasks per node:    ", n_tasks_per_node, "\n",
  "  CPUs per task:     ", n_cpus_per_task, "\n",
  "  Chains:            ", n_chains, "\n",
  "  Threads per chain: ", threads_per_chain, "\n",
  "  Parallel chains:   ", parallel_chains, "\n",
  "\n[Paths]\n",
  "  JOB_DIR:           ", job_dir, "\n",
  "  JOB_DIR_ID:        ", job_dir_id, "\n",
  "  DATA_DIR:          ", data_dir, "\n",
  "  STAN_DIR:          ", stan_dir, "\n",
  "  RESULT_DIR:        ", result_dir, "\n",
  "  SNAPSHOT_DIR:      ", snapshot_dir, "\n",
  "========================\n\n",
  sep = ""
)

## --- libraries ---

library(posterior)
library(cmdstanr)

## --- input(s) ---

load(file.path(data_dir, "bfi_jk25a.rda"))
load(file.path(data_dir, "Qarr_bfi_jk25a.rda"))

### --- constraints (resolve later) ---

# 1. run model with 100 persons
bfi <- as.matrix(bfi_jk25a[1:100, ])

# 2. complete case analysis
cc_pat <- complete.cases(bfi) 
bficc <- bfi[cc_pat, ]
bfi <- bficc

## --- derived quantities ---

# q-array
Qarr <- Qarr_bfi_jk25a

# number of respondents
P <- nrow(bfi)

# number of items
I <- ncol(bfi)

# number & labels of dimensions
D <- dim(Qarr)[2] 

# domain specifics 
ID <- c(8, 8, 9, 7, 10) 
dmn_nms <- dimnames(Qarr)$dmn
names(ID) <- dmn_nms 

# number & labels of modifications
M <- dim(Qarr)[3] - 1

# number of items dropped per domain 
n_drop <- 4

# unique strategies
origmod_nms <- dimnames(Qarr)$mod
mod_nms <- dimnames(Qarr)$mod[-1]
# number & labels of strategies
strgy_nms <- c("ao", "ag", "lo", "lg")
S <- length(strgy_nms)

# hyperparameters 

# important: we need successive integers from 1 to highest number
C <- 5 # number of response categories

# item threshold hyperparameters
Thr_mean <- replicate(C - 1, rep(0, I)) # 42 x 4
THR_cov <- array(0, dim = c(I, C-1, C-1)) # 42 x 4 x 4
for(d in seq_len(I)) {
  THR_cov[d , ,] <- diag(1000, C - 1)
}

# item discrimination/factor loading hyperparameters
lambda_mean <- rep(0, I)
Lambda_cov <- diag(1000, I)

# Latent trait hyperparameters
Theta_mean <- rep(0, D)

## --- stan list ---

stanls_md2polsi <- list(
  "P" = P,
  "I" = I,
  "C" = C,
  "D" = D,
  "Q" = Qarr_bfi_jk25a[,, "orig"],
  # Important transpose (array in stan are in row major order)
  "Y" = t(bfi),
  "thr_mean" = Thr_mean,
  "Thr_cov" = THR_cov,
  "lambda_mean" = lambda_mean,
  "Lambda_cov" = Lambda_cov,
  "theta_mean" = Theta_mean
)

## --- model fitting ---

# compile model
mdl_md2polsi <- cmdstanr::cmdstan_model(
  file.path(stan_dir, "md2pol_si_cholesky.stan"),
  pedantic = TRUE
)

# initialization values
lambda_init <- rnorm(I, mean = 5, sd = 1)
sum_scores <- as.matrix(bfi) %*% Qarr_bfi_jk25a[,, "orig"]
theta_init <- scale(sum_scores)

# run the model
fit_md2polsi <- mdl_md2polsi$sample( 
  data = stanls_md2polsi,
  seed = 112,
  chains = n_chains,
  parallel_chains = parallel_chains,
  threads_per_chain = threads_per_chain,
  #iter_warmup = 3000,
  iter_warmup = 100,
  #iter_sampling = 2000,
  iter_sampling = 100,
  # Mean should be below 10, since the log of it is too large
  init = function() list("lambda" = lambda_init, "theta" = theta_init))

## --- output(s) ---

out_file <- file.path(result_dir, "fit_md2polsi.rds")
fit_md2polsi$save_object(out_file)

cat("Saved fit to:", out_file, "\n")
cat("Done.\n")

# reload
#library(cmdstanr)
#fit_md2polsi <- readRDS("fit_md2polsi.rds")

## --- logging (end) ---
cat("\n=== End R session (job:", job_id, ") ===\n")
cat("Time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
