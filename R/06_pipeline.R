# Segment 1 — Local exports and a cumulative DuckDB store.
# Repeated source bytes retain the same evidence IDs; run observations remain distinct.
export_tables <- function(tables, directory) {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  for (name in names(tables)) {
    readr::write_csv(tables[[name]], file.path(directory, paste0(name, ".csv")), na = "")
    jsonlite::write_json(tables[[name]], file.path(directory, paste0(name, ".json")), dataframe = "rows", auto_unbox = TRUE, na = "null", pretty = FALSE)
  }
}
store_duckdb <- function(ctx, tables) {
  assert(requireNamespace("duckdb", quietly = TRUE), "duckdb package missing. Run setup.R, or explicitly choose --no-db for CSV/JSON-only mode.")
  dir.create(file.path(ctx$output, "database"), showWarnings = FALSE)
  path <- file.path(ctx$output, "database", "transcripts.duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(con, "SET memory_limit = '2GB'")
  keys <- c(statements = "statement_id", evidence = "evidence_id", statement_summaries = "summary_id", meeting_summaries = "summary_id", daily_summaries = "summary_id")
  DBI::dbWithTransaction(con, {
    for (name in names(tables)) {
      frame <- tables[[name]]
      if (!name %in% names(keys)) frame <- dplyr::mutate(frame, run_id = ctx$run_id, .before = 1)
      if (!DBI::dbExistsTable(con, name)) {
        DBI::dbWriteTable(con, name, frame)
        if (name %in% names(keys)) DBI::dbExecute(con, paste0('CREATE UNIQUE INDEX "', name, '_pk" ON "', name, '" ("', keys[[name]], '")'))
      } else if (name %in% names(keys)) {
        key <- keys[[name]]
        # Stage only this run; database anti-join avoids reading the historical corpus into RAM.
        DBI::dbWriteTable(con, "stage_rows", frame, temporary = TRUE, overwrite = TRUE)
        DBI::dbExecute(con, paste0('INSERT INTO "', name, '" SELECT s.* FROM stage_rows s WHERE NOT EXISTS (SELECT 1 FROM "', name, '" t WHERE t."', key, '" = s."', key, '")'))
        DBI::dbRemoveTable(con, "stage_rows")
      } else DBI::dbAppendTable(con, name, frame)
    }
  })
  DBI::dbExecute(con, "CHECKPOINT")
  if (isTRUE(ctx$config$storage$parquet)) {
    directory <- file.path(ctx$run_dir, "tables")
    for (name in names(tables)) {
      DBI::dbWriteTable(con, "export_rows", tables[[name]], temporary = TRUE, overwrite = TRUE)
      target <- DBI::dbQuoteString(con, normalizePath(directory, winslash = "/", mustWork = TRUE) |> file.path(paste0(name, ".parquet")))
      DBI::dbExecute(con, paste0("COPY export_rows TO ", target, " (FORMAT PARQUET)"))
      DBI::dbRemoveTable(con, "export_rows")
    }
  }
  list(path = path, status = "COMPLETE", parquet = isTRUE(ctx$config$storage$parquet))
}

# Segment 2 — Complete run: discover -> archive -> normalize -> summarize -> preview.
run_pipeline <- function(root, config, dates, fetcher = NULL) {
  dates <- sort(unique(vapply(dates, validate_day, character(1))))
  assert(length(dates) > 0 && length(dates) <= 90, "Choose 1..90 dates per run.")
  output <- file.path(root, config$output_root)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  lock <- filelock::lock(file.path(output, "pipeline.lock"), timeout = 0)
  assert(!is.null(lock), "Another pipeline run is active for this output folder.")
  on.exit(filelock::unlock(lock), add = TRUE)
  ctx <- new_context(root, config, dates, fetcher)
  manifest_path <- file.path(ctx$run_dir, "manifest.json")
  write_json(list(run_id = ctx$run_id, status = "RUNNING", started_at_utc = ctx$started, dates = as.list(dates)), manifest_path)
  completed <- FALSE
  on.exit({
    if (!completed) write_json(list(run_id = ctx$run_id, status = "FAILED", started_at_utc = ctx$started,
      finished_at_utc = utc_now(), dates = as.list(dates), requests = ctx$requests, errors = ctx$errors,
      failure = "Run aborted before completion; inspect console.log. Source archive retained."), manifest_path)
  }, add = TRUE)
  registry <- load_registry(root)
  inventory <- dplyr::bind_rows(lapply(dates, function(day) collect_inventory(ctx, day)))
  collected <- list(); statement_rows <- list(); evidence_rows <- list()
  for (i in seq_len(nrow(inventory))) {
    if (!inventory$in_scope[i] || !inventory$has_transcript[i]) next
    item <- inventory[i, ]
    message("Collecting ", item$date, " ", item$slug)
    parsed <- tryCatch({
      raw <- fetch_source(ctx, item$json_url, "detail", item$date, item$slug)
      inventory$detail_sha256[i] <- raw$sha256
      parse_transcript(raw, item, config, registry)
    }, error = function(e) {
      inventory$status[i] <<- "FAILED"; inventory$error[i] <<- conditionMessage(e)
      record_error(ctx, "detail", conditionMessage(e), item$date, item$slug)
      NULL
    })
    if (is.null(parsed)) next
    if (isTRUE(parsed$unavailable_language)) { inventory$status[i] <- "UNAVAILABLE_LANGUAGE"; next }
    collected[[length(collected) + 1L]] <- parsed$meetings
    statement_rows[[length(statement_rows) + 1L]] <- parsed$statements
    evidence_rows[[length(evidence_rows) + 1L]] <- parsed$evidence
    inventory$status[i] <- "COLLECTED"
    tryCatch({
      assert(nzchar(item$text_url), "Transcript TXT link missing from inventory.")
      raw_txt <- fetch_source(ctx, item$text_url, "txt", item$date, item$slug)
      text <- rawToChar(raw_txt$bytes)
      assert(nzchar(trimws(text)) && !grepl("^\\s*(<!doctype html|<html)", text, ignore.case = TRUE), "TXT response empty or HTML.")
      inventory$txt_sha256[i] <- raw_txt$sha256
    }, error = function(e) {
      inventory$status[i] <<- "COLLECTED_TXT_FAILED"; inventory$error[i] <<- conditionMessage(e)
      record_error(ctx, "txt", conditionMessage(e), item$date, item$slug)
    })
  }
  meetings <- rows_frame(collected, empty_meetings())
  statements <- rows_frame(statement_rows, empty_statements())
  evidence <- rows_frame(evidence_rows, empty_evidence())
  assert(!anyDuplicated(meetings$meeting_id) && !anyDuplicated(statements$statement_id), "Duplicate normalized recording or statement ID.")
  summaries <- build_summaries(statements, evidence, meetings, config)
  tables <- list(inventory = inventory, meetings = meetings, statements = statements, evidence = evidence,
    statement_summaries = summaries$statements, meeting_summaries = summaries$meetings, daily_summaries = summaries$daily)
  export_tables(tables, file.path(ctx$run_dir, "tables"))
  database <- list(status = "DISABLED_EXPLICITLY")
  if (isTRUE(config$storage$duckdb)) {
    database <- tryCatch(store_duckdb(ctx, tables), error = function(e) {
      record_error(ctx, "database", conditionMessage(e)); list(status = "FAILED", error = conditionMessage(e))
    })
  }
  # Verify archive bytes after processing, including responses that failed schema checks.
  for (request in ctx$requests) {
    if (identical(request$status, "HTTP_SUCCESS") && !identical(sha_file(file.path(ctx$output, request$path)), request$sha256)) {
      record_error(ctx, "archive", paste("Hash mismatch:", request$path))
    }
  }
  source_files <- project_files(root)
  manifest <- list(project_version = config$project_version, run_id = ctx$run_id,
    status = if (length(ctx$errors)) "PARTIAL" else "COMPLETE", started_at_utc = ctx$started,
    finished_at_utc = utc_now(), dates = as.list(dates), locale = config$locale, timezone = config$timezone,
    scope = "UN Transcripts inventory; not a census of all UN meetings", configuration = config,
    configuration_sha256 = sha_bytes(charToRaw(enc2utf8(json_text(config)))),
    code_and_registry_hashes = stats::setNames(lapply(source_files, sha_file), substring(source_files, nchar(root) + 2)),
    runtime = list(r_version = R.version.string, platform = R.version$platform),
    day_coverage = ctx$day_records, counts = list(inventory_rows = nrow(inventory), in_scope = sum(inventory$in_scope),
      collected_meetings = nrow(meetings), statements = nrow(statements), evidence_sentences = nrow(evidence),
      statement_summaries = nrow(summaries$statements), meeting_summaries = nrow(summaries$meetings),
      daily_summaries = nrow(summaries$daily), unavailable = sum(inventory$status %in% c("NO_TRANSCRIPT", "UNAVAILABLE_LANGUAGE"))),
    verification = list(quotation_fidelity = "PASS", contiguous_excerpts = "PASS", evidence_lineage = "PASS",
      upstream_transcription_accuracy = "NOT_MEASURED", independent_speaker_identity = "NOT_VERIFIED"),
    database = database, requests = ctx$requests, errors = ctx$errors, email = list(mode = "PREVIEW_ONLY", sent = FALSE))
  preview <- create_preview(ctx, inventory, meetings, statements, summaries, manifest)
  manifest$email <- preview
  write_json(manifest, manifest_path)
  write_utf8(capture.output(sessionInfo()), file.path(ctx$run_dir, "sessionInfo.txt"))
  readr::write_lines(ctx$run_id, file.path(ctx$output, "LATEST_RUN.txt"))
  completed <- TRUE
  list(status = manifest$status, run_id = ctx$run_id, run_directory = ctx$run_dir, preview = preview$path,
    counts = manifest$counts, errors = length(ctx$errors), email_sent = FALSE,
    tables = tables, manifest = manifest)
}
