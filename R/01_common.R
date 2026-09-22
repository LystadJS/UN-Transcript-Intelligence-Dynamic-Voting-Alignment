# Segment 1 — Configuration and provenance utilities.
# Inputs: configuration / source bytes. Outputs: validated settings and stable IDs.
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
utc_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
fail <- function(...) stop(..., call. = FALSE)
assert <- function(ok, message) if (!isTRUE(ok)) fail(message)
scalar_text <- function(x, default = "") {
  if (is.null(x)) return(default)
  assert(is.character(x) && length(x) == 1L && !is.na(x), "Expected one text value.")
  x
}
is_whole <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x == floor(x)
json_text <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
sha_bytes <- function(x) digest::digest(x, algo = "sha256", serialize = FALSE)
sha_file <- function(path) digest::digest(file = path, algo = "sha256")
stable_id <- function(prefix, ...) paste0(prefix, "_", substr(sha_bytes(charToRaw(enc2utf8(json_text(list(...))))), 1, 24))
read_json <- function(path) jsonlite::fromJSON(path, simplifyVector = FALSE)
read_bytes <- function(path) readBin(path, "raw", n = file.info(path)$size)
write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
  invisible(path)
}
write_utf8 <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, "wb"); on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste0(x, collapse = "\n"))), con)
  invisible(path)
}
rows_frame <- function(rows, template) {
  if (!length(rows)) return(template)
  dplyr::bind_rows(rows)
}
word_count <- function(x) lengths(strsplit(trimws(x), "[[:space:]]+", perl = TRUE))
project_files <- function(root) sort(c(list.files(file.path(root, "R"), "\\.R$", full.names = TRUE),
  file.path(root, "run.R"), list.files(file.path(root, "data", "registries"), "\\.csv$", full.names = TRUE)))
validate_day <- function(x) {
  assert(length(x) == 1L && grepl("^\\d{4}-\\d{2}-\\d{2}$", x), "Date must be YYYY-MM-DD.")
  day <- as.Date(x)
  assert(!is.na(day) && format(day, "%Y-%m-%d") == x, "Invalid date.")
  x
}
read_config <- function(root, path = "config/settings.yml") {
  c <- yaml::read_yaml(file.path(root, path))
  assert(identical(c$locale, "en"), "This extractive release supports English only.")
  assert(c$timezone %in% OlsonNames(), "Unknown timezone.")
  assert(is_whole(c$lookback_days) && c$lookback_days >= 1 && c$lookback_days <= 90, "lookback_days must be 1..90.")
  assert(is.logical(c$include_today) && length(c$include_today) == 1, "include_today must be true or false.")
  for (field in c("max_attempts", "max_pages", "max_response_bytes")) {
    assert(is_whole(c$http[[field]]) && c$http[[field]] > 0, paste("Invalid http setting:", field))
  }
  assert(is.numeric(c$http$timeout_seconds) && c$http$timeout_seconds > 0, "Invalid timeout.")
  assert(is.numeric(c$http$request_interval_seconds) && c$http$request_interval_seconds >= 0, "Invalid request interval.")
  for (field in c("excerpt_target_words", "meeting_highlights")) {
    assert(is_whole(c$summary[[field]]) && c$summary[[field]] > 0, paste("Invalid summary setting:", field))
  }
  assert(identical(c$email$mode, "preview"), "Only email preview is implemented. No mail is sent.")
  for (field in c("from", "to", "subject_prefix")) {
    assert(!grepl("[\r\n]", scalar_text(c$email[[field]])), "Email headers cannot contain line breaks.")
  }
  assert(grepl("^[^[:space:]@<>]+@[^[:space:]@<>]+\\.[^[:space:]@<>]+$", c$email$from), "Invalid sender address.")
  for (topic in c$topics) {
    assert(nzchar(scalar_text(topic$id)) && nzchar(scalar_text(topic$pattern)), "Every topic needs id and pattern.")
    tryCatch(grepl(topic$pattern, "validation", perl = TRUE), error = function(e) fail("Invalid topic regex: ", topic$id))
  }
  ids <- vapply(c$topics, function(t) t$id, character(1))
  assert(!anyDuplicated(ids), "Topic IDs must be unique.")
  c$report <- c$report %||% list(headline_excerpts = 3L, meeting_cards = 4L)
  for (field in c("headline_excerpts", "meeting_cards")) {
    assert(is_whole(c$report[[field]]) && c$report[[field]] >= 1 && c$report[[field]] <= 10,
      paste("Report limit must be 1..10:", field))
  }
  c$models <- c$models %||% list()
  for (track in c("statements", "votes")) {
    m <- c$models[[track]] %||% list(artifact_dir = "", max_age_days = 45L, allow_synthetic = FALSE)
    m$artifact_dir <- scalar_text(m$artifact_dir)
    assert(is_whole(m$max_age_days) && m$max_age_days >= 0, "Model max_age_days must be a nonnegative integer.")
    assert(is.logical(m$allow_synthetic) && length(m$allow_synthetic) == 1L && !is.na(m$allow_synthetic), "Invalid allow_synthetic flag.")
    c$models[[track]] <- m
  }
  c
}

