# Segment 1 — Port of the recovered deterministic extractive selector.
# Inputs: one statement's original sentence rows. Output: one contiguous passage.
# The 120-word setting is a context target, not a truncation limit.
summary_tokens <- function(text) {
  stopwords <- strsplit("the a an and or to of in on for with is are was were be been this that these those we our i you your it as at by from not have has will would can could should must", " ")[[1]]
  words <- stringr::str_extract_all(tolower(text), "[^\\W\\d_]{3,}")[[1]]
  words[!words %in% stopwords]
}
select_passage <- function(rows, config) {
  assert(nrow(rows) > 0, "Cannot summarize an empty statement.")
  documents <- lapply(rows$text, function(t) unique(summary_tokens(t)))
  counts <- table(unlist(documents, use.names = FALSE))
  scores <- rep(-Inf, nrow(rows))
  cue <- "\\b(?:call(?:s)? for|urge|demand|recommend|committed|support|concern|priority|essential|propose|emphasize|oppose|reject)\\b"
  for (i in seq_len(nrow(rows))) {
    words <- summary_tokens(rows$text[i])
    if (length(words) < 5) next
    rarity <- sum(log((nrow(rows) + 1) / (as.numeric(counts[unique(words)]) + 1)) + 1) / length(words)
    own <- grepl("\\b(?:we|our delegation|my delegation)\\s+(?:also |strongly |firmly |once again )?(?:call|urge|demand|support|oppose|reject|propose|remain committed)\\b", rows$text[i], ignore.case = TRUE, perl = TRUE)
    cues <- stringr::str_count(rows$text[i], stringr::regex(cue, ignore_case = TRUE))
    scores[i] <- rarity + min(3, cues) * 0.7 + 1.2 * own + 0.12 / i
    if (grepl("^(?:thank you|I thank|Mr\\.? President|Madam Chair)", rows$text[i], ignore.case = TRUE, perl = TRUE) && length(words) < 16) scores[i] <- scores[i] - 2
  }
  anchor <- if (any(is.finite(scores))) which.max(scores) else 1L
  start <- end <- anchor
  first_words <- paste(head(strsplit(trimws(rows$text[anchor]), "\\s+", perl = TRUE)[[1]], 12), collapse = " ")
  if (start > 1 && grepl("\\b(?:it|its|they|their|this|these|those)\\b", first_words, ignore.case = TRUE, perl = TRUE)) start <- start - 1L
  terminal <- function(text) grepl('[.!?][”"]?\\s*$', text, perl = TRUE)
  while (start > 1 && (!terminal(rows$text[start - 1L]) || grepl("^\\s*(?:and|but|however|this|these|it|they)\\b", rows$text[start], ignore.case = TRUE, perl = TRUE))) {
    start <- start - 1L
    if (anchor - start >= 4) break
  }
  while (end < nrow(rows) && !terminal(rows$text[end])) {
    end <- end + 1L
    if (end - anchor >= 4) break
  }
  selected <- seq.int(start, end)
  if (end < nrow(rows) && sum(word_count(rows$text[selected])) < config$excerpt_target_words %/% 2L) {
    j <- end + 1L
    while (j <= nrow(rows)) {
      selected <- c(selected, j)
      if (terminal(rows$text[j]) || j - end >= 4) break
      j <- j + 1L
    }
  }
  list(indices = selected, score = if (any(is.finite(scores))) round(max(scores), 6) else 0)
}

