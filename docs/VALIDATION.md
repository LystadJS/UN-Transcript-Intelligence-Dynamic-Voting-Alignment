# Validation — R briefing and driftmapR adapter 0.2.0

Validation date: **2026-09-22**. Runtime: **R 4.5.3, Linux x86_64**.
The actual installed driftmapR source prototype is **0.0.5.9000**; DuckDB is
**1.5.5**. This is engineering validation, not scientific calibration or a
Windows/Gmail acceptance test.

## Results

| Check | Result |
|---|---|
| Offline test groups | 26 passed; no skipped groups in the accepted run |
| Original selector regression | All 548 archived excerpts/scores still match the recovered reference |
| Archived collection replay | 11 inventory entries, 9 transcripts, 2 unavailable |
| Normalized records | 548 statements; 5,327 evidence sentences |
| Coverage and failures | Empty days, unavailable language, malformed inventory, duplicate pagination, bad source data and TXT failure covered |
| New briefing | Six sections; seven excerpts in the archived example; full report retains 35 selected passages across all nine meetings |
| Independent quotation check | Every displayed briefing/full-report quotation matches an exported source summary exactly |
| Actual package computation | Known displacement and reference-distance change recovered within 1e-9 tolerance |
| Entry/exit and gaps | Missing adjacent endpoints produce no movement; no arrows bridge an unobserved middle period |
| Geometry | Collinear and insufficient-anchor inputs rejected |
| Input validation | Duplicate rows, nonfinite coordinates, omitted scheduled periods, malformed evidence arrays and unresolved evidence IDs rejected |
| Model-panel validation | Track mismatch, future data, corrupted files and path traversal rejected; synthetic models require explicit opt-in; stale models labeled |
| Separate voting track | Voting artifact accepted only on its configured track |
| Path handling | Windows drive-letter, backslash, UNC and project-relative forms covered |
| MIME structure | Independently parsed without MIME defects; plain/HTML bodies, inline PNG and full-report attachment match their source bytes |
| Image references | Outgoing HTML uses CID; local preview embeds PNG; no local-file link in outgoing HTML |
| Frozen model archive | Every archived model file matches its byte count and SHA-256 |
| Persistence | DuckDB deduplication/Parquet tests pass; separate process reopens the replay database with 548 statements and 5,327 evidence rows |
| Delivery | No message sent; recipient remains unconfigured |

Accepted replay run IDs:

- Standard briefing: `20260922T184334Z_3314774ad4`.
- Synthetic map integration: `20260922T184404Z_8edbe3ebb6`.

The final table-spacing adjustment was applied by rerendering the accepted
exported tables, without recollection or changes to source summaries. The run
manifests retain the report-regeneration timestamp and report-code hashes.
The development MIME/HTML check used Python's independent standard-library
parser; Python is not an application dependency.

Evidence: `test-results-0.2.0.txt`, `demo-results-0.2.0.txt`,
`drift-demo-results-0.2.0.txt`, `independent-preview-qa.json`, and
`validated-sessionInfo-0.2.0.txt`. The previous release's evidence remains in
`VALIDATION_0.1.0.md` and its original logs.

## Repairs made during validation

- Moved common engineering fixtures into a shared helper so both test suites
  resolve them consistently.
- Replaced body-wide placeholder substitution with structural insertion, so
  transcript text containing a template token cannot alter the layout.
- Changed PNG publication to render in a temporary location, verify complete
  bytes, and commit the finished image. A full replay detected a truncated
  image; the integrity gate correctly withheld it before the repaired run passed.
- Suppressed only floating-point-residual arrowheads, retaining the complete
  numeric output and a recorded display tolerance. This is not a significance
  threshold.
- Added explicit comparison-table widths/padding and rounded-value wording.

## Limits and local acceptance

- The adapter consumes prepared coordinates. It does not validate a stance
  measurement model, infer opinions, fit a voting model, estimate uncertainty,
  or establish political significance.
- The demonstration map is synthetic, labeled in the subject, header, panel,
  figure and caption. Its coordinates are not country results.
- The separate driftmapR calibration/recovery studies were not run, altered or
  declared complete. This adapter is pinned to the inspected source archive.
- The reference-source checks establish fidelity to automatic transcript text,
  not transcription accuracy, independent attribution or representative selection.
- Local desktop/narrow-width rendered HTML was inspected. Actual received
  Gmail rendering, Windows installation, local scheduling and delivery remain
  untested here. The narrow-width renderer is not a Gmail emulator.

On Windows, extract to a new project folder, run `setup.R`, then
`setup_driftmapR.R`, `tests/run_tests.R`, `demo.R` and `demo_drift.R`. Check the
complete manifests and visible synthetic label. Do not enable automatic
delivery based solely on these local preview checks; sending is not implemented.
