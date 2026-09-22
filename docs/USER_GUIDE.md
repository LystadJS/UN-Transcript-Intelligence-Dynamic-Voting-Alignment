# User guide — UN Transcript R

[← Project overview](../README.md)

**Version 0.2.0 · Briefing layout, full-report attachment, and driftmapR adapter.**

All application code is R. This release requires no Python, GPU, language model,
API key, Gmail password, or email authorization. The sender is `LystadJS@gmail.com`;
the recipient is deliberately blank. **This release cannot send email.**

## Start on Windows 11

1. Install [64-bit R](https://cran.r-project.org/bin/windows/base/) and
   [RStudio Desktop](https://posit.co/downloads). R 4.3 or later is required;
   use the current stable Windows release and available binary packages.
2. Extract this ZIP to a local folder, for example `C:\Users\John\Documents\UN_Transcript_R`.
   Open `UN_Transcript_R.Rproj` in RStudio. Avoid putting the active database in
   a folder concurrently synchronized by OneDrive or another machine.
3. In the RStudio Console, run:

```r
source("setup.R")
source("setup_driftmapR.R")  # Optional for collection; required for adapter tests/demo
source("tests/run_tests.R")
source("demo.R")
source("demo_drift.R")      # Real archived transcripts + clearly synthetic movement map
```

The demo replays included, hash-verified UN responses from September 9, 2026.
It creates a local database, exports, and email preview without new UN requests.
RStudio opens the preview in your browser after a successful demo.

4. Collect a live date and open the resulting preview:

```r
source("run.R")
result <- run_cli(c("--date", "2026-09-09"))
browseURL(result$preview)
```

For a routine run covering the previous three calendar days in New York:

```r
source("run.R")
result <- run_cli(character())
browseURL(result$preview)
```

The default excludes today because meetings and transcripts may still be
incomplete. Set `include_today: true` to include it. A three-day lookback catches
some delayed transcripts and revisions; it does not guarantee discovery of every
later change. Backfill older dates explicitly. The source inventory currently
covers a rolling 365-day window.

## Configuration

Edit `config/settings.yml` before running.

| Setting | Default | Meaning |
|---|---|---|
| `locale` | `en` | English only in this release |
| `categories` | `[]` | All inventory categories; exact category names restrict collection |
| `topics` | `[]` | All topics; see `config/topics-example.yml` for optional regex screens |
| `lookback_days` | `3` | Previous three dates, by default |
| `summary.meeting_highlights` | `5` | Up to five passages per meeting |
| `summary.excerpt_target_words` | `120` | Context-expansion target, not a maximum word count |
| `storage.duckdb` | `true` | Cumulative local database |
| `storage.parquet` | `true` | Per-run Parquet copies, written with DuckDB |
| `email.from` | `LystadJS@gmail.com` | Sender shown in the preview |
| `email.to` | empty | Add a recipient only if you want it displayed in the preview |
| `email.mode` | `preview` | Sending is not implemented |
| `report.headline_excerpts` | `3` | Round-robin excerpts across meetings, not an importance ranking |
| `report.meeting_cards` | `4` | Compact meeting cards; full report and coverage retain all meetings |
| `models.statements.artifact_dir` | empty | Frozen statement-position artifact, or unavailable panel |
| `models.votes.artifact_dir` | empty | Separate voting artifact, or unavailable panel |
| `models.<track>.max_age_days` | `45` / `120` | Age since data_as_of at the report's final date; older figures explicitly marked stale |
| `models.<track>.allow_synthetic` | `false` | Blocks synthetic fixtures unless explicitly opted into |

Topic screens match the complete statement. A selected passage from that
statement may not itself contain the screening term. Screening is lexical,
not a semantic classifier, and does not infer national policy positions.
Every successfully parsed statement stays in the archive, even when it does
not match a topic screen. Source country labels are matched exactly to the
recovered registry; ambiguous or institutional labels remain unresolved.

## Outputs

Each run writes `output/runs/<run_id>/`:

- `email-preview.html`: briefing with embedded images; local link to the full report.
- `email-body.html`: outgoing HTML body using CID image references, not local paths.
- `email-preview.txt`: text alternative.
- `email-preview.eml`: multipart MIME preview with inline image parts and the full report attached; no delivery action.
- `full-report.html`: all collected meetings and their extractive passages.
- `model-status.json`: unavailable, descriptive, stale or failed state for each track.
- `model-assets/`: frozen copies of accepted model artifacts used in this report.
- `manifest.json`: scope, completeness, errors, settings, timestamps, hashes and counts.
- `sessionInfo.txt`: actual R and dependency versions.
- `tables/`: inventory, meetings, statements, sentence evidence, and statement,
  meeting, and daily summaries in CSV, JSON and (when enabled) Parquet.

`output/raw/` preserves source bytes by SHA-256. `output/database/transcripts.duckdb`
stores cumulative evidence and run observations. Unchanged statements and
summaries reuse IDs; changed source bytes create a new version. Inventory and
meeting observations are retained per run intentionally. `output/LATEST_RUN.txt`
points to the last completed pipeline attempt, including a partial attempt.

No existing Python database is modified or automatically migrated. This is a
separate R store. The archive and new database can coexist with the old system.

## Windows scheduling (preview generation)

`setup.R` creates `run-preview.cmd` on Windows using your actual R installation.
Double-click it for a default run. It writes messages to `output/console.log`.

To automate previews using Windows Task Scheduler:

1. Create a task named **UN Transcript Preview** under your Windows account.
2. Choose a daily trigger, for example **07:00** local time.
3. Action: **Start a program**. Program: `C:\Windows\System32\cmd.exe`.
4. Arguments: `/c ""C:\Users\John\Documents\UN_Transcript_R\run-preview.cmd""`.
   Replace the example path with your extracted project path.
5. Set **Start in** to the project folder. Enable **Run task as soon as possible
   after a scheduled start is missed** and **Do not start a new instance**.
6. For the first check, use **Run only when user is logged on**, select **Run**,
   and verify a new preview and `COMPLETE` manifest. RStudio need not be open.

The PC needs to be running and online for collection. Wake timers depend on the
machine's power settings. A task cannot collect while the computer is shut down.
Scheduling has not been executed on Windows in this development environment.
Email delivery is a subsequent implementation step.

## Method and interpretation

The briefing uses Garamond/Georgia headings and Inter/Arial body text on a white
surface with restrained oxblood accents. It contains selected excerpts, U.S.
Mission relevance, cross-meeting developments, meeting summaries, separate
position/voting panels, and full coverage accounting. The relevance and
cross-meeting sections explicitly say they are not assessed/synthesized; the
extractive selector does not silently become a geopolitical analyst.

The statement selector ports the recovered Python algorithm: lexical rarity,
policy-action cues, explicit delegation commitments, a small early-sentence
preference, and a penalty for short ceremonial openings. It selects a contiguous
passage and expands context around incomplete sentence boundaries and pronouns.

Meeting summaries choose up to five passages while diversifying source
affiliations. Daily summaries group meeting summaries and retain child evidence
IDs. They do not generate new narrative claims or infer consensus. Reported
quotes preserve source sentence text, joined with spaces. Raw JSON preserves
the original paragraph structure and all extra source fields.

The checker verifies exact quoted text, contiguous sentence indices, and
statement/meeting/day lineage. It does not verify the UN's transcription against
audio, assess quotation representativeness, or independently verify speakers.
Timestamp warnings from the source remain visible in the email.

## Failure handling and reruns

- `COMPLETE` means discovery/processing succeeded within the declared scope.
  It can include unavailable transcripts or an empty day.
- `PARTIAL` means inventory, retrieval, parsing, TXT archival, or database output
  failed. Good source records and a clearly marked preview are preserved.
- Fatal errors retain a `FAILED` manifest and source bytes. Check the console log.
- A file lock prevents overlapping runs against the same output folder.
- HTTP retries are bounded. TLS verification stays enabled; redirects are refused.
- `Rscript run.R --date 2026-09-09 --no-db` explicitly disables DuckDB and Parquet
  while retaining CSV/JSON and the preview. It is a diagnostic mode, not a hidden fallback.
- The report may be long; actual Gmail clipping and client appearance have not
  been validated. The full HTML and all statement summaries remain available locally.

## Reproducibility and scope

`setup.R` writes `renv.lock` from packages actually installed on your machine.
No untested Windows lockfile is supplied. The driftmapR installer adds the
bundled local prototype to the project environment. Preserve the lockfile after your first
successful run. See `docs/VALIDATION.md` for the development environment, measured
checks, and Windows-specific items still awaiting local execution.

The original 108-file application snapshot was recovered and hash-verified.
This release ports the requested collection and extractive-preview slice; it
does not claim full parity with every historical stance classifier, review UI,
Azure adapter, voting model, or email delivery adapter. Original cross-topic
rules are preserved in `provenance/` for later migration; they are not silently
used as validated R classifiers.

## driftmapR integration

Read `docs/DRIFTMAPR_ADAPTER.md` for the complete input contract and limits.
The adapter uses the bundled, SHA-256-checked **0.0.5.9000** source prototype.
It does not change or run the separate package-calibration studies.

```r
source("run.R")
model <- build_drift_artifact(
  coordinates_path = "my-inputs/coordinates.csv",
  evidence_path = "my-inputs/evidence.csv",
  specification_path = "my-inputs/specification.yml",
  output_dir = "output/models/statements-2026-09-09"
)
```

Use a new output directory per build. Configure its path under
`models.statements.artifact_dir` or `models.votes.artifact_dir`, then run the
normal pipeline. The report reads the frozen outputs; it does not refit models.
Paths can be absolute Windows paths or relative to the project root.

The adapter accepts prepared two-dimensional coordinates, not raw transcript
text. It calls the actual package alignment, drift, distance and plotting
functions. It exports fit diagnostics, adjacent-period movement, entry/exit
coverage and optional reference-distance changes. It never bridges missing
entity observations. Entirely missing scheduled periods and invalid fitting
geometry are errors. No confidence intervals or significance claims are produced.

`demo_drift.R` is an engineering demonstration, not a measurement of UN opinion
change. Substantive position measurement and the voting model remain separate
upstream work. A hash proves artifact consistency, not substantive validity.

## Source references

- [UN programmatic access guide](https://transcripts.un.org/llms.txt)
- [UN full API reference](https://transcripts.un.org/llms-full.txt)
- [UN automatic transcript limitations](https://transcripts.un.org/en/about)
- [Windows Task Scheduler](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
- [renv](https://rstudio.github.io/renv/articles/renv.html)

The collection code follows literal inventory URLs. It requests `xlang=1` so
meetings without an English transcript remain in coverage accounting.
