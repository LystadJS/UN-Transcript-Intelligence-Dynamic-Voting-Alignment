# Task & purpose: one entry point for manual and Windows scheduled preview runs.
# Run from the project directory: Rscript run.R --date 2026-09-09
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
project_root <- if (length(script_arg)) dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/")) else normalizePath(getwd(), winslash = "/")
if (!file.exists(file.path(project_root, "config/settings.yml"))) stop("Open the UN_Transcript_R project first.", call. = FALSE)
if (file.exists(file.path(project_root, "renv/activate.R"))) source(file.path(project_root, "renv/activate.R"))
required <- c("httr2", "jsonlite", "digest", "dplyr", "tibble", "stringr", "stringi", "readr", "yaml", "htmltools", "filelock", "DBI")
missing <- required[!vapply(required, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) stop("Run source('setup.R') first. Missing: ", paste(missing, collapse = ", "), call. = FALSE)
for (file in sort(list.files(file.path(project_root, "R"), "\\.R$", full.names = TRUE))) source(file)

run_cli <- function(args) {
  config_path <- "config/settings.yml"; day <- NULL; days <- NULL; no_db <- FALSE
  i <- 1L
  while (i <= length(args)) {
    flag <- args[i]
    if (flag == "--help") {
      cat("Usage: Rscript run.R [--date YYYY-MM-DD | --days N] [--config config/settings.yml] [--no-db]\nDefault: previous 3 days in America/New_York; email preview only.\n")
      return(invisible(NULL))
    }
    if (flag == "--no-db") { no_db <- TRUE; i <- i + 1L; next }
    assert(flag %in% c("--date", "--days", "--config") && i < length(args), paste("Unknown/incomplete option:", flag))
    value <- args[i + 1L]
    if (flag == "--date") day <- validate_day(value)
    if (flag == "--days") { days <- suppressWarnings(as.integer(value)); assert(grepl("^[0-9]+$", value) && !is.na(days) && days >= 1 && days <= 90, "--days must be 1..90.") }
    if (flag == "--config") config_path <- value
    i <- i + 2L
  }
  assert(is.null(day) || is.null(days), "Use --date or --days, not both.")
  config <- read_config(project_root, config_path)
  if (no_db) { config$storage$duckdb <- FALSE; config$storage$parquet <- FALSE }
  if (is.null(day)) {
    last_day <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = config$timezone)) - as.integer(!config$include_today)
    dates <- as.character(seq(last_day, by = "-1 day", length.out = days %||% config$lookback_days))
  } else dates <- day
  result <- run_pipeline(project_root, config, dates)
  print(result[c("status", "run_id", "run_directory", "preview", "counts", "errors", "email_sent")])
  if (!identical(result$status, "COMPLETE")) stop("Partial collection. Inspect manifest.json and the preview coverage table.", call. = FALSE)
  invisible(result)
}

if (sys.nframe() == 0L) run_cli(commandArgs(trailingOnly = TRUE))
