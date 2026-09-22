# Segment 1 — Compact briefing; full extractive detail remains a separate report.
brief_heading <- function(number, title) paste0('<h2 style="font-family:Garamond,Georgia,serif;font-size:24px;line-height:1.2;color:#742f3c;margin:25px 0 12px;">',
  '<span style="font-family:Inter,Arial,sans-serif;font-size:11px;color:#77716b;">', number, ' &nbsp; </span>', esc(title), '</h2>')
meeting_picks <- function(meeting_id, summaries) {
  parent <- summaries$meetings[summaries$meetings$parent_key == meeting_id, ]
  assert(nrow(parent) == 1L, "Missing/ambiguous meeting-summary parent.")
  ids <- jsonlite::fromJSON(parent$child_summary_ids)
  picks <- summaries$statements[match(ids, summaries$statements$summary_id), ]
  assert(!anyNA(picks$summary_id), "Missing statement-summary child.")
  picks
}
brief_excerpt <- function(s) {
  label <- paste(unique(c(s$speaker_label, s$affiliation_full)[nzchar(c(s$speaker_label, s$affiliation_full))]), collapse = " · ")
  paste0('<div style="margin:14px 0 18px;"><strong style="font-size:13px;">', esc(label), '</strong>',
    '<blockquote style="margin:6px 0 8px;padding-left:14px;border-left:2px solid #baa1a7;">', esc(s$text), '</blockquote>',
    '<div style="font-size:12px;">', html_link(s$source_url, "Read source passage"),
    if (isTRUE(s$timing_warning)) ' · <span style="color:#795619;">Timestamp alignment warning</span>' else '', '</div></div>')
}
brief_panel <- function(panel, inline = TRUE) {
  title <- if (panel$track == "statements") "Expressed positions" else "Voting alignment"
  p <- c('<div class="model-panel" style="border:1px solid #dcd7d0;background:#faf9f6;padding:15px;margin:12px 0;">',
    '<strong>', title, '</strong><br><span style="font-size:12px;color:#742f3c;">', esc(panel$status),
    if (identical(panel$data_kind, "SYNTHETIC")) ' · SYNTHETIC ENGINEERING EXAMPLE' else '', '</span>',
    '<p style="font-size:13px;">', esc(panel$message), '</p>')
  if (!is.null(panel$figure)) {
    src <- if (inline) paste0("data:image/png;base64,", gsub("[\r\n]", "", jsonlite::base64_enc(read_bytes(panel$figure$path)))) else paste0("cid:", panel$figure$cid)
    p <- c(p, '<p style="font-size:12px;">', esc(panel$issue_label), ' · Periods: ', esc(paste(panel$periods, collapse = ", ")),
      '<br>Data as of ', esc(panel$data_as_of), ' · Age at report cutoff: ', panel$age_days, ' days</p>',
      '<img src="', src, '" alt="', esc(panel$figure$alt), '" width="636" style="display:block;width:100%;max-width:636px;height:auto;">',
      '<p style="font-size:12px;color:#686762;">', esc(panel$figure$caption), '</p>')
    if (!is.null(panel$comparison) && nrow(panel$comparison)) {
      rows <- panel$comparison
      p <- c(p, '<p style="font-size:12px;"><strong>Change in distance to ', esc(rows$reference_entity[1]),
        '</strong> · Latest adjacent period pair</p><table width="100%" cellpadding="5" cellspacing="0" style="width:100%;font-size:12px;border-collapse:collapse;"><tr style="text-align:left;"><th style="width:65%;padding:5px 8px;border-bottom:1px solid #dedbd5;">Entity</th><th style="padding:5px 8px;border-bottom:1px solid #dedbd5;">Change</th></tr>')
      for (i in seq_len(nrow(rows))) p <- c(p, '<tr><td style="padding:5px 8px;">', esc(rows$entity[i]), '</td><td style="padding:5px 8px;">', sprintf("%+.3f", if (abs(rows$change[i]) < 0.0005) 0 else rows$change[i]), '</td></tr>')
      p <- c(p, '</table><p style="font-size:11px;color:#686762;">Up to five paired entities in identifier order; not an importance ranking. Units: ', esc(panel$coordinate_units),
        '. Values rounded to three decimals. Negative means closer relative to the reference, which may itself move. This does not establish increased policy support.</p>')
    }
  }
  paste(c(p, '</div>'), collapse = "")
}

