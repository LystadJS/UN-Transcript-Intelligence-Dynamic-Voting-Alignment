# Segment 1 — Explicit, evidence-linked input contract for prepared 2-D maps.
# This adapter does not estimate stances, embeddings, uncertainty or political blocs.
drift_supported_version <- "0.0.5.9000"
drift_required_text <- function(x, field) {
  value <- scalar_text(x[[field]])
  assert(nzchar(trimws(value)), paste("Missing specification field:", field))
  value
}
drift_https <- function(x) {
  u <- httr2::url_parse(x)
  assert(identical(u$scheme, "https") && nzchar(u$hostname %||% "") &&
    !nzchar(u$username %||% "") && !nzchar(u$password %||% "") &&
    !grepl("[[:space:]\\\\]", x), "Evidence URLs must be credential-free HTTPS URLs.")
  invisible(x)
}
read_drift_inputs <- function(coordinates_path, evidence_path, specification_path) {
  spec <- yaml::read_yaml(specification_path)
  assert(identical(spec$schema_version, 1L), "Unsupported drift input schema.")
  for (field in c("track", "issue_id", "issue_label", "data_kind", "data_as_of",
                 "measurement_version", "measurement_description", "preprocessing",
                 "coordinate_units", "frame_justification")) drift_required_text(spec, field)
  assert(spec$track %in% c("statements", "votes"), "Track must be statements or votes.")
  assert(spec$data_kind %in% c("OBSERVED", "SYNTHETIC"), "data_kind must be OBSERVED or SYNTHETIC.")
  spec$data_as_of <- validate_day(spec$data_as_of)
  periods <- unlist(spec$periods, use.names = FALSE)
  assert(is.character(periods) && length(periods) >= 2L && length(periods) <= 12L &&
    !anyDuplicated(periods), "Supply 2..12 unique, ordered ISO-date periods, including every scheduled period.")
  periods <- vapply(periods, validate_day, character(1), USE.NAMES = FALSE)
  assert(all(diff(as.Date(periods)) > 0) && max(periods) <= spec$data_as_of, "Periods must increase and end on/before data_as_of.")
  spec$periods <- periods
  spec$reference <- spec$reference %||% "previous"
  assert(spec$reference %in% c("previous", "first"), "reference must be previous or first.")
  spec$scale <- spec$scale %||% FALSE
  assert(identical(spec$scale, FALSE), "Adapter 0.2.0 fixes scale=FALSE to retain coordinate units.")
  spec$anchors <- unlist(spec$anchors %||% character(), use.names = FALSE)
  assert(is.character(spec$anchors) && !anyNA(spec$anchors) && !anyDuplicated(spec$anchors), "Invalid anchor IDs.")
  spec$label_entities <- unlist(spec$label_entities %||% character(), use.names = FALSE)
  assert(is.character(spec$label_entities) && length(spec$label_entities) <= 12L, "Choose at most 12 label_entities.")
  spec$distance_reference <- scalar_text(spec$distance_reference)
  pos <- readr::read_csv(coordinates_path, col_types = readr::cols(.default = readr::col_character(),
    x = readr::col_double(), y = readr::col_double()), show_col_types = FALSE)
  assert(nrow(readr::problems(pos)) == 0L, "Coordinate CSV has parsing problems.")
  assert(all(c("country_id", "period", "x", "y", "evidence_ids") %in% names(pos)) && nrow(pos) > 0L,
    "Coordinates need country_id, period, x, y, evidence_ids.")
  assert(!anyNA(pos[c("country_id", "period", "x", "y", "evidence_ids")]) &&
    all(nzchar(trimws(pos$country_id))) && all(is.finite(pos$x)) && all(is.finite(pos$y)), "Invalid/missing coordinates or identifiers.")
  assert(!anyDuplicated(pos[c("country_id", "period")]), "Duplicate country-period rows.")
  assert(setequal(unique(pos$period), periods), "Observed periods must match the complete declared schedule; no missing periods.")
  ids <- unique(pos$country_id)
  if (!"country_name" %in% names(pos)) pos$country_name <- pos$country_id
  assert(!anyNA(pos$country_name) && all(nzchar(trimws(pos$country_name))), "Blank country display name.")
  assert(all(vapply(split(pos$country_name, pos$country_id), function(x) length(unique(x)) == 1L, logical(1))),
    "Country display names must be consistent across periods.")
  assert(all(spec$anchors %in% ids) && all(spec$label_entities %in% ids), "Unknown anchor or label entity.")
  evidence <- readr::read_csv(evidence_path, col_types = readr::cols(.default = readr::col_character()), show_col_types = FALSE)
  assert(nrow(readr::problems(evidence)) == 0L && all(c("evidence_id", "source_url") %in% names(evidence)) && nrow(evidence) > 0L,
    "Evidence needs evidence_id and source_url.")
  assert(!anyNA(evidence[c("evidence_id", "source_url")]) && !anyDuplicated(evidence$evidence_id) &&
    all(nzchar(evidence$evidence_id)), "Evidence IDs must be unique and nonblank.")
  invisible(lapply(evidence$source_url, drift_https))
  linked <- lapply(pos$evidence_ids, function(x) {
    assert(grepl("^\\s*\\[", x), "evidence_ids must be a JSON array.")
    v <- jsonlite::fromJSON(x)
    assert(is.character(v) && length(v) > 0L && !anyNA(v) && !anyDuplicated(v) && all(v %in% evidence$evidence_id),
      "Every coordinate row needs resolvable, unique evidence IDs.")
    v
  })
  pos$n_evidence <- lengths(linked)
  list(spec = spec, positions = pos, evidence = evidence)
}

