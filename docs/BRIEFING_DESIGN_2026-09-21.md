# UN briefing: email format and driftmapR integration

Design record · 21 September 2026

This records the email design derived from your earlier conversations and the
original UN project specification. It adds a concrete integration contract for
**driftmapR**. The accompanying HTML is a design preview using real archived
transcript excerpts. It is not a new analytical release or a sent email.

## What carries through your previous requests

| Recurring preference | Evidence reviewed | Email decision |
|---|---|---|
| Academic, refined typography | September 8 and 14 professional-material discussions; September 15 Thunderbird request | Garamond headings; Inter body and metadata; readable fallback fonts |
| White or restrained ivory, charcoal text, limited decoration | CV/material requests and original UN visualization specification | White content surface, fine gray rules, oxblood headings, muted blue links |
| Concise, scannable, consistently labeled information | September 16 visualization revisions; September 11 generalist-language request | Short opening bullets, compact sections, meaningful labels; longer detail in an archived report |
| Evidence-grounded intelligence | September 9 UN specification | Every substantive claim has source links; quotes, analytical inferences and model estimates remain distinguishable |
| Changing positions, with uncertainty | Original dynamic-voting specification; September 10 driftmapR direction | Show longitudinal movement and its limits; separate transcript and voting evidence |
| Generalizable across issues | September 14 UN discussion | Configurable topics and countries; Gaza remains one test case |
| Honest coverage and reproducibility | Original UN specification and R preview requirements | Coverage strip near the top; missing items and failures at the bottom; dated model outputs |

These are explicit preferences or requirements. Applying the typography from
your other materials to this email is a design inference. The width, section
budgets and status wording below are new implementation choices. Dark website
backgrounds and inbox backgrounds are not treated as email-body requirements.

## Intended daily email

**Subject:** UN Daily Meeting Intelligence | YYYY-MM-DD

**Sender:** LystadJS@gmail.com. The recipient is still unconfigured.

The header states the reporting dates, language and cutoff/time zone when
available. A coverage strip gives discovered, in-scope, collected, unavailable
and failed counts. Collection dates and model comparison dates are distinct.

| Order | Section | Content and length target |
|---|---|---|
| 1 | Executive Assessment | 3–5 concise, evidence-linked bullets on consequential developments. Only claim a new development when a comparison supports it. |
| 2 | U.S. Mission Relevance | 2–3 observations about stated positions on U.S. initiatives, procedural developments or relevant coalition behavior. Descriptive; no automated policy recommendations. |
| 3 | Cross-Meeting Developments | Themes supported by more than one meeting, with evidence from each. A small table can show issue, stated positions and sources. |
| 4 | Meeting Summaries | Title; 2–3 sentence summary; attributed country positions; notable developments; evidence links. Prioritize a small number in the email and preserve every meeting in the full report/coverage register. |
| 5 | Position and Voting Updates | Separate transcript-position and voting panels. Each shows periods, coverage, method status, a figure and 1–2 plain-language interpretation sentences when available. |
| 6 | Coverage and QA | Missing transcripts, language gaps, retrieval failures, timestamp warnings and limits of source/attribution verification. |

Target roughly 600–900 words before the coverage register, with one main figure
and one compact comparison graphic when justified. This is a design target, not
permission to omit material uncertainty or source attribution. A full report
can initially be an attachment, keeping the system local. External hosting is
not required. Do not place local filesystem URLs in outgoing messages.

During the extractive phase, section 1 is labeled **Selected transcript
excerpts**. Lexical selection scores are not measures of political importance.
Sections 2–3 remain explicitly unavailable until a validated analytical method
exists. A lack of analysis must never be presented as “no important developments.”

## Visual system

- Single column, maximum width about 700 px; comfortable mobile wrapping.
- Headings: `Garamond, Georgia, serif`. Body: `Inter, Arial, sans-serif`.
  Exact fonts depend on the receiving client; the layout must survive fallback.
- White content, restrained ivory outer background, charcoal text, oxblood
  headings and muted blue links. Use color sparingly and never as the only cue.
