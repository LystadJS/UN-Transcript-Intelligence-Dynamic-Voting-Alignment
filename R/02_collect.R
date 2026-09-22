# Segment 1 — HTTP retrieval and immutable source archive.
# Inputs: a UN URL and run context. Outputs: verified bytes, hash and relative path.
new_context <- function(root, config, dates, fetcher = NULL) {
  ctx <- new.env(parent = emptyenv())
  ctx$root <- root; ctx$config <- config
  ctx$output <- file.path(root, config$output_root)
  dir.create(ctx$output, recursive = TRUE, showWarnings = FALSE)
  ctx$run_id <- paste0(format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "_", substr(sha_bytes(charToRaw(tempfile())), 1, 10))
  ctx$run_dir <- file.path(ctx$output, "runs", ctx$run_id)
  dir.create(ctx$run_dir, recursive = TRUE)
  ctx$requests <- list(); ctx$errors <- list(); ctx$day_records <- list()
  ctx$fetcher <- fetcher; ctx$started <- utc_now(); ctx$dates <- dates
  ctx
}
record_error <- function(ctx, stage, detail, day = "", slug = "") {
  ctx$errors[[length(ctx$errors) + 1L]] <- list(stage = stage, date = day, slug = slug, detail = detail, at_utc = utc_now())
}
http_bytes <- function(url, settings) {
  Sys.sleep(settings$request_interval_seconds)
  req <- httr2::request(url) |>
    httr2::req_user_agent("UNTranscriptR/0.2.0 (public transcript research)") |>
    httr2::req_headers(Accept = "application/json, text/plain;q=0.9") |>
    httr2::req_timeout(settings$timeout_seconds) |>
    httr2::req_options(followlocation = FALSE, maxfilesize_large = settings$max_response_bytes) |>
    httr2::req_error(is_error = function(response) FALSE)
  # Explicit bounded retries also support the older httr2 shipped with R 4.3.
  response <- NULL
  for (attempt in seq_len(settings$max_attempts)) {
    value <- tryCatch(httr2::req_perform(req), error = function(e) e)
    transport_error <- inherits(value, "error")
    status <- if (transport_error) NA_integer_ else httr2::resp_status(value)
    transient <- transport_error || status %in% c(408L, 429L, 500L, 502L, 503L, 504L)
    if (!transient || attempt == settings$max_attempts) {
      if (transport_error) stop(value)
      response <- value; break
    }
    retry_after <- if (transport_error) NA_real_ else suppressWarnings(as.numeric(httr2::resp_header(value, "retry-after") %||% NA_character_))
    delay <- if (is.finite(retry_after)) max(0, retry_after) else 2^(attempt - 1L)
    assert(delay <= 60, "Server requested a retry delay over 60 seconds; defer to the next run.")
    Sys.sleep(delay)
  }
  assert(httr2::resp_status(response) == 200, paste("Unexpected HTTP status", httr2::resp_status(response)))
  bytes <- httr2::resp_body_raw(response)
  assert(length(bytes) > 0 && length(bytes) <= settings$max_response_bytes, "Response empty or exceeds configured byte limit.")
  bytes
}
fetch_source <- function(ctx, url, kind, day, slug = "") {
  url <- source_url(url)
  at <- utc_now()
  tryCatch({
    bytes <- if (is.null(ctx$fetcher)) http_bytes(url, ctx$config$http) else ctx$fetcher(url)
    assert(is.raw(bytes) && length(bytes) > 0 && length(bytes) <= ctx$config$http$max_response_bytes, "Invalid response bytes.")
    hash <- sha_bytes(bytes)
    extension <- if (kind == "txt") "txt" else "json"
    relative <- paste0("raw/", substr(hash, 1, 2), "/", hash, ".", extension)
    destination <- file.path(ctx$output, relative)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (file.exists(destination)) {
      assert(identical(sha_file(destination), hash), "Existing raw source hash mismatch.")
    } else {
      temp <- tempfile(tmpdir = dirname(destination)); on.exit(unlink(temp), add = TRUE)
      writeBin(bytes, temp)
      assert(identical(sha_file(temp), hash), "Raw write hash mismatch.")
      assert(file.rename(temp, destination), "Could not commit raw source.")
    }
    ctx$requests[[length(ctx$requests) + 1L]] <- list(url = url, kind = kind, date = day, slug = slug,
      status = "HTTP_SUCCESS", retrieved_at_utc = at, sha256 = hash, path = relative, bytes = length(bytes))
    list(bytes = bytes, sha256 = hash, path = relative, url = url)
  }, error = function(e) {
    ctx$requests[[length(ctx$requests) + 1L]] <- list(url = url, kind = kind, date = day, slug = slug,
      status = "FAILED", retrieved_at_utc = at, error = conditionMessage(e))
    stop(e)
  })
}

