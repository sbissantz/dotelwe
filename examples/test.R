outdir <- Sys.getenv("OUTDIR", ".")
sink(file.path(outdir,
 sprintf("rsesinfo-%s.txt", Sys.getenv("SLURM_JOB_ID"))))

utils::sessionInfo()

sink()

sink(file.path(outdir,
 sprintf("routput-%s.txt", Sys.getenv("SLURM_JOB_ID"))))

2+2

sink()