- Short source labels in the email. Full evidence IDs, hashes, model versions
  and diagnostics belong in the archived report and manifests.
- Figures are static PNGs for mail, with captions and alt text. Interactive
  views can be local HTML companions. Delivery should package inline figures
  as MIME image parts rather than rely on files existing on the recipient's PC.
- Use simple HTML tables and supported CSS. Gmail supports standard CSS and
  media queries but can ignore unsupported rules; test the actual received
  message before enabling automated delivery. See
  [Google's Gmail CSS reference](https://developers.google.com/workspace/gmail/design/css).

## Where driftmapR belongs

The project should report **changes in expressed positions** and **changes in
voting alignment**. Neither directly observes private opinions, intentions,
coordination or causation.

Two independent analysis tracks feed the same report:

| Track | Upstream measurement | driftmapR's role | Interpretation |
|---|---|---|---|
| Statements | Evidence-linked, validated country × issue × period position measures | Align comparable maps; measure relative displacement; compare distances to chosen references | Changes in the measured pattern of expressed positions |
| Votes | A separately specified longitudinal voting model or validated repeated-map approach | Alignment and movement tools where appropriate to that model | Changes in measured voting behavior |

Text collection and extractive summaries come before these stages. The package
does not infer stance from text. Lexical or semantic embeddings may move because
the agenda or vocabulary changed; that alone is not evidence of a position shift.
Country attribution, issue definitions, comparability and stance validation
must be addressed before substantive labels are attached to maps.

Keep the package general-purpose and the UN-specific preparation in this
project. Retain the existing project identity and structure.

### Verified prototype interface

The inspected archive is `driftmapR_0.0.5.9000.tar.gz`, a development prototype.
The exported interface includes `drift_data()`, `validate_drift_data()`,
`embed_snapshots()`, `align_snapshots()`, `measure_drift()`,
`distance_to_anchor()`, `match_clusters()`, `paired_unit_design()`,
`bootstrap_drift()` and `plot_drift_map()`.

The prototype aligns two-dimensional maps using orthogonal Procrustes methods
and offers PCA/classical-MDS adapters. It does not make an unstable or
non-comparable embedding substantively identified. Avoid arrows between
independently fitted UMAP layouts as evidence of changing opinions.

### Figure design

**Main map.** A country point marks its current aligned position. An arrow starts
at the previous observed position and ends at the current position. Labels are
restricted to selected countries, with a full key in the companion report.
Stable cluster colors or halos can show supplied, matched communities; they do
not establish geopolitical blocs. Default point size is constant. If size later
encodes evidence quantity, define it and ensure it does not imply influence.

**Companion comparison.** A small table or dot plot shows change in a named issue
score, or change in distance to a specified reference, with units and comparison
dates. These are different estimands. “Closer to the U.S. in this model” must
not become “supports U.S. policy.” Both countries may have moved.

Keep alignment anchors (used to define the coordinate frame) distinct from
substantive reference countries (used to interpret relative distance). Do not
choose anchors after seeing which makes a preferred result appear.

### Interpretation and validation rules

- Alignment removes frame changes. Movement shared by all countries can be
  absorbed by that frame; reported drift is relative to explicit assumptions.
- Require the prototype's fitting geometry, including at least three
  non-collinear fitting entities and a nonsingular cross-covariance. Record
  anchor availability, residuals, retained dimensions and scale convention.
- Start with `scale = FALSE` unless the measurement design justifies scaling;
  isotropic scaling or period-specific standardization can erase real changes
  in dispersion. Fix and record preprocessing across comparable periods.
- Do not bridge missing scheduled periods with movement arrows or silently
  impute absent countries. “Insufficient comparable evidence” is different from
  “no detected movement,” which is different from “stable.”
- Paired-unit bootstrap refits require a defensible sampling design. Sentences,
  correlated speeches and overlapping windows are not automatically independent
  exchangeable units. Coordinate resampling is not a substitute. Retain all
  attempted draws, failures, delivery status and the conditional nature of
  summaries; do not redraw failures until enough succeed.
- The inspected prototype's resampling summaries are not established calibrated
  confidence intervals. A positive lower quantile of a displacement norm does
  not demonstrate significant movement. Use clearly labeled sensitivity output
  until inferential claims have independent validation.
- Cluster matching uses supplied labels; it does not itself quantify cluster
  stability. A split/merge candidate is not a verified political realignment.
- The September 21 recovery bundle records a historical running snapshot and
  no scientific-completion marker. It does not establish the current live job
  state or a completed calibration audit. No Study 07 result or v0.1 approval is
  inferred from checkpoint counts.

## Refresh cadence and R integration contract

Daily emails consume the most recent accepted model artifacts, with a visible
as-of date. They do not trigger a complete model refit every time mail is built.
Your original voting baseline remains rolling 24-month windows updated
quarterly, with 12-month and 60-month sensitivity comparisons. Choose transcript
windows after measuring issue coverage; do not silently apply the voting window
or claim a daily movement series from sparse observations.

The following is a **proposed project contract**, not an existing driftmapR API:

| Artifact | Minimum content |
|---|---|
| `positions` | Stable country ID, track, issue, period, estimate/features, evidence IDs, coverage, measurement version |
| `movement` | Country ID, start/end periods, comparable-observation status, displacement/reference-distance estimand, units, uncertainty method/status |
| `model_manifest` | Source hashes, preprocessing, package/version/hash, anchor design, windows, fit diagnostics, attempted/successful/failed refits, validation status |
| `figure_manifest` | Figure path, alt text, caption, periods, track, model ID, generated time, figure status |

The report builder reads these outputs without fitting the model. Initially
support `UNAVAILABLE`, `DESCRIPTIVE`, `VALIDATED`, `STALE` and `FAILED` figure
states with defined meanings; “VALIDATED” must identify which claim or method
passed review. The email continues when a figure is unavailable. It displays
the date/status instead of substituting an old plot without notice.

Keep initial fitting serial and benchmark one representative issue/window on
the Windows 11 machine before choosing resampling size or parallel workers.
Collection, extractive summaries and preview rendering need no GPU or Python.
The specified RAM alone does not establish the feasibility of every future
embedding or resampling workload.

## Delivered preview and how to reproduce it

`UN_Briefing_Design_Preview.html` illustrates this layout with the archived
September 9 collection: 11 discovered/in-scope entries, 9 collected transcripts,
2 unavailable transcripts and 548 statements. Its two excerpts are taken from
the existing meeting-summary selections, in inventory order, for layout
demonstration. They are not a ranking of the day's most important developments.
All inventory entries remain visible. Unavailable analysis is labeled explicitly.

The accompanying `render_briefing_design.R` reads an existing completed R run:

```r
source("render_briefing_design.R")
render_briefing_design(
  run_dir = "C:/UN_Transcript_R/output/runs/YOUR_RUN_ID",
  output_file = "C:/UN_Transcript_R/UN_Briefing_Design_Preview.html"
)
```

It uses the existing `jsonlite` and `htmltools` dependencies. It does not collect,
estimate positions, invoke driftmapR, authenticate Gmail or send mail. It is a
standalone template prototype; the tested 0.1.0 application is unchanged.

Preview verification: rendered with R 4.3.3; both displayed passages matched the
escaped archived text exactly; the 9 collected and 11 inventory counts and
unavailable-model labels were checked. The local rendered layout was visually
inspected. Actual Windows/Gmail rendering remains a delivery-stage check.

Sources reviewed: retrieved September 8–21 conversations listed above; original
`Pasted markdown.md` UN specification (email, visualization and cadence sections);
R preview release 0.1.0 and its validation record; driftmapR prototype README,
DESCRIPTION and NAMESPACE; September 21 recovery README, STATUS.json and
SUMMARY-CONTRACT.md. Prior assistant suggestions were separated from explicit
user requirements. The Gmail reference was checked on September 21, 2026.
