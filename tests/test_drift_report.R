source(file.path(UN_TEST_ROOT, "examples/make_drift_fixture.R"), local = TRUE)
drift_case <- function(track = "statements") {
  directory <- tempfile("drift-test-"); dir.create(directory)
  paths <- write_drift_fixture(file.path(directory, "inputs"), track)
  list(directory = directory, paths = paths, output = file.path(directory, "model"))
}
build_case <- function(case) build_drift_artifact(case$paths$coordinates, case$paths$evidence, case$paths$spec, case$output)
require_drift <- function() {
  testthat::skip_if_not_installed("driftmapR")
  testthat::expect_identical(as.character(utils::packageVersion("driftmapR")), drift_supported_version)
}

testthat::test_that("artifact paths recognize Windows drives and UNC paths", {
  for (path in c("C:/Users/John/My Models", "C:\\Users\\John\\My Models", "\\\\server\\share\\models", "/tmp/models")) {
    testthat::expect_identical(resolve_model_dir("project", path), path)
  }
  testthat::expect_identical(resolve_model_dir("project", "models/topic"), file.path("project", "models/topic"))
})

testthat::test_that("briefing preserves empty, partial and all-topic outcomes", {
  cfg <- test_config(); on.exit(unlink(file.path(UN_TEST_ROOT, cfg$output_root), recursive = TRUE))
  r <- run_pipeline(UN_TEST_ROOT, cfg, fixture()$day, fixture_fetcher(fixture()))
  html <- rawToChar(read_bytes(r$preview))
  for (title in c("Selected transcript excerpts", "U.S. Mission Relevance", "Cross-Meeting Developments", "Meeting Summaries", "Position and Voting Updates", "Coverage and QA")) {
    testthat::expect_true(grepl(title, html, fixed = TRUE))
  }
  testthat::expect_true(file.exists(r$manifest$email$full_report))
  testthat::expect_identical(unlist(r$manifest$email$model_status), c(statements = "UNAVAILABLE", votes = "UNAVAILABLE"))
})
testthat::test_that("source text cannot replace layout tokens or inject HTML", {
  cfg <- test_config(); on.exit(unlink(file.path(UN_TEST_ROOT, cfg$output_root), recursive = TRUE))
  f <- fixture("We support {{MODEL_PANELS}} and {{FULL_REPORT}} <script>bad()</script> as literal transcript text.")
  r <- run_pipeline(UN_TEST_ROOT, cfg, f$day, fixture_fetcher(f))
  html <- rawToChar(read_bytes(r$preview))
  testthat::expect_true(grepl("{{MODEL_PANELS}}", html, fixed = TRUE))
  testthat::expect_false(grepl("<script>", html, fixed = TRUE))
  testthat::expect_true(grepl("No model artifact configured.", html, fixed = TRUE))
})
testthat::test_that("unavailable and failed models do not break collection", {
  cfg <- test_config(); cfg$models$statements$artifact_dir <- "missing-model-directory"
  on.exit(unlink(file.path(UN_TEST_ROOT, cfg$output_root), recursive = TRUE))
  r <- suppressWarnings(run_pipeline(UN_TEST_ROOT, cfg, fixture()$day, fixture_fetcher(fixture())))
  testthat::expect_identical(r$status, "COMPLETE")
  testthat::expect_identical(r$manifest$email$model_status$statements, "FAILED")
})
testthat::test_that("input checks reject duplicates, gaps, nonfinite values and broken evidence", {
  case <- drift_case(); on.exit(unlink(case$directory, recursive = TRUE))
  p <- readr::read_csv(case$paths$coordinates, show_col_types = FALSE)
  check <- function(value, pattern) {
    readr::write_csv(value, case$paths$coordinates)
    testthat::expect_error(read_drift_inputs(case$paths$coordinates, case$paths$evidence, case$paths$spec), pattern)
  }
  check(rbind(p, p[1, ]), "Duplicate")
  check(p[p$period != "2026-08-09", ], "missing periods")
  bad <- p; bad$x[1] <- Inf; check(bad, "Invalid/missing")
  bad <- p; bad$evidence_ids[1] <- '["not-found"]'; check(bad, "resolvable")
  bad <- p; bad$evidence_ids[1] <- '"not-an-array"'; check(bad, "JSON array")
})
testthat::test_that("actual driftmapR recovers known movement and preserves entry/exit", {
  require_drift(); case <- drift_case(); on.exit(unlink(case$directory, recursive = TRUE))
  m <- build_case(case)
  movement <- readr::read_csv(file.path(case$output, "movement.csv"), show_col_types = FALSE)
  testthat::expect_equal(movement$distance[movement$entity == "SYN_D"], case$paths$expected_displacement, tolerance = 1e-9)
  testthat::expect_true(all(movement$distance[movement$entity %in% c("SYN_A", "SYN_B", "SYN_C")] < 1e-9))
  testthat::expect_false(any(c("SYN_E", "SYN_F") %in% movement$entity))
  coverage <- readr::read_csv(file.path(case$output, "comparability.csv"), show_col_types = FALSE)
  testthat::expect_equal(coverage$status[match(c("SYN_E", "SYN_F"), coverage$country_id)], c("EXITED", "ENTERED"))
  testthat::expect_identical(m$validation$uncertainty, "NOT_ESTIMATED")
  testthat::expect_identical(m$validation$inference, "NOT_VALIDATED")
  testthat::expect_identical(m$data_kind, "SYNTHETIC")
  distances <- readr::read_csv(file.path(case$output, "reference-distance-changes.csv"), show_col_types = FALSE)
  testthat::expect_equal(distances$change[distances$entity == "SYN_D"], sqrt(1.5^2 + 1.25^2) - sqrt(2), tolerance = 1e-9)
  testthat::expect_error(build_case(case), "immutable")
})
testthat::test_that("collinear and insufficient anchor geometry is rejected", {
  require_drift(); case <- drift_case(); on.exit(unlink(case$directory, recursive = TRUE))
  p <- readr::read_csv(case$paths$coordinates, show_col_types = FALSE); p$y <- 0
  readr::write_csv(p, case$paths$coordinates)
  testthat::expect_error(build_case(case), "rank|collinear|geometry|degenerate")
  testthat::expect_false(dir.exists(case$output))
  spec <- yaml::read_yaml(case$paths$spec); spec$anchors <- c("SYN_A", "SYN_B")
  yaml::write_yaml(spec, case$paths$spec)
  testthat::expect_error(build_case(case), "insufficient|at least 3")
})
testthat::test_that("missing entity observations are not bridged across three periods", {
  require_drift(); case <- drift_case(); on.exit(unlink(case$directory, recursive = TRUE))
  p <- readr::read_csv(case$paths$coordinates, show_col_types = FALSE)
  middle <- p[p$period == "2026-08-09" & p$country_id != "SYN_D", ]; middle$period <- "2026-08-24"
  readr::write_csv(rbind(p, middle), case$paths$coordinates)
  spec <- yaml::read_yaml(case$paths$spec); spec$periods <- c("2026-08-09", "2026-08-24", "2026-09-09")
  yaml::write_yaml(spec, case$paths$spec)
  build_case(case)
  movement <- readr::read_csv(file.path(case$output, "movement.csv"), show_col_types = FALSE)
  testthat::expect_false("SYN_D" %in% movement$entity)
})
testthat::test_that("panels enforce synthetic opt-in, track, cutoff, stale status and hashes", {
  require_drift(); case <- drift_case(); on.exit(unlink(case$directory, recursive = TRUE))
  build_case(case)
  config <- list(artifact_dir = case$output, max_age_days = 45L, allow_synthetic = FALSE)
  panel <- function(track = "statements", date = "2026-09-09") load_drift_panel(UN_TEST_ROOT, config, track, date, case$directory)
  testthat::expect_identical(panel()$status, "FAILED")
  config$allow_synthetic <- TRUE
  testthat::expect_identical(panel()$status, "DESCRIPTIVE")
  testthat::expect_identical(panel(date = "2026-11-01")$status, "STALE")
  testthat::expect_identical(panel(date = "2026-09-01")$status, "FAILED")
  testthat::expect_identical(panel("votes")$status, "FAILED")
  write_utf8("tampered", file.path(case$output, "movement.csv"))
  testthat::expect_identical(panel()$status, "FAILED")
})
testthat::test_that("path traversal is refused even when a hash is supplied", {
  require_drift(); case <- drift_case(); on.exit(unlink(case$directory, recursive = TRUE))
  build_case(case); path <- file.path(case$output, "model-manifest.json"); m <- read_json(path)
  m$files[[1]]$path <- "../outside.csv"; write_json(m, path)
  config <- list(artifact_dir = case$output, max_age_days = 45L, allow_synthetic = TRUE)
  p <- load_drift_panel(UN_TEST_ROOT, config, "statements", "2026-09-09", case$directory)
  testthat::expect_identical(p$status, "FAILED")
  testthat::expect_match(p$message, "file inventory")
})
testthat::test_that("model rendering produces CID MIME and a self-contained local preview", {
  require_drift(); case <- drift_case(); on.exit(unlink(case$directory, recursive = TRUE), add = TRUE)
  build_case(case)
  cfg <- test_config(); cfg$models$statements <- list(artifact_dir = case$output, max_age_days = 45L, allow_synthetic = TRUE)
  on.exit(unlink(file.path(UN_TEST_ROOT, cfg$output_root), recursive = TRUE), add = TRUE)
  r <- run_pipeline(UN_TEST_ROOT, cfg, fixture()$day, fixture_fetcher(fixture()))
  html <- rawToChar(read_bytes(r$preview))
  body <- rawToChar(read_bytes(file.path(r$run_directory, "email-body.html")))
  mime <- rawToChar(read_bytes(file.path(r$run_directory, "email-preview.eml")))
  testthat::expect_true(grepl("data:image/png;base64,", html, fixed = TRUE))
  testthat::expect_true(grepl('src="cid:statements-movement@un-preview"', body, fixed = TRUE))
  testthat::expect_false(grepl("data:image/png", body, fixed = TRUE))
  testthat::expect_true(grepl("Content-ID: <statements-movement@un-preview>", mime, fixed = TRUE))
  testthat::expect_true(grepl("SYNTHETIC ENGINEERING EXAMPLE", html, fixed = TRUE))
  testthat::expect_false(r$email_sent)
})
testthat::test_that("voting artifacts use their own accepted track", {
  require_drift(); case <- drift_case("votes"); on.exit(unlink(case$directory, recursive = TRUE))
  build_case(case)
  config <- list(artifact_dir = case$output, max_age_days = 120L, allow_synthetic = TRUE)
  panel <- load_drift_panel(UN_TEST_ROOT, config, "votes", "2026-09-09", case$directory)
  testthat::expect_identical(panel$status, "DESCRIPTIVE")
  testthat::expect_identical(panel$track, "votes")
  testthat::expect_identical(panel$figure$cid, "votes-movement@un-preview")
})