# Segment 2 — RFC MIME preview with text alternative, CID images and full report.
# Building the message is intentionally separate from any future delivery adapter.
mime_base64 <- function(bytes) {
  value <- gsub("[\r\n]", "", jsonlite::base64_enc(bytes))
  if (!nzchar(value)) return("")
  starts <- seq.int(1L, nchar(value), by = 76L)
  paste(substring(value, starts, pmin(starts + 75L, nchar(value))), collapse = "\r\n")
}
write_briefing_mime <- function(ctx, subject, html, plain, panels, full_report) {
  c <- ctx$config$email
  for (value in c(c$from, c$to, subject)) assert(!grepl("[\r\n]", value), "Unsafe email header.")
  token <- gsub("[^A-Za-z0-9]", "", ctx$run_id)
  mixed <- paste0("mix", token); alternative <- paste0("alt", token); related <- paste0("rel", token)
  part <- function(type, bytes, extra = character()) c(paste0("Content-Type: ", type),
    "Content-Transfer-Encoding: base64", extra, "", mime_base64(bytes))
  message <- c(paste0("From: ", c$from), if (nzchar(c$to)) paste0("To: ", c$to),
    paste0("Subject: =?UTF-8?B?", gsub("[\r\n]", "", jsonlite::base64_enc(charToRaw(enc2utf8(subject)))), "?="),
    "MIME-Version: 1.0", 'X-UN-Transcript-Mode: preview',
    paste0('Content-Type: multipart/mixed; boundary="', mixed, '"'), "", paste0("--", mixed),
    paste0('Content-Type: multipart/alternative; boundary="', alternative, '"'), "", paste0("--", alternative),
    part('text/plain; charset=UTF-8', charToRaw(enc2utf8(plain))), paste0("--", alternative),
    paste0('Content-Type: multipart/related; boundary="', related, '"'), "", paste0("--", related),
    part('text/html; charset=UTF-8', charToRaw(enc2utf8(html))))
  for (panel in panels) if (!is.null(panel$figure)) {
    message <- c(message, paste0("--", related), part("image/png", read_bytes(panel$figure$path),
      c(paste0("Content-ID: <", panel$figure$cid, ">"),
        paste0('Content-Disposition: inline; filename="', panel$track, '-movement.png"'))))
  }
  message <- c(message, paste0("--", related, "--"), paste0("--", alternative, "--"),
    paste0("--", mixed), part('text/html; charset=UTF-8', read_bytes(full_report),
      'Content-Disposition: attachment; filename="full-report.html"'), paste0("--", mixed, "--"), "")
  write_utf8(paste(message, collapse = "\r\n"), file.path(ctx$run_dir, "email-preview.eml"))
}

