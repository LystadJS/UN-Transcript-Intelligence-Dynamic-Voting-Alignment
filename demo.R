# Task & purpose: replay the included real UN responses without contacting the UN.
# Run in the project: source("demo.R"). No email is sent.
demo_arg <- grep("^--file=", commandArgs(), value = TRUE)
demo_root <- if (length(demo_arg)) dirname(normalizePath(sub("^--file=", "", demo_arg[1]), winslash = "/")) else getwd()
source(file.path(demo_root, "run.R"))
config <- read_config(project_root)
config$output_root <- "output/demo"
archive <- file.path(project_root, "examples/archive")
reference <- read_json(file.path(archive, "manifest.json"))
requests <- Filter(function(x) identical(x$status, "HTTP_SUCCESS"), reference$requests)
replay_fetcher <- function(url) {
  matches <- Filter(function(x) identical(x$url, url), requests)
  assert(length(matches) == 1, paste("No unique archived response for", url))
  r <- matches[[1]]
  bytes <- read_bytes(file.path(archive, r$path))
  assert(identical(sha_bytes(bytes), r$sha256), "Archived demonstration source hash mismatch.")
  bytes
}
demo_result <- run_pipeline(project_root, config, "2026-09-09", replay_fetcher)
print(demo_result[c("status", "run_directory", "preview", "counts", "errors", "email_sent")])
if (!identical(demo_result$status, "COMPLETE")) stop("Demo incomplete; inspect its manifest.json.")
if (interactive()) browseURL(demo_result$preview)
