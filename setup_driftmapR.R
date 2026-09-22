# Run after setup.R in the project. Uses the bundled, hash-verified prototype.
if (!file.exists("UN_Transcript_R.Rproj")) stop("Open the UN_Transcript_R project first.")
if (file.exists("renv/activate.R")) source("renv/activate.R")
if (!requireNamespace("digest", quietly = TRUE)) stop("Run setup.R first.")
archive <- "vendor/driftmapR_0.0.5.9000.tar.gz"
expected <- "a18461c14015dbddee5e4e8ca800c6fbf6b152f418a71c233b139c826965b3bb"
if (!file.exists(archive) || !identical(digest::digest(file = archive, algo = "sha256"), expected)) stop("Bundled driftmapR archive is missing or changed.")
deps <- c("ggplot2", "clue")
missing <- deps[!vapply(deps, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
if ("driftmapR" %in% loadedNamespaces()) stop("Restart R before installing the pinned driftmapR prototype.")
install.packages(archive, repos = NULL, type = "source")
stopifnot(as.character(utils::packageVersion("driftmapR")) == "0.0.5.9000")
if (file.exists("renv/activate.R")) renv::snapshot(prompt = FALSE)
message("driftmapR prototype installed. Run source('demo_drift.R'). No mail is sent.")
