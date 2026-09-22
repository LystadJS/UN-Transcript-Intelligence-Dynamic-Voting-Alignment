# Segment 1 — Email-safe HTML. All source text is escaped; no external resources.
esc <- function(x) as.character(htmltools::htmlEscape(as.character(x), attribute = TRUE))
html_link <- function(url, label) paste0('<a href="', esc(url), '" style="color:#234b70;text-decoration:underline;">', esc(label), '</a>')
format_status <- function(x) switch(x, COLLECTED = "Collected", NO_TRANSCRIPT = "Transcript unavailable",
  UNAVAILABLE_LANGUAGE = "English transcript unavailable", EXCLUDED_CATEGORY = "Outside selected categories",
  FAILED = "Retrieval or validation failed", COLLECTED_TXT_FAILED = "JSON collected; TXT unavailable", x)
create_full_report <- function(ctx, inventory, meetings, statements, summaries, manifest) {
  c <- ctx$config
  dates <- paste(range(ctx$dates), collapse = " to ")
  if (length(ctx$dates) == 1) dates <- ctx$dates
  headline <- paste(c$email$subject_prefix, dates, sep = " | ")
  title <- if (manifest$status == "COMPLETE") "UN Transcript Digest" else "UN Transcript Digest — Partial collection"
  n_collected <- nrow(meetings); n_scope <- sum(inventory$in_scope)
  n_unavailable <- sum(inventory$status %in% c("NO_TRANSCRIPT", "UNAVAILABLE_LANGUAGE"))
  n_failed <- sum(inventory$status %in% c("FAILED", "COLLECTED_TXT_FAILED"))
  topic_text <- if (!length(c$topics)) "All topics" else paste(vapply(c$topics, function(t) t$label %||% t$id, character(1)), collapse = "; ")
  parts <- c('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>', esc(headline),
    '</title></head><body style="margin:0;background:#edf1f4;color:#233241;font-family:Inter,Arial,sans-serif;font-size:15px;line-height:1.55;">',
    '<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="padding:24px 12px;">',
    '<table role="presentation" width="760" cellspacing="0" cellpadding="0" style="width:100%;max-width:760px;background:white;border:1px solid #d8e0e7;"><tr><td style="padding:30px 32px 22px;background:#142c43;color:white;">',
    '<div style="font-size:11px;letter-spacing:2px;color:#c6d5df;">PUBLIC UN TRANSCRIPTS · EMAIL PREVIEW</div>',
    '<h1 style="font-family:Garamond,Georgia,serif;font-size:32px;line-height:1.2;margin:9px 0;">', esc(title), '</h1>',
    '<div style="color:#dae3ea;">', esc(dates), ' · English</div></td></tr>',
    '<tr><td style="padding:24px 32px;">',
    '<div style="font-size:12px;color:#526779;margin-bottom:18px;">From: ', esc(c$email$from),
    ' &nbsp; | &nbsp; To: ', esc(if (nzchar(c$email$to)) c$email$to else 'Not configured — preview only'), '</div>',
    '<table role="presentation" width="100%" cellspacing="0" cellpadding="10" style="background:#f0f4f7;border-left:4px solid #8d2636;"><tr><td>',
    '<strong>', n_collected, ' collected</strong> / ', n_scope, ' in scope &nbsp; · &nbsp; ', n_unavailable,
    ' unavailable &nbsp; · &nbsp; ', n_failed, ' failed or incomplete',
    '<br><span style="font-size:12px;">', nrow(statements), ' source statements · ', esc(topic_text), '</span></td></tr></table>',
    '<p style="font-size:13px;color:#526779;">Selected verbatim passages from automatically generated UN transcripts. These are not official UN records. Selection is lexical and not exhaustive; speaker labels and timestamps come from the source.</p>')
  if (!all(vapply(ctx$day_records, function(d) isTRUE(d$inventory_complete), logical(1)))) {
    parts <- c(parts, '<p style="padding:12px;background:#fff1d9;border:1px solid #dbb777;"><strong>Incomplete inventory:</strong> totals above count discovered rows only. This run cannot establish complete meeting coverage.</p>')
  }
  for (day in ctx$dates) {
    parts <- c(parts, '<h2 style="font-family:Garamond,Georgia,serif;font-size:25px;border-bottom:2px solid #dce4eb;padding-bottom:8px;margin-top:28px;">', esc(day), '</h2>')
    daymeetings <- meetings[meetings$date == day, ]
    if (!nrow(daymeetings)) parts <- c(parts, '<p>No usable transcripts were collected for this date. See coverage below.</p>')
    for (i in seq_len(nrow(daymeetings))) {
      m <- daymeetings[i, ]; parent <- summaries$meetings[summaries$meetings$parent_key == m$meeting_id, ]
      children <- jsonlite::fromJSON(parent$child_summary_ids)
      picks <- summaries$statements[match(children, summaries$statements$summary_id), ]
      parts <- c(parts, '<div style="margin:22px 0 30px;">',
        '<div style="font-size:11px;text-transform:uppercase;letter-spacing:1px;color:#64788a;">', esc(m$category), '</div>',
        '<h3 style="font-size:18px;line-height:1.35;margin:5px 0 7px;">', html_link(m$source_url, m$title), '</h3>',
        '<div style="font-size:12px;color:#64788a;">', m$statement_count, ' statements · ', nrow(picks), ' selected passages</div>')
      if (m$timing_warning) parts <- c(parts, '<p style="font-size:12px;padding:9px 12px;background:#fff4df;color:#795619;"><strong>Timing warning:</strong> ', esc(m$timing_note), ' Video links may not align with the excerpt.</p>')
      if (!nrow(picks)) parts <- c(parts, '<p style="color:#64788a;">No statements matched the configured screening terms. This does not establish that the topic was absent.</p>')
      for (j in seq_len(nrow(picks))) {
        s <- picks[j, ]; label <- paste(unique(c(s$speaker_label, s$affiliation_full)[nzchar(c(s$speaker_label, s$affiliation_full))]), collapse = ' · ')
        parts <- c(parts, '<div style="margin:17px 0;">', '<strong style="font-size:13px;">', esc(label), '</strong>',
          '<blockquote style="margin:7px 0;padding:4px 0 4px 14px;border-left:3px solid #b6c8d6;color:#233241;">', esc(s$text), '</blockquote>',
          '<div style="font-size:11px;">', html_link(s$source_url, 'Source passage'),
          ' <span style="color:#64788a;">· ', esc(s$statement_id), '</span></div></div>')
      }
      parts <- c(parts, '</div>')
    }
  }
  parts <- c(parts, '<h2 style="font-family:Garamond,Georgia,serif;font-size:25px;border-top:2px solid #dce4eb;padding-top:20px;">Coverage and gaps</h2>',
    '<p style="font-size:12px;color:#64788a;">Coverage refers to the UN Transcripts inventory, not every UN meeting. Entries without transcripts remain visible. The default request includes other-language availability.</p>',
    '<table width="100%" cellspacing="0" cellpadding="8" style="border-collapse:collapse;font-size:12px;"><tr style="background:#eef3f7;text-align:left;"><th>Date / meeting</th><th style="width:27%;">Status</th></tr>')
  for (i in seq_len(nrow(inventory))) {
    item <- inventory[i, ]
    parts <- c(parts, '<tr><td style="border-bottom:1px solid #e2e8ed;vertical-align:top;">', esc(item$date), '<br>', html_link(item$page_url, item$title),
      '</td><td style="border-bottom:1px solid #e2e8ed;vertical-align:top;">', esc(format_status(item$status)), '</td></tr>')
  }
  parts <- c(parts, '</table>')
  if (length(ctx$errors)) {
    parts <- c(parts, '<p style="font-size:12px;color:#8d2636;"><strong>', length(ctx$errors), ' collection/processing errors recorded.</strong> See manifest.json for stage, date and source details.</p>')
  }
  parts <- c(parts, '<p style="font-size:11px;color:#64788a;margin-top:24px;">Run ', esc(ctx$run_id),
    ' · Generated ', esc(utc_now()), '<br>Method: extractive selection. Quotes checked against archived source sentences. Transcription accuracy and speaker identity have not been independently verified.</p>',
    '</td></tr></table></td></tr></table></body></html>')
  html <- paste(parts, collapse = "")
  path <- file.path(ctx$run_dir, "full-report.html"); write_utf8(html, path)
  list(path = path, subject = headline, html = html)
}
