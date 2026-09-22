# Validation — R preview release 0.1.0

Validation date: **2026-09-21**. Development runtime: **R 4.3.3, Linux x86_64**;
DuckDB R package **1.5.5**. See `validated-sessionInfo.txt` for package versions.

## Verified results

| Check | Result |
|---|---|
| Recovery of original application snapshot | All 108 embedded file hashes matched |
| Live UN collection date | September 9, 2026 |
| Inventory pagination/count reconciliation | 11 entries; complete |
| Usable English transcripts | 9 |
| Entries without transcripts | 2; retained in coverage |
| Archived HTTP responses | 19; SHA-256 verified |
| Normalized statements / evidence sentences | 548 / 5,327 |
| Statement / meeting / daily summaries | 548 / 9 / 1 |
| Original Python vs. R selection | All 548 excerpt texts and selection scores matched |
| Offline engineering test groups | 14 passed; no skipped groups in final run |
| Quotation and hierarchy checks | Exact text, contiguous sentences and valid lineage passed |
| DuckDB persistence | Reopened in another R process: 548 statements; 5,327 evidence rows |
| Parquet persistence | Evidence file independently read: 5,327 rows |
| Rerun behavior | Stable evidence IDs; cumulative evidence deduplicated; run observations retained |
| Offline replay | Included real UN source archive replayed successfully with DuckDB/Parquet |
| Email behavior | HTML and MIME previews written; no message sent |
| Preview checks | HTML escaping and MIME round-trip passed; 55 UN links; local rendered layout inspected |

Live run: `20260921T191944Z_42b97729c6`. The complete machine-readable report is
`live-validation-manifest.json`. The development test log is `test-results.txt`.

The live sample spans six inventory categories: Human Rights Council, General
Assembly, High-level Events, International Court of Justice, Media Stakeouts,
and Press Conferences. It is not a validation of every UN body or date.

## Issues found and repaired

- Older httr2 versions lack `retry_on_failure` in `req_retry()`. The port uses
  explicit bounded transport/status retries compatible with the validated runtime.
- Sequential tibble evaluation initially shadowed the topic-match vector. A
  precomputed logical flag repaired the filter; matching and nonmatching fixtures pass.
- The demo entry point initially assumed its working directory. It now resolves
  its script location when invoked from the command line.

## Deliberate limits

- **Windows installation and scheduled execution have not been run here.**
  The setup and launcher are provided for the user's local acceptance test.
- **Gmail authentication and email delivery are not implemented in this release.**
  The MIME file is a preview; no password or recipient is needed to generate it.
- Preview layout was inspected with a local HTML renderer. Actual Gmail and
  Windows browser rendering remain untested.
- **Automatic transcripts can contain errors.** The tests establish fidelity to
  source text, not truth, speaker accuracy, or representative selection.
- Two collected recordings carry timing warnings. The preview preserves them.
- Country resolution matched 215 statements to exact structured aliases and left
  333 unresolved. Institutional speakers and missing metadata are not silently
  assigned a country; these counts are not a country-recognition accuracy score.
- Topic screening fixtures cover distinct issues, but the port does not claim
  parity with the original stance-coding or human-review subsystems.
- The current-day/rolling lookback behavior and Windows task launcher remain
  local acceptance items. The sample validates an explicit historical date.
- Summary IDs use an R-specific namespace. Statement/evidence IDs retain the
  original content-hash and statement-number scheme. Old database migration is
  outside this release.
- The included dependency record describes the actual Linux validation runtime.
  `setup.R` creates a Windows `renv.lock` only after local installation.

## Windows acceptance checklist

1. `source("setup.R")` finishes without missing-package errors.
2. `source("tests/run_tests.R")` passes with no skipped DuckDB test.
3. `source("demo.R")` reports COMPLETE and the expected 9 / 548 / 5,327 counts.
4. A live explicit-date run reports complete inventory or an honestly explained
   partial result; inspect `manifest.json` and its coverage table.
5. `run-preview.cmd` works with RStudio closed.
6. A manually triggered Windows scheduled task creates a fresh preview.

After these local checks, email delivery can be added as a separate, testable
step using the specified personal Gmail sender and a confirmed recipient.