# Segment 2 — Inventory discovery. Count missing, excluded and failed records explicitly.
parse_inventory_item <- function(x, day, config) {
  for (key in c("title", "date", "slug", "category", "body", "hasTranscript", "pageUrl", "jsonUrl", "textUrl")) {
    assert(key %in% names(x), paste("Missing inventory field:", key))
  }
  assert(is.logical(x$hasTranscript) && length(x$hasTranscript) == 1 && !is.na(x$hasTranscript), "hasTranscript must be boolean.")
  assert(nzchar(scalar_text(x$slug)) && substr(scalar_text(x$date), 1, 10) == day, "Inventory date/slug mismatch.")
  category <- scalar_text(x$category)
  scope <- !length(config$categories) || category %in% unlist(config$categories)
  tibble::tibble(date = day, slug = x$slug, title = scalar_text(x$title, x$slug), category = category,
    body = scalar_text(x$body), has_transcript = x$hasTranscript, page_url = source_url(x$pageUrl),
    json_url = source_url(x$jsonUrl), text_url = if (is.null(x$textUrl)) "" else source_url(x$textUrl),
    in_scope = scope, status = if (!scope) "EXCLUDED_CATEGORY" else if (!x$hasTranscript) "NO_TRANSCRIPT" else "PENDING",
    detail_sha256 = "", txt_sha256 = "", error = "")
}
collect_inventory <- function(ctx, day) {
  rows <- list(); seen <- character(); expected <- NULL; complete <- FALSE; malformed <- 0L; observed <- 0L
  tryCatch({
    for (page in seq_len(ctx$config$http$max_pages)) {
      raw <- fetch_source(ctx, inventory_url(day, page), "inventory", day)
      doc <- jsonlite::fromJSON(rawToChar(raw$bytes), simplifyVector = FALSE)
      assert(is.list(doc$meetings) && is_whole(doc$total) && doc$total >= 0 &&
        is_whole(doc$totalIncludingOther) && doc$totalIncludingOther >= doc$total &&
        is_whole(doc$page) && doc$page == page && is_whole(doc$pageSize) && doc$pageSize > 0 &&
        is.logical(doc$hasMore) && length(doc$hasMore) == 1 && !is.na(doc$hasMore), "Unexpected inventory schema.")
      if (is.null(expected)) expected <- doc$total
      assert(expected == doc$total, "Inventory total changed during pagination; rerun required.")
      assert(doc$totalIncludingOther == doc$total, "Inventory omitted other-language meetings despite xlang=1.")
      assert(length(doc$meetings) > 0 || !doc$hasMore, "Pagination made no progress.")
      for (item in doc$meetings) {
        observed <- observed + 1L
        row <- tryCatch(parse_inventory_item(item, day, ctx$config), error = function(e) {
          malformed <<- malformed + 1L
          record_error(ctx, "inventory_row", conditionMessage(e), day, as.character(item$slug %||% ""))
          NULL
        })
        if (is.null(row)) next
        assert(!row$slug %in% seen, "Duplicate inventory slug across pages.")
        seen <- c(seen, row$slug); rows[[length(rows) + 1L]] <- row
      }
      if (!doc$hasMore) { complete <- TRUE; break }
    }
    assert(complete && observed == expected && malformed == 0, "Inventory incomplete, malformed, or count mismatch.")
  }, error = function(e) {
    complete <<- FALSE
    record_error(ctx, "inventory", conditionMessage(e), day)
  })
  ctx$day_records[[length(ctx$day_records) + 1L]] <- list(date = day, inventory_complete = complete,
    expected = expected, observed = observed, valid_rows = length(rows), malformed_rows = malformed)
  rows_frame(rows, empty_inventory())
}
