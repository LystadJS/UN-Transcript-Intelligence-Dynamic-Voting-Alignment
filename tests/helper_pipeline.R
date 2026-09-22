test_config <- function() {
  cfg <- read_config(UN_TEST_ROOT)
  cfg$output_root <- paste0("test-", basename(tempfile()))
  cfg$storage$duckdb <- FALSE; cfg$storage$parquet <- FALSE
  cfg$http$request_interval_seconds <- 0
  cfg
}
fixture <- function(text = "We strongly support cooperation on artificial intelligence and responsible development. This commitment requires practical support for every member state.") {
  day <- "2026-09-09"
  item <- list(title = "Synthetic engineering fixture <not a real meeting>", date = paste0(day, "T00:00:00.000Z"),
    body = "General Assembly", category = "General Assembly", slug = "asset/test/one", duration = "00:02:00",
    hasTranscript = TRUE, pageUrl = "/en/asset/test/one", jsonUrl = "/en/asset/test/one.json", textUrl = "/en/asset/test/one.txt")
  source <- list(disclaimer = "Automatic transcript engineering fixture", video = list(id = "test/one", slug = item$slug,
    title = item$title, date = item$date, duration = "00:02:00"),
    transcript = list(language = "en", data = list(list(statement_number = 1L, start = 0,
      pageUrl = paste0(item$pageUrl, "?t=0"), speaker = list(name = "Test speaker", affiliation = "USA", affiliation_full = "United States of America"),
      paragraphs = list(list(sentences = list(list(text = text, start = 0, end = 8))))))))
  inventory <- list(meetings = list(item), total = 1L, totalIncludingOther = 1L, hasMore = FALSE, page = 1L, pageSize = 250L)
  list(day = day, item = item, source = source, inventory = inventory)
}
fixture_fetcher <- function(f, fail_txt = FALSE) function(url) {
  if (grepl("meetings.json", url, fixed = TRUE)) return(charToRaw(json_text(f$inventory)))
  if (endsWith(url, ".json")) return(charToRaw(json_text(f$source)))
  if (fail_txt) stop("Synthetic TXT failure")
  charToRaw("Synthetic engineering transcript; not a real UN meeting.")
}
run_fixture <- function(f, config = test_config(), fail_txt = FALSE) {
  on.exit(unlink(file.path(UN_TEST_ROOT, config$output_root), recursive = TRUE), add = TRUE)
  run_pipeline(UN_TEST_ROOT, config, f$day, fixture_fetcher(f, fail_txt))
}