# Segment 2 — URL policy. Follow literal inventory links; keep requests on UN origin.
source_url <- function(value) {
  value <- scalar_text(value)
  assert(nzchar(value) && !grepl("[[:space:]\\\\]", value), "Invalid source URL.")
  if (startsWith(value, "/") && !startsWith(value, "//")) value <- paste0("https://transcripts.un.org", value)
  u <- httr2::url_parse(value)
  assert(identical(u$scheme, "https") && identical(u$hostname, "transcripts.un.org") &&
    (is.null(u$port) || identical(as.character(u$port), "443")) &&
    !nzchar(u$username %||% "") && !nzchar(u$password %||% "") && !nzchar(u$fragment %||% ""),
    "Source URL must use the transcripts.un.org HTTPS origin.")
  value
}
inventory_url <- function(day, page) paste0("https://transcripts.un.org/en/meetings.json?date=", day,
  "&page=", page, "&xlang=1")

# Segment 3 — Flat export schemas (empty runs retain valid column definitions).
empty_inventory <- function() tibble::tibble(date = character(), slug = character(), title = character(),
  category = character(), body = character(), has_transcript = logical(), page_url = character(),
  json_url = character(), text_url = character(), in_scope = logical(), status = character(),
  detail_sha256 = character(), txt_sha256 = character(), error = character())
empty_statements <- function() tibble::tibble(statement_id = character(), meeting_id = character(), slug = character(),
  date = character(), statement_number = integer(), speaker_label = character(), speaker_role = character(),
  affiliation = character(), affiliation_full = character(), speaker_json = character(), country_entity_id = character(),
  country_name = character(), resolution_method = character(), text = character(), word_count = integer(),
  source_sha256 = character(), source_path = character(), source_url = character(), source_pointer = character(),
  start_seconds = double(), end_seconds = double(), timing_warning = logical(), topics = character(), topic_match = logical())
empty_evidence <- function() tibble::tibble(evidence_id = character(), statement_id = character(),
  sentence_index = integer(), text = character(), start_seconds = double(), end_seconds = double(),
  source_sha256 = character(), source_path = character(), source_pointer = character(), source_url = character())
empty_summaries <- function() tibble::tibble(summary_id = character(), statement_id = character(), meeting_id = character(),
  date = character(), speaker_label = character(), affiliation_full = character(), text = character(),
  evidence_ids = character(), selection_score = double(), source_sha256 = character(), source_url = character(),
  method = character(), epistemic_status = character(), timing_warning = logical(), topic_match = logical(), topics = character())
empty_meetings <- function() tibble::tibble(meeting_id = character(), slug = character(), title = character(), date = character(),
  category = character(), source_sha256 = character(), source_url = character(), source_path = character(),
  source_type = character(), language = character(), statement_count = integer(), timing_warning = logical(), timing_note = character())
empty_parents <- function() tibble::tibble(summary_id = character(), level = character(), parent_key = character(),
  date = character(), child_summary_ids = character(), evidence_ids = character(), method = character())
