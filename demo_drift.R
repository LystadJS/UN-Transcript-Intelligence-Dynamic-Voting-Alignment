# Offline real transcript replay with a prominently labeled synthetic model map.
demo_arg <- grep("^--file=", commandArgs(), value = TRUE)
demo_root <- if (length(demo_arg)) dirname(normalizePath(sub("^--file=", "", demo_arg[1]), winslash = "/")) else getwd()
source(file.path(demo_root, "run.R"))
source(file.path(demo_root, "examples/make_drift_fixture.R"))
config <- read_config(project_root)
config$output_root <- "output/drift-demo"
config$email$subject_prefix <- "[DEMO] UN Daily Meeting Intelligence"
tag <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_", basename(tempfile()))
fixture_dir <- file.path(project_root, config$output_root, paste0("inputs-", tag))
paths <- write_drift_fixture(fixture_dir)
model_dir <- file.path(project_root, config$output_root, paste0("model-", tag))
model <- build_drift_artifact(paths$coordinates, paths$evidence, paths$spec, model_dir)
config$models$statements$artifact_dir <- normalizePath(model_dir, winslash = "/")
config$models$statements$allow_synthetic <- TRUE
archive <- file.path(project_root, "examples/archive")
requests <- Filter(function(x) identical(x$status, "HTTP_SUCCESS"), read_json(file.path(archive, "manifest.json"))$requests)
replay <- function(url) {
  matches <- Filter(function(x) identical(x$url, url), requests)
  assert(length(matches) == 1L, "Archived source not found uniquely.")
  r <- matches[[1]]; bytes <- read_bytes(file.path(archive, r$path))
  assert(identical(sha_bytes(bytes), r$sha256), "Archived source hash mismatch.")
  bytes
}
result <- run_pipeline(project_root, config, "2026-09-09", replay)
assert(identical(result$status, "COMPLETE"), "Replay incomplete.")
assert(identical(result$manifest$email$model_status$statements, "DESCRIPTIVE"), "Synthetic map did not render; inspect model-status.json.")
print(result[c("status", "run_directory", "preview", "counts", "email_sent")])
message("Synthetic model only. No real opinion-change estimate and no email sent.")
if (interactive()) browseURL(result$preview)
