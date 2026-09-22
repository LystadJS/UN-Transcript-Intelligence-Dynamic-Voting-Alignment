
testthat::test_that("source URLs stay on the UN HTTPS origin", {
  testthat::expect_equal(source_url("/en/sc/123.json"), "https://transcripts.un.org/en/sc/123.json")
  for (url in c("http://transcripts.un.org/en", "https://example.com/en", "//evil.example/en", "https://user@transcripts.un.org/en", "https://transcripts.un.org/en#x")) testthat::expect_error(source_url(url))
})
testthat::test_that("registry resolution preserves ambiguity and organizational labels", {
  reg <- load_registry(UN_TEST_ROOT)
  testthat::expect_equal(resolve_country(list(affiliation = "USA"), reg)$id, "M49_840")
  testthat::expect_equal(resolve_country(list(affiliation = "GA"), reg)$method, "unresolved")
  testthat::expect_equal(resolve_country(list(affiliation = "USA", affiliation_full = "China"), reg)$method, "ambiguous")
  testthat::expect_equal(resolve_country(list(name = "China"), reg)$method, "unresolved")
})
testthat::test_that("complete extraction is verbatim and email remains a preview", {
  f <- fixture(); result <- run_fixture(f)
  testthat::expect_equal(result$status, "COMPLETE")
  testthat::expect_equal(result$tables$statements$text, f$source$transcript$data[[1]]$paragraphs[[1]]$sentences[[1]]$text)
  testthat::expect_equal(result$tables$statement_summaries$text, result$tables$evidence$text)
  testthat::expect_false(result$email_sent)
  testthat::expect_equal(result$manifest$counts$statements, 1)
})
testthat::test_that("missing transcripts remain in coverage", {
  f <- fixture(); missing <- f$item; missing$slug <- "asset/test/two"; missing$hasTranscript <- FALSE; missing$textUrl <- NULL
  # Keep the explicit JSON null key.
  missing["textUrl"] <- list(NULL)
  f$inventory$meetings <- list(f$item, missing); f$inventory$total <- f$inventory$totalIncludingOther <- 2L
  r <- run_fixture(f)
  testthat::expect_equal(r$status, "COMPLETE")
  testthat::expect_equal(r$tables$inventory$status, c("COLLECTED", "NO_TRANSCRIPT"))
  testthat::expect_equal(r$manifest$counts$unavailable, 1)
})
testthat::test_that("one malformed inventory row cannot erase valid rows", {
  f <- fixture(); bad <- f$item; bad$slug <- "asset/test/two"; bad$hasTranscript <- "true"
  f$inventory$meetings <- list(f$item, bad); f$inventory$total <- f$inventory$totalIncludingOther <- 2L
  r <- run_fixture(f)
  testthat::expect_equal(r$status, "PARTIAL")
  testthat::expect_equal(nrow(r$tables$statements), 1)
  testthat::expect_equal(r$manifest$day_coverage[[1]]$malformed_rows, 1)
  testthat::expect_false(r$manifest$day_coverage[[1]]$inventory_complete)
})
testthat::test_that("duplicate pagination and inconsistent totals are reported", {
  f <- fixture(); f$inventory$hasMore <- TRUE
  r <- run_fixture(f)
  testthat::expect_equal(r$status, "PARTIAL")
  testthat::expect_equal(nrow(r$tables$inventory), 1)
  f <- fixture(); f$inventory$total <- f$inventory$totalIncludingOther <- 2L
  testthat::expect_equal(run_fixture(f)$status, "PARTIAL")
})
testthat::test_that("bad detail data and TXT failure are distinguishable", {
  f <- fixture(); f$source$transcript$data[[1]]$paragraphs[[1]]$sentences[[1]]$end <- -1
  r <- run_fixture(f)
  testthat::expect_equal(r$status, "PARTIAL")
  testthat::expect_equal(r$tables$inventory$status, "FAILED")
  testthat::expect_equal(nrow(r$tables$statements), 0)
  r <- run_fixture(fixture(), fail_txt = TRUE)
  testthat::expect_equal(r$tables$inventory$status, "COLLECTED_TXT_FAILED")
  testthat::expect_equal(nrow(r$tables$statements), 1)
})
testthat::test_that("empty days and other-language transcripts are honest outcomes", {
  f <- fixture(); f$inventory$meetings <- list(); f$inventory$total <- f$inventory$totalIncludingOther <- 0L
  r <- run_fixture(f)
  testthat::expect_equal(r$status, "COMPLETE")
  testthat::expect_equal(r$manifest$counts$inventory_rows, 0)
  f <- fixture(); f$source$transcript$language <- "fr"
  r <- run_fixture(f)
  testthat::expect_equal(r$tables$inventory$status, "UNAVAILABLE_LANGUAGE")
})
testthat::test_that("topic filtering keeps the complete statement archive", {
  cfg <- test_config(); cfg$topics <- list(list(id = "finance", label = "Finance", pattern = "\\bdebt\\b"))
  r <- run_fixture(fixture(), cfg)
  testthat::expect_equal(nrow(r$tables$statements), 1)
  testthat::expect_false(r$tables$statements$topic_match)
  testthat::expect_equal(r$tables$meeting_summaries$child_summary_ids, "[]")
  r <- run_fixture(fixture("We urge action to address debt and financing for sustainable development."), cfg)
  testthat::expect_true(r$tables$statements$topic_match)
})
testthat::test_that("summary tampering and cross-speaker evidence fail validation", {
  r <- run_fixture(fixture()); t <- r$tables
  t$statement_summaries$text <- "Invented statement"
  testthat::expect_error(verify_summaries(t$statement_summaries, t$meeting_summaries, t$daily_summaries, t$evidence), "Unsupported")
})
testthat::test_that("HTML source content is escaped and MIME body round-trips", {
  cfg <- test_config(); on.exit(unlink(file.path(UN_TEST_ROOT, cfg$output_root), recursive = TRUE), add = TRUE)
  f <- fixture("We support cooperation <script>alert('bad')</script> & practical development measures.")
  r <- run_pipeline(UN_TEST_ROOT, cfg, f$day, fixture_fetcher(f))
  html <- rawToChar(read_bytes(r$preview))
  testthat::expect_false(grepl("<script>", html, fixed = TRUE))
  testthat::expect_true(grepl("&lt;script&gt;", html, fixed = TRUE))
  eml <- rawToChar(read_bytes(file.path(r$run_directory, "email-preview.eml")))
  outgoing <- read_bytes(file.path(r$run_directory, "email-body.html"))
  testthat::expect_true(grepl(mime_base64(outgoing), eml, fixed = TRUE))
  testthat::expect_true(grepl('Content-Type: multipart/mixed;', eml, fixed = TRUE))
  testthat::expect_true(grepl('filename="full-report.html"', eml, fixed = TRUE))
  testthat::expect_false(grepl('href="full-report.html"', rawToChar(outgoing), fixed = TRUE))
  testthat::expect_false(grepl("\r\nTo:", eml, fixed = TRUE))
})
testthat::test_that("same bytes retain evidence IDs and revisions acquire new IDs", {
  a <- run_fixture(fixture()); b <- run_fixture(fixture())
  testthat::expect_equal(a$tables$evidence$evidence_id, b$tables$evidence$evidence_id)
  c <- run_fixture(fixture("We support a revised approach to sustainable development and cooperation."))
  testthat::expect_false(identical(a$tables$evidence$evidence_id, c$tables$evidence$evidence_id))
})
testthat::test_that("DuckDB deduplicates evidence and retains run observations", {
  testthat::skip_if_not_installed("duckdb")
  cfg <- test_config(); cfg$storage$duckdb <- TRUE; cfg$storage$parquet <- TRUE
  on.exit(unlink(file.path(UN_TEST_ROOT, cfg$output_root), recursive = TRUE), add = TRUE)
  f <- fixture(); a <- run_pipeline(UN_TEST_ROOT, cfg, f$day, fixture_fetcher(f))
  b <- run_pipeline(UN_TEST_ROOT, cfg, f$day, fixture_fetcher(f))
  testthat::expect_equal(a$status, "COMPLETE"); testthat::expect_equal(b$status, "COMPLETE")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = b$manifest$database$path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM evidence")$n, 1)
  testthat::expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM inventory")$n, 2)
  testthat::expect_true(file.exists(file.path(b$run_directory, "tables/evidence.parquet")))
})

testthat::test_that("R selection matches the recovered Python selector on archived live data", {
  fixture_path <- file.path(UN_TEST_ROOT, "examples/reference_selection.json")
  testthat::skip_if_not(file.exists(fixture_path), "Reference fixture not available")
  cases <- read_json(fixture_path)
  cfg <- read_config(UN_TEST_ROOT)
  for (case in cases) {
    rows <- dplyr::bind_rows(case$sentences)
    pick <- select_passage(rows, cfg$summary)
    testthat::expect_equal(paste(rows$text[pick$indices], collapse = " "), case$expected_text, info = case$statement_id)
    testthat::expect_equal(pick$score, case$expected_score, tolerance = 1e-6, info = case$statement_id)
  }
})