# Segment 3 — Public entry point used by live, replay, empty and partial runs.
create_preview <- function(ctx, inventory, meetings, statements, summaries, manifest) {
  full <- create_full_report(ctx, inventory, meetings, statements, summaries, manifest)
  config <- ctx$config
  limits <- config$report %||% list(headline_excerpts = 3L, meeting_cards = 4L)
  panels <- lapply(c("statements", "votes"), function(track) load_drift_panel(ctx$root, config$models[[track]],
    track, max(ctx$dates), ctx$run_dir))
  write_json(panels, file.path(ctx$run_dir, "model-status.json"))
  dates <- paste(range(ctx$dates), collapse = " to "); if (length(ctx$dates) == 1L) dates <- ctx$dates
  subject <- paste(config$email$subject_prefix, dates, sep = " | ")
  picked <- lapply(meetings$meeting_id, meeting_picks, summaries = summaries)
  # Round-robin across meetings, preserving original selected-child order.
  headlines <- list()
  if (length(picked)) for (j in seq_len(max(c(0L, vapply(picked, nrow, integer(1)))))) {
    for (i in seq_along(picked)) if (nrow(picked[[i]]) >= j && length(headlines) < limits$headline_excerpts) {
      headlines[[length(headlines) + 1L]] <- picked[[i]][j, ]
    }
  }
  n_unavailable <- sum(inventory$status %in% c("NO_TRANSCRIPT", "UNAVAILABLE_LANGUAGE"))
  n_failed <- sum(inventory$status %in% c("FAILED", "COLLECTED_TXT_FAILED"))
  parts <- c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
    '<title>', esc(subject), '</title><style>@media screen and (max-width:540px){.inner{padding:22px 16px!important}.outer{padding:12px 6px!important}}',
    '@media print{h2,h3{break-after:avoid}.model-panel,blockquote{break-inside:avoid}}</style></head>',
    '<body style="margin:0;background:#f3f1ed;color:#292d30;font-family:Inter,Arial,sans-serif;font-size:15px;line-height:1.55;">',
    '<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td class="outer" align="center" style="padding:28px 12px;">',
    '<table role="presentation" width="700" cellspacing="0" cellpadding="0" style="width:100%;max-width:700px;background:white;border:1px solid #dedbd5;border-top:4px solid #742f3c;"><tr><td class="inner" style="padding:28px 32px;">',
    '<div style="font-size:11px;letter-spacing:1.5px;color:#742f3c;">PUBLIC UN TRANSCRIPTS · EMAIL PREVIEW</div>',
    if (any(vapply(panels, function(p) identical(p$data_kind, "SYNTHETIC"), logical(1)))) '<p style="padding:10px;background:#fff1d9;font-size:13px;"><strong>SYNTHETIC MODEL DEMONSTRATION.</strong> The movement figure is an engineering fixture, not a UN opinion-change result.</p>' else '',
    '<h1 style="font-family:Garamond,Georgia,serif;font-size:36px;line-height:1.1;font-weight:normal;margin:12px 0;">UN Daily Meeting Intelligence</h1>',
    '<p style="font-size:13px;color:#686762;">Reporting dates: ', esc(dates), ' · English<br>Date basis: ', esc(config$timezone),
    '<br>From: ', esc(config$email$from), ' · To: ', esc(if (nzchar(config$email$to)) config$email$to else "Unconfigured — preview only"), '</p>',
    '<div style="padding:12px 14px;background:#f5f3ef;border-top:1px solid #dedbd5;border-bottom:1px solid #dedbd5;font-size:13px;"><strong>',
    nrow(inventory), ' discovered · ', sum(inventory$in_scope), ' in scope · ', nrow(meetings), ' collected</strong><br>',
    n_unavailable, ' unavailable · ', n_failed, ' failed or incomplete · ', nrow(statements), ' statements</div>')
  if (!all(vapply(ctx$day_records, function(x) isTRUE(x$inventory_complete), logical(1)))) {
    parts <- c(parts, '<p style="padding:12px;background:#fff1d9;"><strong>Incomplete inventory.</strong> Counts include discovered entries only and do not establish complete coverage.</p>')
  }
  parts <- c(parts, brief_heading("01", "Selected transcript excerpts"),
    '<p style="font-size:13px;">Verbatim, lexically selected passages in round-robin meeting order. They are not ranked by political importance. Analytical executive assessment is not yet implemented.</p>')
  if (!length(headlines)) parts <- c(parts, '<p>No eligible excerpts. This does not establish that relevant developments were absent.</p>')
  for (s in headlines) parts <- c(parts, brief_excerpt(s))
  parts <- c(parts, brief_heading("02", "U.S. Mission Relevance"),
    '<p>Not assessed in this extractive release.</p>', brief_heading("03", "Cross-Meeting Developments"),
    '<p>Not synthesized in this extractive release.</p>', brief_heading("04", "Meeting Summaries"))
  chosen_ids <- if (length(headlines)) vapply(headlines, function(s) s$summary_id, character(1)) else character()
  if (!nrow(meetings)) parts <- c(parts, '<p>No usable transcripts collected. See coverage below.</p>')
  for (i in seq_len(min(nrow(meetings), limits$meeting_cards))) {
    m <- meetings[i, ]; picks <- picked[[i]]
    parts <- c(parts, '<h3 style="font-size:16px;margin-bottom:5px;">', html_link(m$source_url, m$title), '</h3>',
      '<p style="font-size:12px;color:#686762;margin:0;">', esc(m$date), ' · ', esc(m$category), ' · ', m$statement_count, ' statements</p>')
    if (isTRUE(m$timing_warning)) parts <- c(parts, '<p style="font-size:12px;color:#795619;">Timestamp alignment warning: ', esc(m$timing_note), '</p>')
    unseen <- picks[!picks$summary_id %in% chosen_ids, ]
    if (nrow(unseen)) parts <- c(parts, brief_excerpt(unseen[1, ])) else parts <- c(parts,
      '<p style="font-size:13px;">', if (nrow(picks)) "Selected passage appears above." else "No selected passage matched the configured screening terms.", '</p>')
  }
  full_index <- length(parts) + 1L
  model_index <- length(parts) + 3L
  parts <- c(parts, '<p style="font-size:13px;">{{FULL_REPORT}}</p>', brief_heading("05", "Position and Voting Updates"), '{{MODEL_PANELS}}',
    brief_heading("06", "Coverage and QA"),
    '<p style="font-size:12px;">Coverage is the UN Transcripts inventory, not a census of every UN meeting. All discovered entries are retained below.</p>',
    '<table width="100%" cellpadding="7" cellspacing="0" style="border-collapse:collapse;font-size:12px;"><tr style="background:#f5f3ef;text-align:left;"><th>Date / meeting</th><th>Status</th></tr>')
  for (i in seq_len(nrow(inventory))) {
    r <- inventory[i, ]
    parts <- c(parts, '<tr><td style="border-bottom:1px solid #e8e4df;vertical-align:top;">', esc(r$date), '<br>', html_link(r$page_url, r$title),
      '</td><td style="border-bottom:1px solid #e8e4df;vertical-align:top;">', esc(format_status(r$status)), '</td></tr>')
  }
  parts <- c(parts, '</table><p style="font-size:12px;color:#686762;">Automatic transcripts are not official UN records. Quotations are checked against archived source text, not independently verified speech. Speaker identity has not been independently verified. ',
    sum(meetings$timing_warning), ' recordings carry timestamp alignment warnings. ', length(ctx$errors), ' collection/processing errors recorded.</p>',
    '<p style="font-size:11px;color:#77716b;border-top:1px solid #dedbd5;padding-top:14px;">Run ', esc(ctx$run_id), ' · Collection: ', esc(manifest$status),
    '<br>Generated ', esc(utc_now()), ' · Release ', esc(config$project_version), ' · No message sent</p></td></tr></table></td></tr></table></body></html>')
  # Replace by structural position, never by searching untrusted source text.
  preview_parts <- parts; outgoing_parts <- parts
  preview_parts[full_index] <- '<p style="font-size:13px;"><a href="full-report.html" style="color:#31566b;">Open full extractive report</a> — all meetings and selected passages.</p>'
  outgoing_parts[full_index] <- '<p style="font-size:13px;">Full extractive report attached — all meetings and selected passages.</p>'
  preview_parts[model_index] <- paste(vapply(panels, brief_panel, character(1), inline = TRUE), collapse = "")
  outgoing_parts[model_index] <- paste(vapply(panels, brief_panel, character(1), inline = FALSE), collapse = "")
  preview <- paste(preview_parts, collapse = "\n")
  outgoing <- paste(outgoing_parts, collapse = "\n")
  path <- file.path(ctx$run_dir, "email-preview.html")
  write_utf8(preview, path)
  write_utf8(outgoing, file.path(ctx$run_dir, "email-body.html"))
  plain <- paste(c(subject, paste(nrow(meetings), "collected;", n_unavailable, "unavailable;", n_failed, "failed/incomplete."),
    "Selected transcript excerpts (not an analytical assessment):",
    unlist(lapply(headlines, function(s) c(s$speaker_label, s$text, s$source_url))),
    "U.S. Mission Relevance: not assessed. Cross-Meeting Developments: not synthesized.",
    vapply(panels, function(p) paste(p$track, p$status, p$message, sep = ": "), character(1)),
    "Full extractive report attached. Automatic transcript and attribution limitations apply. No email sent."), collapse = "\n\n")
  write_utf8(plain, file.path(ctx$run_dir, "email-preview.txt"))
  write_briefing_mime(ctx, subject, outgoing, plain, panels, full$path)
  list(path = path, subject = subject, html_bytes = nchar(preview, type = "bytes"), full_report = full$path,
    model_status = stats::setNames(lapply(panels, function(p) p$status), c("statements", "votes")),
    mode = "PREVIEW_ONLY", sent = FALSE)
}
