# Runnable offline checks; no requests and no email delivery.
arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- if (length(arg)) dirname(dirname(normalizePath(sub("^--file=", "", arg[1]), winslash = "/"))) else normalizePath(getwd(), winslash = "/")
if (!file.exists(file.path(root, "UN_Transcript_R.Rproj"))) stop("Run tests from the project root.")
if (file.exists(file.path(root, "renv/activate.R"))) source(file.path(root, "renv/activate.R"))
for (f in sort(list.files(file.path(root, "R"), "\\.R$", full.names = TRUE))) source(f)
UN_TEST_ROOT <- root
source(file.path(root, "tests/helper_pipeline.R"))
test_env <- new.env(parent = globalenv())
testthat::test_file(file.path(root, "tests/test_pipeline.R"), reporter = "summary", env = test_env, stop_on_failure = TRUE)
testthat::test_file(file.path(root, "tests/test_drift_report.R"), reporter = "summary", env = test_env, stop_on_failure = TRUE)
