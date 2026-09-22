# Segment 1 — Exact affiliation resolution. Do not infer a country from a person's name.
normalize_alias <- function(x) stringr::str_squish(stringi::stri_trans_casefold(stringi::stri_trans_nfkc(x)))
load_registry <- function(root) {
  countries <- readr::read_csv(file.path(root, "data/registries/country_registry.csv"), col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  aliases <- readr::read_csv(file.path(root, "data/registries/country_aliases.csv"), col_types = readr::cols(.default = "c"), show_col_types = FALSE)
  assert(!anyDuplicated(countries$entity_id) && all(aliases$entity_id %in% countries$entity_id), "Invalid country registry.")
  aliases <- aliases[aliases$alias_type != "iso_alpha2", ]
  aliases$key <- normalize_alias(aliases$alias)
  list(countries = countries, aliases = aliases)
}
resolve_country <- function(speaker, registry) {
  values <- normalize_alias(c(scalar_text(speaker$affiliation), scalar_text(speaker$affiliation_full)))
  values <- setdiff(values, c("", "ga", "sc", "un", "ecosoc", "hrc", "pga", "sg"))
  ids <- unique(registry$aliases$entity_id[registry$aliases$key %in% values])
  if (length(ids) == 1) return(list(id = ids, name = registry$countries$canonical_name[match(ids, registry$countries$entity_id)], method = "exact_structured_alias"))
  list(id = "", name = "", method = if (length(ids)) "ambiguous" else "unresolved")
}
duration_seconds <- function(x) {
  if (is.null(x)) return(NA_real_)
  if (is.numeric(x)) { assert(length(x) == 1 && is.finite(x) && x >= 0, "Invalid duration."); return(as.numeric(x)) }
  assert(grepl("^\\d+:[0-5]\\d:[0-5]\\d(?:\\.\\d+)?$", x), "Invalid duration string.")
  p <- as.numeric(strsplit(x, ":", fixed = TRUE)[[1]])
  p[1] * 3600 + p[2] * 60 + p[3]
}
match_topics <- function(text, config) {
  ids <- vapply(config$topics, function(t) if (grepl(t$pattern, text, ignore.case = TRUE, perl = TRUE)) t$id else "", character(1))
  ids[nzchar(ids)]
}

# Segment 2 — Normalize source sentences without rewriting, deleting or merging speakers.
# IDs bind evidence to source content and source JSON pointers.
parse_transcript <- function(source, item, config, registry) {
  assert(identical(sha_bytes(source$bytes), source$sha256), "Source hash changed before parsing.")
  doc <- jsonlite::fromJSON(rawToChar(source$bytes), simplifyVector = FALSE)
  video <- doc$video; tr <- doc$transcript
  assert(is.list(video) && identical(video$slug, item$slug) && substr(scalar_text(video$date), 1, 10) == item$date,
    "Detail/inventory identity mismatch.")
  assert(nzchar(scalar_text(video$id)), "Missing video ID.")
  assert(!is.null(tr), "Advertised transcript missing in detail.")
  if (!identical(tr$language, config$locale)) return(list(unavailable_language = TRUE))
  assert(is.list(tr$data) && length(tr$data) > 0, "Empty transcript data.")
  assert(nzchar(scalar_text(doc$disclaimer)), "Missing automatic transcript disclaimer.")
  duration <- duration_seconds(video$duration)
  source_warning <- isTRUE(tr$timestamps_flagged)
  meeting_id <- paste0("asset/", video$id)
  statements <- list(); evidence <- list(); numbers <- integer()
  for (i in seq_along(tr$data)) {
    s <- tr$data[[i]]
    assert(is_whole(s$statement_number) && s$statement_number > 0 && !s$statement_number %in% numbers,
      "Invalid or duplicate statement number.")
    numbers <- c(numbers, s$statement_number)
    assert(is.list(s$paragraphs) && length(s$paragraphs) > 0, "Missing statement paragraphs.")
    sid <- paste0(substr(source$sha256, 1, 16), ":s", s$statement_number)
    pointer <- paste0("/transcript/data/", i - 1L)
    source_url(s$pageUrl)
    # A source deep link must identify the same meeting.
    assert(identical(strsplit(source_url(s$pageUrl), "?", fixed = TRUE)[[1]][1], item$page_url), "Statement URL points to another meeting.")
    ev <- list(); j <- 0L
    for (p in seq_along(s$paragraphs)) {
      sentences <- s$paragraphs[[p]]$sentences
      assert(is.list(sentences) && length(sentences) > 0, "Empty paragraph sentences.")
      for (k in seq_along(sentences)) {
        sentence <- sentences[[k]]
        text <- scalar_text(sentence$text)
        assert(is.numeric(sentence$start) && length(sentence$start) == 1 && is.finite(sentence$start) &&
          is.numeric(sentence$end) && length(sentence$end) == 1 && is.finite(sentence$end) &&
          sentence$start >= 0 && sentence$end >= sentence$start, "Invalid source sentence timing.")
        ev[[length(ev) + 1L]] <- tibble::tibble(evidence_id = paste0(sid, ":", j), statement_id = sid,
          sentence_index = j, text = text, start_seconds = as.numeric(sentence$start), end_seconds = as.numeric(sentence$end),
          source_sha256 = source$sha256, source_path = source$path,
          source_pointer = paste0(pointer, "/paragraphs/", p - 1L, "/sentences/", k - 1L),
          source_url = paste0(item$page_url, "?t=", ceiling(sentence$start)))
        j <- j + 1L
      }
    }
    ev <- dplyr::bind_rows(ev)
    assert(any(nzchar(trimws(ev$text))), "Empty source statement.")
    sp <- s$speaker %||% list()
    assert(is.list(sp), "Speaker must be an object or null.")
    country <- resolve_country(sp, registry)
    label <- c(scalar_text(sp$name), scalar_text(sp$affiliation_full), scalar_text(sp[["function"]]), "Unidentified speaker")
    text <- paste(ev$text, collapse = " ")
    topics <- match_topics(text, config)
    topic_ok <- !length(config$topics) || length(topics) > 0
    statements[[length(statements) + 1L]] <- tibble::tibble(statement_id = sid, meeting_id = meeting_id,
      slug = item$slug, date = item$date, statement_number = as.integer(s$statement_number),
      speaker_label = label[nzchar(label)][1], speaker_role = scalar_text(sp[["function"]]), affiliation = scalar_text(sp$affiliation),
      affiliation_full = scalar_text(sp$affiliation_full), speaker_json = json_text(s$speaker), country_entity_id = country$id,
      country_name = country$name, resolution_method = country$method, text = text, word_count = as.integer(word_count(text)),
      source_sha256 = source$sha256, source_path = source$path, source_url = source_url(s$pageUrl), source_pointer = pointer,
      start_seconds = min(ev$start_seconds), end_seconds = max(ev$end_seconds),
      timing_warning = source_warning || (!is.na(duration) && any(ev$end_seconds > duration + 2)),
      topics = paste(topics, collapse = ";"), topic_match = topic_ok)
    evidence[[length(evidence) + 1L]] <- ev
  }
  statements <- dplyr::bind_rows(statements)
  meeting <- tibble::tibble(meeting_id = meeting_id, slug = item$slug, title = scalar_text(video$title, item$title),
    date = item$date, category = item$category, source_sha256 = source$sha256, source_url = item$page_url,
    source_path = source$path, source_type = "automatic_transcript", language = tr$language,
    statement_count = nrow(statements), timing_warning = any(statements$timing_warning),
    timing_note = scalar_text(tr$timestamps_note, if (any(statements$timing_warning)) "Some timestamps exceed the listed recording duration." else ""))
  list(unavailable_language = FALSE, meetings = meeting, statements = statements, evidence = dplyr::bind_rows(evidence))
}
