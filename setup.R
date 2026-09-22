# Task & purpose: install R dependencies and record the actual local environment.
# In RStudio: open UN_Transcript_R.Rproj, then source("setup.R").
if (!file.exists("UN_Transcript_R.Rproj")) stop("Run setup from the project directory.", call. = FALSE)
if (getRversion() < "4.3.0") stop("Install R 4.3 or later.", call. = FALSE)
options(repos = c(CRAN = "https://cloud.r-project.org"))
packages <- c("httr2", "jsonlite", "digest", "dplyr", "tibble", "stringr", "stringi", "readr",
              "yaml", "htmltools", "filelock", "DBI", "duckdb", "renv", "testthat")
missing <- packages[!vapply(packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) install.packages(missing)
still_missing <- packages[!vapply(packages, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(still_missing)) stop("Installation incomplete: ", paste(still_missing, collapse = ", "), call. = FALSE)
library_sources <- .libPaths()
if (!file.exists("renv/activate.R")) renv::init(bare = TRUE, restart = FALSE)
renv::hydrate(packages = packages, sources = library_sources, prompt = FALSE)
renv::snapshot(packages = packages, prompt = FALSE)
dir.create("output", showWarnings = FALSE)
writeLines(capture.output(sessionInfo()), "output/setup-sessionInfo.txt")
if (.Platform$OS.type == "windows") {
  rscript <- normalizePath(file.path(R.home("bin"), "Rscript.exe"), winslash = "\\", mustWork = TRUE)
  launcher <- c("@echo off", "setlocal", 'pushd "%~dp0"', 'if not exist "output" mkdir "output"',
    paste0('"', rscript, '" "run.R" %* >> "output\\console.log" 2>&1'),
    'set "UN_EXIT_CODE=%ERRORLEVEL%"', "popd", "exit /b %UN_EXIT_CODE%")
  writeLines(launcher, "run-preview.cmd", useBytes = TRUE)
  message("Created run-preview.cmd for double-click or Windows Task Scheduler.")
}
message("Setup complete. Run source('tests/run_tests.R'), then source('run.R'); run_cli(c('--date', '2026-09-09')).")