# Segment 2 — Hierarchy. Meeting highlights diversify source affiliations; daily
# summaries group meetings. Neither step infers agreement or a political position.
build_summaries <- function(statements, evidence, meetings, config) {
  result <- list()
  for (i in seq_len(nrow(statements))) {
    s <- statements[i, ]; rows <- evidence[evidence$statement_id == s$statement_id, ]
    pick <- select_passage(rows, config$summary); selected <- rows[pick$indices, ]
    ids <- selected$evidence_id
    result[[length(result) + 1L]] <- tibble::tibble(
      summary_id = stable_id("r_statement_summary", s$statement_id, as.list(ids), config$summary),
      statement_id = s$statement_id, meeting_id = s$meeting_id, date = s$date,
      speaker_label = s$speaker_label, affiliation_full = s$affiliation_full,
      text = paste(selected$text, collapse = " "), evidence_ids = json_text(as.list(ids)), selection_score = pick$score,
      source_sha256 = s$source_sha256, source_url = selected$source_url[1], method = "EXTRACTIVE",
      epistemic_status = "OBSERVED_TRANSCRIPT_TEXT", timing_warning = s$timing_warning, topic_match = s$topic_match, topics = s$topics)
  }
  result <- rows_frame(result, empty_summaries())
  parents <- list()
  for (i in seq_len(nrow(meetings))) {
    m <- meetings[i, ]; candidates <- result[result$meeting_id == m$meeting_id & result$topic_match, ]
    candidates <- candidates[order(-candidates$selection_score, candidates$statement_id, method = "radix"), ]
    selected <- integer(); used <- character()
    for (j in seq_len(nrow(candidates))) {
      s <- statements[match(candidates$statement_id[j], statements$statement_id), ]
      if (s$word_count < 20) next
      key <- if (nzchar(candidates$affiliation_full[j])) candidates$affiliation_full[j] else candidates$speaker_label[j]
      if (key %in% used) next
      selected <- c(selected, j); used <- c(used, key)
      if (length(selected) == config$summary$meeting_highlights) break
    }
    if (!length(selected)) selected <- head(seq_len(nrow(candidates)), config$summary$meeting_highlights)
    children <- candidates[selected, ]
    ev <- unique(unlist(lapply(children$evidence_ids, jsonlite::fromJSON), use.names = FALSE))
    parents[[length(parents) + 1L]] <- tibble::tibble(summary_id = stable_id("r_meeting_summary", m$source_sha256, as.list(children$summary_id)),
      level = "MEETING", parent_key = m$meeting_id, date = m$date, child_summary_ids = json_text(as.list(children$summary_id)),
      evidence_ids = json_text(as.list(ev)), method = "EXTRACTIVE")
  }
  parents <- rows_frame(parents, empty_parents())
  daily <- list()
  for (day in sort(unique(meetings$date))) {
    children <- parents[parents$date == day, ]; ev <- unique(unlist(lapply(children$evidence_ids, jsonlite::fromJSON), use.names = FALSE))
    daily[[length(daily) + 1L]] <- tibble::tibble(summary_id = stable_id("r_daily_summary", day, as.list(children$summary_id)),
      level = "DAILY", parent_key = day, date = day, child_summary_ids = json_text(as.list(children$summary_id)),
      evidence_ids = json_text(as.list(ev)), method = "EXTRACTIVE")
  }
  daily <- rows_frame(daily, empty_parents())
  verify_summaries(result, parents, daily, evidence)
  list(statements = result, meetings = parents, daily = daily)
}

# Segment 3 — Automated quotation and lineage verification.
verify_summaries <- function(summaries, meetings, daily, evidence) {
  assert(!anyDuplicated(evidence$evidence_id), "Duplicate evidence IDs.")
  for (i in seq_len(nrow(summaries))) {
    s <- summaries[i, ]; ids <- jsonlite::fromJSON(s$evidence_ids)
    assert(length(ids) > 0 && all(ids %in% evidence$evidence_id), "Missing summary evidence.")
    rows <- evidence[match(ids, evidence$evidence_id), ]
    assert(identical(s$text, paste(rows$text, collapse = " ")) && all(rows$statement_id == s$statement_id) &&
      all(rows$source_sha256 == s$source_sha256), "Unsupported or cross-speaker quotation.")
    assert(identical(rows$sentence_index, seq.int(min(rows$sentence_index), max(rows$sentence_index))), "Noncontiguous excerpt.")
  }
  check_parents <- function(parents, children, key) {
    for (i in seq_len(nrow(parents))) {
      p <- parents[i, ]; ids <- jsonlite::fromJSON(p$child_summary_ids)
      assert(all(ids %in% children$summary_id), "Missing child summary.")
      child <- children[match(ids, children$summary_id), ]
      assert(all(child[[key]] == p$parent_key), "Parent/child summary identity mismatch.")
      expected <- unique(unlist(lapply(child$evidence_ids, jsonlite::fromJSON), use.names = FALSE))
      actual <- jsonlite::fromJSON(p$evidence_ids)
      assert(identical(as.character(actual), as.character(expected)), "Summary evidence lineage mismatch.")
    }
  }
  check_parents(meetings, summaries, "meeting_id")
  check_parents(daily, meetings, "date")
  invisible(TRUE)
}
