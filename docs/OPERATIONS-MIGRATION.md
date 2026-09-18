# Operations system — moving off the spreadsheet

The monthly workbook is the operational source of truth today. This is the
mapping the importer uses and the order the cutover runs in. The importer
itself is Phase 5; the mapping is settled here first, because an import
written against a mapping nobody agreed is an import that has to be undone.

## 1. What the workbook holds

One tab a month, with these columns:

Client · Type · Tasks / Content Description · Remarks · First Draft Due ·
Final Due · Revision Due · Priority · Stage · Assignee

## 2. What it does not hold

Enough history to reconstruct cycle time, stage time, active work or lateness
for anything but the current month. There is no created timestamp, no stage
history, no completion timestamp and no record of a date having moved.

**No timestamp is invented.** A row that arrives without one is imported with
`data_quality` naming what is missing, and every time-based metric excludes it
and says how many it excluded. A Done row with no completion timestamp is
never counted as delivered on time, because nothing in the sheet says it was.

## 3. Client aliases

Matching is by a reviewed mapping table and never by similarity. Fuzzy
matching on a client's name is how one client's work lands on another
client's record.

| In the sheet | Client |
|---|---|
| `D&C` | Dale & Cecil |
| `HKL` | HKL Lim |
| `SPS` | S P Setia |

Extend the table during the dry run. A row whose client is not in it is not
imported; it goes to the manual-review list.

## 4. Type codes

Deliverable and language are two facts and are stored as two columns, not as
one code.

| Code | Deliverable type | Language |
|---|---|---|
| `S EN` / `S CN` / `S ML` | static | en / zh / ms |
| `C EN` / `C CN` / `C ML` | carousel | en / zh / ms |
| `R EN` / `R CN` / `R ML` | reel | en / zh / ms |
| `SV EN` / `SV CN` / `SV ML` | video | en / zh / ms |
| `GIF EN` / `GIF CN` / `GIF ML` | gif | en / zh / ms |
| `Report` | report | — |
| `Adhoc` | adhoc | — |
| `Quotation` | quotation | — |
| `Invoice` | invoice | — |
| `PO` | purchase_order | — |

A reel or a video takes the video workflow; everything else takes the general
one.

## 5. Stages

| In the sheet | Stage | Note |
|---|---|---|
| Ideation | `intake` or `ready` | Ready where the row has an owner and a final due date |
| Planning | `ready` | |
| Shooting | `shooting` | video workflow |
| Designing | `in_progress` | |
| Editing | `editing` | video workflow |
| C.Review | `client_review` | |
| Revision | `revision` | |
| Scheduled | `approved` | the portal has no Scheduled stage; Approved is what it means |
| Done | `done` | `data_quality` records that there is no completion timestamp |
| KIV | `kiv` | |
| **Due** | manual review | Overdue is derived from a date, never a stage |
| blank | manual review | |

## 6. Data-quality flags

`ops_tasks.data_quality` carries one of:

`complete` · `legacy_no_history` · `legacy_missing_due` ·
`legacy_missing_stage` · `legacy_placeholder` · `needs_review`

Anything but `complete` is excluded from cycle time, stage time, active work,
waiting time, flow efficiency, first-draft on-time and historical on-time, and
the exclusion is stated on every metric that made it.

## 7. The sequence

1. Export each required tab as a bounded CSV.
2. Load into a staging structure, never straight into `ops_tasks`.
3. Normalise clients, colleagues and type codes against the tables above.
4. Classify each row: complete, placeholder, or manual review.
5. Produce the dry-run report and read it.
6. Import the approved rows with `legacy_source` and `legacy_key` set.
   `ops_tasks_legacy_idx` refuses the same row twice, so a rerun is safe.
7. Reconcile counts by month, client, assignee and stage.
8. Keep the workbook read-only from the cutover moment.

## 8. A practical first cutover

Import the open tasks of the current month, and recent completed tasks for
reference only, marked legacy. Leave the older tabs as an archive. Stop adding
work to the sheet at the agreed time and reconcile daily for the first week.
