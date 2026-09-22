# Deterministic synthetic geometry, not UN countries, positions or voting data.
write_drift_fixture <- function(directory, track = "statements") {
  if (dir.exists(directory)) stop("Use a new fixture directory.")
  dir.create(directory, recursive = TRUE)
  first <- data.frame(country_id = paste0("SYN_", LETTERS[1:5]), period = "2026-08-09",
    x = c(0, 2, 0, 1, 2), y = c(0, 0, 2, 1, 2))
  second <- first
  second$country_id[5] <- "SYN_F"
  second$x[4:5] <- c(1.5, 3); second$y[4:5] <- c(1.25, 2)
  second$period <- "2026-09-09"
  xy <- cbind(-second$y + 5, second$x - 3)
  second$x <- xy[, 1]; second$y <- xy[, 2]
  positions <- rbind(first, second)
  ids <- paste0("synthetic-", seq_len(nrow(positions)))
  positions$evidence_ids <- vapply(ids, function(x) as.character(jsonlite::toJSON(x, auto_unbox = FALSE)), character(1))
  evidence <- data.frame(evidence_id = ids, source_url = paste0("https://example.invalid/engineering-fixture/", ids))
  spec <- list(schema_version = 1L, track = track, issue_id = "synthetic_geometry",
    issue_label = "Synthetic geometry test", data_kind = "SYNTHETIC", data_as_of = "2026-09-09",
    periods = c("2026-08-09", "2026-09-09"), measurement_version = "engineering-fixture-1",
    measurement_description = "Known geometric displacement; no substantive position estimation.",
    preprocessing = "None; second map rotated and translated.", coordinate_units = "synthetic coordinate units",
    frame_justification = "SYN_A, SYN_B and SYN_C are stable by construction.",
    anchors = c("SYN_A", "SYN_B", "SYN_C"), reference = "previous", scale = FALSE,
    label_entities = c("SYN_A", "SYN_D", "SYN_F"), distance_reference = "SYN_A")
  readr::write_csv(positions, file.path(directory, "coordinates.csv"))
  readr::write_csv(evidence, file.path(directory, "evidence.csv"))
  yaml::write_yaml(spec, file.path(directory, "specification.yml"))
  invisible(list(coordinates = file.path(directory, "coordinates.csv"), evidence = file.path(directory, "evidence.csv"),
    spec = file.path(directory, "specification.yml"), expected_displacement = sqrt(0.5^2 + 0.25^2)))
}
