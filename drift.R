# Rscript drift.R --coordinates positions.csv --evidence evidence.csv --spec model.yml --output output/models/new-model
drift_arg <- grep("^--file=", commandArgs(), value = TRUE)
drift_root <- if (length(drift_arg)) dirname(normalizePath(sub("^--file=", "", drift_arg[1]), winslash = "/")) else getwd()
source(file.path(drift_root, "run.R"))
drift_cli <- function(args) {
  allowed <- c("--coordinates", "--evidence", "--spec", "--output")
  if (identical(args, "--help")) {
    cat("Rscript drift.R --coordinates positions.csv --evidence evidence.csv --spec model.yml --output NEW_DIRECTORY\n")
    return(invisible(NULL))
  }
  assert(length(args) == 8L, "Supply --coordinates, --evidence, --spec and --output. See --help.")
  keys <- args[seq(1, 8, 2)]; values <- args[seq(2, 8, 2)]
  assert(setequal(keys, allowed) && !anyDuplicated(keys), "Unknown or duplicate drift option.")
  paths <- stats::setNames(values, keys)
  result <- build_drift_artifact(paths[["--coordinates"]], paths[["--evidence"]], paths[["--spec"]], paths[["--output"]])
  print(result[c("model_id", "status", "track", "data_kind", "periods", "counts")])
  invisible(result)
}
if (sys.nframe() == 0L) drift_cli(commandArgs(trailingOnly = TRUE))
