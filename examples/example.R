## --- reproducibility snapshot ---

writeLines(
  capture.output(utils::sessionInfo()),
  "sessioninfo.txt"
)

## --- workplace ---

2 + 2

set.seed(123)          

result <- rnorm(10)

## --- output ---
saveRDS(result, file.path("results", "result.rds"))