# Segment 2 — Fit once, preserve diagnostics, and commit an immutable artifact.
build_drift_artifact <- function(coordinates_path, evidence_path, specification_path, output_dir) {
  assert(!dir.exists(output_dir) && !file.exists(output_dir), "Use a new output directory; existing model artifacts are immutable.")
  assert(requireNamespace("driftmapR", quietly = TRUE), "driftmapR missing. Run setup_driftmapR.R.")
  assert(identical(as.character(utils::packageVersion("driftmapR")), drift_supported_version),
    paste("Adapter tested only with driftmapR", drift_supported_version, "- install the bundled prototype."))
  inputs <- list(coordinates = coordinates_path, evidence = evidence_path, specification = specification_path)
  input_hashes <- lapply(inputs, sha_file)
  input <- read_drift_inputs(coordinates_path, evidence_path, specification_path)
  assert(identical(input_hashes, lapply(inputs, sha_file)), "Inputs changed while being read.")
  spec <- input$spec; pos <- input$positions
  xy <- data.frame(entity = pos$country_id, time = pos$period, x = pos$x, y = pos$y)
  fit <- driftmapR::drift_data(xy, periods = spec$periods,
    embedding_metadata = list(measurement_version = spec$measurement_version, preprocessing = spec$preprocessing))
  anchors <- if (length(spec$anchors)) spec$anchors else NULL
  driftmapR::validate_drift_data(fit, check_overlap = TRUE, reference = spec$reference, anchors = anchors)
  fit <- driftmapR::align_snapshots(fit, reference = spec$reference, scale = FALSE, anchors = anchors)
  movement <- driftmapR::measure_drift(fit)
  movement$track <- spec$track; movement$issue_id <- spec$issue_id
  movement$uncertainty_status <- "NOT_ESTIMATED"
  ids <- sort(unique(pos$country_id))
  comparisons <- lapply(seq_len(length(spec$periods) - 1L), function(i) {
    a <- spec$periods[i]; b <- spec$periods[i + 1L]
    before <- pos[pos$period == a, ]; after <- pos[pos$period == b, ]
    from <- ids %in% before$country_id; to <- ids %in% after$country_id
    data.frame(country_id = ids, period_from = a, period_to = b,
      status = ifelse(from & to, "PAIRED", ifelse(from, "EXITED", ifelse(to, "ENTERED", "UNOBSERVED"))),
      n_evidence_from = ifelse(from, before$n_evidence[match(ids, before$country_id)], NA_integer_),
      n_evidence_to = ifelse(to, after$n_evidence[match(ids, after$country_id)], NA_integer_))
  }) |> dplyr::bind_rows()
  distances <- NULL
  if (nzchar(spec$distance_reference)) {
    ref <- driftmapR::distance_to_anchor(fit, spec$distance_reference)
    distances <- movement[c("entity", "time_from", "time_to")]
    key <- paste(ref$entity, ref$time, sep = "\r")
    distances$distance_from <- ref$distance[match(paste(distances$entity, distances$time_from, sep = "\r"), key)]
    distances$distance_to <- ref$distance[match(paste(distances$entity, distances$time_to, sep = "\r"), key)]
    distances$change <- distances$distance_to - distances$distance_from
    distances$reference_entity <- spec$distance_reference
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  complete <- FALSE
  on.exit({ if (!complete) write_json(list(schema_version = 1L, status = "FAILED",
    message = "Artifact build did not finish. Do not use incomplete outputs."), file.path(output_dir, "model-manifest.json")) }, add = TRUE)
  source_names <- c(coordinates = "input-coordinates.csv", evidence = "input-evidence.csv", specification = "input-specification.yml")
  for (name in names(inputs)) {
    copied <- file.path(output_dir, source_names[[name]])
    assert(file.copy(inputs[[name]], copied) && identical(sha_file(copied), input_hashes[[name]]), "Could not archive unchanged model input.")
  }
  readr::write_csv(fit$aligned, file.path(output_dir, "aligned.csv"))
  readr::write_csv(movement, file.path(output_dir, "movement.csv"))
  readr::write_csv(comparisons, file.path(output_dir, "comparability.csv"))
  write_json(fit$transformations, file.path(output_dir, "transformations.json"))
  if (!is.null(distances)) readr::write_csv(distances, file.path(output_dir, "reference-distance-changes.csv"))
  synthetic <- identical(spec$data_kind, "SYNTHETIC")
  caption <- paste0(if (synthetic) "SYNTHETIC ENGINEERING EXAMPLE. " else "",
    "Arrows show relative coordinate displacement across adjacent scheduled periods, not significant opinion changes. ",
    "Uncertainty has not been estimated. Units: ", spec$coordinate_units, ".")
  graph <- driftmapR::plot_drift_map(fit, labels = FALSE) +
    ggplot2::labs(title = paste(if (synthetic) "SYNTHETIC EXAMPLE -" else "Descriptive map -", spec$issue_label),
      subtitle = paste("Aligned to", if (length(spec$anchors)) "declared anchors" else "shared entities", "| scale fixed")) +
    ggplot2::theme(plot.title = ggplot2::element_text(family = "serif", color = "#742f3c"),
      text = ggplot2::element_text(family = "sans"), legend.position = "bottom")
  # Suppress floating-point residual arrowheads, not substantive movement.
  display_tolerance <- 100 * .Machine$double.eps * max(1, abs(fit$aligned$x), abs(fit$aligned$y))
  for (i in seq_along(graph$layers)) if (inherits(graph$layers[[i]]$geom, "GeomSegment")) {
    segments <- graph$layers[[i]]$data
    keep <- pmax(abs(segments$x_to - segments$x_from), abs(segments$y_to - segments$y_from)) > display_tolerance
    graph$layers[[i]]$data <- segments[keep, , drop = FALSE]
  }
  labels <- fit$aligned[fit$aligned$period_index == length(spec$periods) & fit$aligned$entity %in% spec$label_entities, ]
  labels$display_name <- pos$country_name[match(labels$entity, pos$country_id)]
  if (nrow(labels)) graph <- graph + ggplot2::geom_text(data = labels,
    mapping = ggplot2::aes(x = x, y = y, label = display_name), inherit.aes = FALSE,
    check_overlap = TRUE, vjust = -0.8, size = 3)
  # Render outside the published artifact, then commit only complete PNG bytes.
  # Directory monitors/readers must never observe an in-progress graphics device.
  figure_temp <- tempfile("drift-render-", fileext = ".png")
  on.exit(unlink(figure_temp), add = TRUE)
  ggplot2::ggsave(figure_temp, graph, width = 8, height = 5.2, dpi = 160, bg = "white")
  figure_bytes <- read_bytes(figure_temp)
  assert(length(figure_bytes) > 8L && identical(as.integer(figure_bytes[1:8]), c(137L,80L,78L,71L,13L,10L,26L,10L)), "PNG rendering failed.")
  figure_staged <- file.path(output_dir, "movement.pending")
  writeBin(figure_bytes, figure_staged)
  assert(identical(sha_file(figure_staged), sha_bytes(figure_bytes)), "Staged PNG hash mismatch.")
  assert(file.rename(figure_staged, file.path(output_dir, "movement.png")), "Could not commit completed PNG.")
  file_names <- list.files(output_dir)
  files <- lapply(file_names, function(n) list(path = n, sha256 = sha_file(file.path(output_dir, n)), bytes = file.info(file.path(output_dir, n))$size))
  pkg <- find.package("driftmapR")
  pkg_files <- c("DESCRIPTION", "NAMESPACE", "R/driftmapR.rdb", "R/driftmapR.rdx")
  manifest <- list(schema_version = 1L, adapter_version = "0.2.0", status = "DESCRIPTIVE",
    model_id = stable_id("drift", input_hashes, drift_supported_version), generated_at_utc = utc_now(),
    track = spec$track, issue_id = spec$issue_id, issue_label = spec$issue_label, data_kind = spec$data_kind,
    periods = as.list(spec$periods), data_as_of = spec$data_as_of, specification = spec,
    provenance = list(inputs = input_hashes, package_version = drift_supported_version,
      installed_package_hashes = stats::setNames(lapply(file.path(pkg, pkg_files), sha_file), pkg_files),
      r_version = R.version.string),
    validation = list(evidence_linkage = "STRUCTURAL_ONLY", measurement_validity = "NOT_ASSESSED_BY_ADAPTER",
      geometry = "PASSED", uncertainty = "NOT_ESTIMATED", inference = "NOT_VALIDATED",
      bootstrap_attempted = 0L, bootstrap_successful = 0L, bootstrap_failed = 0L),
    counts = list(coordinate_rows = nrow(pos), entities = length(ids), paired_transitions = nrow(movement)),
    figure = list(path = "movement.png", alt = paste(spec$issue_label, "-", caption), caption = caption,
      numerical_display_tolerance = display_tolerance),
    files = files)
  write_json(manifest, file.path(output_dir, "model-manifest.json"))
  complete <- TRUE
  invisible(manifest)
}

# Segment 3 — Read-only report adapter: failures/staleness never erase the digest.
resolve_model_dir <- function(root, path) {
  if (grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)) path else file.path(root, path)
}
load_drift_panel <- function(root, config, track, cutoff, run_dir) {
  unavailable <- list(track = track, status = "UNAVAILABLE", message = "No model artifact configured.", figure = NULL)
  if (is.null(config) || !nzchar(config$artifact_dir %||% "")) return(unavailable)
  tryCatch({
    directory <- normalizePath(resolve_model_dir(root, config$artifact_dir), winslash = "/", mustWork = TRUE)
    m <- read_json(file.path(directory, "model-manifest.json"))
    assert(identical(m$schema_version, 1L) && identical(m$adapter_version, "0.2.0") && identical(m$status, "DESCRIPTIVE"), "Unsupported or incomplete model artifact.")
    assert(identical(m$track, track), "Configured track and artifact track disagree.")
    assert(m$data_kind %in% c("OBSERVED", "SYNTHETIC"), "Invalid artifact data kind.")
    assert(!identical(m$data_kind, "SYNTHETIC") || isTRUE(config$allow_synthetic), "Synthetic model artifact blocked by configuration.")
    validate_day(cutoff); validate_day(m$data_as_of)
    periods <- unlist(m$periods, use.names = FALSE)
    assert(length(periods) >= 2L && all(vapply(periods, validate_day, character(1)) <= m$data_as_of) &&
      m$data_as_of <= cutoff, "Model includes data after the report cutoff, or invalid periods.")
    assert(length(m$files) > 0L, "Missing artifact file inventory.")
    names <- vapply(m$files, function(x) scalar_text(x$path), character(1))
    assert(!anyDuplicated(names) && all(grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", names)) &&
      all(c("movement.png", "movement.csv", "comparability.csv", "aligned.csv", "transformations.json",
            "input-coordinates.csv", "input-evidence.csv", "input-specification.yml") %in% names), "Invalid artifact file inventory.")
    for (f in m$files) {
      path <- normalizePath(file.path(directory, f$path), winslash = "/", mustWork = TRUE)
      assert(startsWith(path, paste0(directory, "/")), "Artifact file escapes its directory.")
      assert(is.numeric(f$bytes) && f$bytes > 0 && f$bytes <= 25 * 1024^2 &&
        file.info(path)$size == f$bytes && identical(sha_file(path), f$sha256), "Artifact integrity check failed.")
    }
    assert(identical(m$figure$path, "movement.png"), "Unexpected figure path.")
    png <- file.path(directory, "movement.png")
    assert(identical(as.integer(readBin(png, "raw", n = 8)), c(137L,80L,78L,71L,13L,10L,26L,10L)), "Figure is not PNG.")
    age <- as.integer(as.Date(cutoff) - as.Date(m$data_as_of))
    stale <- age > config$max_age_days
    asset_dir <- file.path(run_dir, "model-assets", track)
    dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)
    for (name in c(names, "model-manifest.json")) assert(file.copy(file.path(directory, name), file.path(asset_dir, name), overwrite = TRUE),
      "Could not freeze model artifact inside report archive.")
    destination <- file.path(asset_dir, "movement.png")
    comparison <- NULL
    if ("reference-distance-changes.csv" %in% names) {
      comparison <- readr::read_csv(file.path(directory, "reference-distance-changes.csv"), show_col_types = FALSE)
      assert(all(c("entity", "time_from", "time_to", "distance_from", "distance_to", "change", "reference_entity") %in% names(comparison)) &&
        all(is.finite(comparison$change)), "Invalid reference-distance table.")
      comparison <- comparison[comparison$time_to == tail(periods, 1L) & comparison$entity != comparison$reference_entity, ]
      comparison <- comparison[order(comparison$entity), ] |> head(5L)
    }
    list(track = track, status = if (stale) "STALE" else "DESCRIPTIVE", data_kind = m$data_kind,
      issue_label = scalar_text(m$issue_label), model_id = scalar_text(m$model_id), periods = periods,
      data_as_of = m$data_as_of, age_days = age, generated_at_utc = scalar_text(m$generated_at_utc),
      message = if (stale) "Last available model is older than the configured freshness limit." else "Descriptive relative movement; uncertainty not estimated.",
      figure = list(path = destination, cid = paste0(track, "-movement@un-preview"),
        alt = scalar_text(m$figure$alt), caption = scalar_text(m$figure$caption)),
      comparison = comparison, coordinate_units = scalar_text(m$specification$coordinate_units),
      artifact_manifest_sha256 = sha_file(file.path(directory, "model-manifest.json")), provenance = m$provenance)
  }, error = function(e) list(track = track, status = "FAILED", message = conditionMessage(e), figure = NULL))
}
