# driftmapR adapter — release 0.2.0

## Scope

Fit prepared 2-D maps with the actual driftmapR 0.0.5.9000 prototype; preserve
diagnostics and produce a descriptive, dated figure for the R briefing. No
text-to-stance classifier, embedding estimation, bootstrap, significance labels,
political-bloc classifier, or voting model is implied. Transcript positions and
voting behavior use separate artifacts and panels. Initial support is one issue
per track per email; build other issues separately rather than combine them into
an unlabeled map.

## Installation and execution

In the project, run `source("setup.R")` and then `source("setup_driftmapR.R")`.
The latter verifies the included tarball before installation. The package itself
requires no compilation; its dependencies use available Windows binaries. If
driftmapR is already loaded, restart R before running its installer. The adapter
refuses other prototype versions until compatibility is tested explicitly.

Command-line entry point, with Rscript available on PATH:

```text
Rscript drift.R --coordinates my-inputs/coordinates.csv --evidence my-inputs/evidence.csv --spec my-inputs/specification.yml --output output/models/new-model
```

The equivalent `build_drift_artifact()` R call is in the README. All four paths
are required. Use a new directory; no existing model output is overwritten.
Errors before fitting create no output. A later failed build leaves a FAILED
manifest and retained partial files for inspection; the report refuses it.

## Inputs

`coordinates.csv`:

| Field | Required meaning |
|---|---|
| `country_id` | Nonblank stable identifier; normally a country-registry entity_id |
| `country_name` | Optional readable name, consistent for an identifier across periods |
| `period` | Quoted ISO-date label matching a declared period |
| `x`, `y` | Finite numeric coordinates in comparable units |
| `evidence_ids` | Nonempty JSON array of unique IDs resolving to evidence.csv |

Each country-period pair occurs once. The upstream measurement procedure is
responsible for country identity, issue coding, comparable evidence composition,
measurement validity and map construction. This adapter does not validate those
substantive decisions. Its evidence check verifies linkage structure only; it
does not retrieve URLs or verify that linked evidence supports a coordinate.

`evidence.csv` needs unique `evidence_id` values and credential-free HTTPS
`source_url` values. Additional columns are preserved in the archived input.

`specification.yml` (fill in substantive fields; this is a schema example):

```yaml
schema_version: 1
track: statements
issue_id: your_issue_id
issue_label: Your issue label
data_kind: OBSERVED
data_as_of: "2026-09-09"
periods: ["2026-08-09", "2026-09-09"]
measurement_version: your-measurement-version
measurement_description: Describe how evidence produced these coordinates.
preprocessing: Describe the fixed preprocessing and map-fitting procedure.
coordinate_units: Describe the coordinate units.
frame_justification: Explain the stability assumption for the fitting entities.
anchors: []
reference: previous
scale: false
label_entities: []
distance_reference: ""
```

`OBSERVED` identifies the input's provenance, not validation or acceptance of its
method. Use `SYNTHETIC` for engineering fixtures; synthetic artifacts are blocked
in normal emails unless `allow_synthetic: true` is explicitly configured.

Supply the complete ordered schedule (2–12 periods); every declared period must
have observations. The software cannot discover an omitted period that was
never declared. It does not impute missing countries or draw movement arrows
across unobserved adjacent endpoints. With 12 periods, inspect readability before
publication; prefer a short comparison series for the email.

Empty `anchors` uses all shared entities, a substantive frame assumption rather
than a claim that those entities are stable. Otherwise provide stable IDs;
driftmapR needs at least three non-collinear fitting entities at each fit and a
nonsingular cross-covariance. `reference` is `previous` or `first`; `scale` is
fixed to false in this adapter. `distance_reference` optionally names one entity
observed in every period. This interpretation reference is conceptually
distinct from alignment anchors, even if the same entity is chosen for both.

## Outputs and interpretation

| Output | Meaning |
|---|---|
| `input-*` | Exact source CSV/YAML bytes with hashes |
| `aligned.csv` | All observed positions transformed into the fitted frame |
| `movement.csv` | Adjacent-period paired observations, vector components and displacement norm |
| `comparability.csv` | PAIRED, ENTERED, EXITED or UNOBSERVED; counts of linked evidence IDs, not independent sample sizes |
| `transformations.json` | Matched entities, rotation/translation, fit residuals and geometry diagnostics |
| `reference-distance-changes.csv` | Optional adjacent change in distance to the chosen reference |
| `movement.png` | Package trajectory plot, consistent axes and restrained styling |
| `model-manifest.json` | Method specification, versions, hashes, periods, timestamps, validation limits and file inventory |

Arrows represent relative geometric displacement, not speed, causal change or
significant opinion change. Shared movement can be absorbed into the fitted
frame. Independently fitted nonlinear embeddings can change geometry for
reasons alignment cannot fix. A semantic/topic shift is not automatically a
stance shift. The adapter estimates no uncertainty and offers no VALIDATED
inferential state. No cluster halos are synthesized from countries' identities.

The figure suppresses only arrowheads whose coordinate differences are below
the recorded floating-point display tolerance (`100 * machine epsilon *
max(1, absolute aligned coordinate)`). Full numeric results remain unchanged.
The email distance table rounds to three decimals and does not classify rounded
zero as substantive stability.

A negative reference-distance change means closer in this model; the reference
may itself move. The compact email table shows at most five paired entities in
identifier order for the latest adjacent period pair, not the most important or
statistically significant shifts.

## Report behavior

| State | Report behavior |
|---|---|
| UNAVAILABLE | No artifact configured; explicit empty-state panel |
| DESCRIPTIVE | Verified artifact files displayed with periods and no-inference caption |
| STALE | Last artifact displayed with a prominent age/status warning |
| FAILED | Invalid/missing/corrupted/disallowed artifact; error panel, no figure |

Freshness is the report's final date minus `data_as_of`, not time since the
software refit. A data cutoff after the report's final date is rejected. The
adapter checks configured track, file paths, byte counts, SHA-256 hashes and PNG
signature. Accepted model outputs are copied into the report's own archive.
Hashes detect accidental modification; manifests are not cryptographic signatures.

Model failure does not change transcript-collection COMPLETE/PARTIAL status;
its separate status is recorded in `model-status.json` and `manifest.json`'s
email section. A daily digest never silently triggers a model refit.

## Preview and delivery boundary

Local HTML embeds PNG bytes and links to full-report.html beside it. MIME uses
CID image parts, text/plain and text/html alternatives, and an HTML full-report
attachment. Outgoing HTML has no local-file links or data-URI image dependency.
No Gmail API, SMTP, credentials, recipient discovery or send operation exists.

The original rolling 24-month voting-window baseline and quarterly update
proposal are unchanged. Schedule and measure the upstream model separately.
Windows/Gmail acceptance and substantive measurement validation remain required.
