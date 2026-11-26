# Handover (26 Nov 2026, 07:40 UTC)

This is the single source of truth for work in flight on the ADspace Digital Portal. It is written for a session on a **new account that shares no sessions with the old one**. Everything it needs is in the two repositories and in this file.

- **Live on main:** 261126.5538 (`83f5538`, #1475).
- **Stopped:** every old session has stopped. Each one pushed its branch and posted a handover comment on its draft PR.
- **Read first:** a session picking up an item reads this file, `CLAUDE.md`, and the handover comment on the item's PR, then continues that branch.

---

## 0. Before any session starts (once, on the new account)

1. **GitHub:** connect at claude.ai with access to `adspaceplt/digital-form` and `adspaceplt/digital-form-tests`. The suites repository is private.
2. **Supabase:** a connector to project `hwwuigvdfubuymchsvyx`. If the connector belongs to another Supabase organisation, use the Management API with a token, as CLAUDE.md §3 allows. Never print the token.
3. **Environment:** network access to GitHub, Supabase, npm and the CDNs. The session-start hook clones the suites itself.
4. **Limits:** at most **4 sessions at once** (CLAUDE.md §3). The old account stopped on its 5-hour usage limit, so stagger the work.

---

## 1. Ready to finish (draft PRs, in this order)

Each PR carries a handover comment that lists its commits, its checks and the steps still open.

| # | PR | Branch | State | To finish |
|---|---|---|---|---|
| **1** | [#1479](https://github.com/adspaceplt/digital-form/pull/1479) Settings sheets layout | `claude/settings-sheets-layout` | Built. Every check passed except `demo`, which was rebuilt and not re-run. | Run `node tests/affected.js --run`, mark the PR ready, squash-merge, confirm Pages. No migration. |
| **2** | **S1 edge functions** (merged in #1475) | main | **19 edge function changes are on main but NOT deployed.** Live is behind main. They add the time limits, `maxRetries: 0`, the pdfref regex, the push body cap, the push_done retry and the mail.ts refresh. | Deploy each changed function from main per CLAUDE.md §3: send it whole with its `_shared/` files, read it back and compare. Do this before any other function deploy. |
| **3** | [#1478](https://github.com/adspaceplt/digital-form/pull/1478) Build quote "lines" → items (tests PR digital-form-tests#293) | `claude/qb-items` | Built. The affected run stopped partway, with no result. 10 copy-review findings are not applied. No screenshots. | Apply the 10 findings, run the affected suites, take screenshots, then merge. **Merge before item 6, or fold it into item 6.** |
| **4** | [#1477](https://github.com/adspaceplt/digital-form/pull/1477) Review fixes S2: abuse paths | `claude/review-fixes-1125-s2`, tests branch `handover/review-fixes-1125` | Drafted, not tested. | Finish the `abusesql` suite and the stub2 refusals, run the tests, merge, then apply the migration `2026-11-25-minor-abuse-paths-held.sql`. |
| **5** | [#1476](https://github.com/adspaceplt/digital-form/pull/1476) Campaign invoice made in Bukku | `claude/camp-invoice-bukku` | Partial: the migration, the bukku-sync `campaigninvoice` action and the console panel are written. **Nothing is applied or deployed.** | Still to do: the CSS, the Settings model field (`campaign_invoice_model`, seeded **AINV2609023**), the stand-in, the suites and the copy review. Then apply the migration and deploy bukku-sync (merge main in first). One invoice line per creator. Open point: the client's selection page used to offer the uploaded PDF, so add a client-safe download or show the number only. |
| — | Review fixes S3 | `claude/review-fixes-1125-s3` | Drafted, no PR. | See §3, S3. |

---

## 2. New faults reported 26 Nov (diagnosed, not built)

All five were checked against the code and the live database. Ship them as one or two releases.

| # | Fault | Cause | Fix | Migration |
|---|---|---|---|---|
| F1 | **Trip sheet facts break mid-word** ("#OS26110 / 1", "Shootin / g") | `css/portal.css:3682` `.facts:has(> :nth-child(6))` forces 6 equal columns, which beats `.ost-facts` (console.css:4956). The 620px sheet gives about 77px per column, and `overflow-wrap: anywhere` breaks the words. | At the shared rule: `repeat(auto-fit, minmax(max(140px, calc((100% - 5*24px)/6)), 1fr))`, so a narrow box reads 3 over 3. Note cells span the full row. `nowrap` on `.serial-copy`, and an ellipsis on `.ost-person > span`. Check every `.facts` with 6 or more cells with `cssguard`, `geom` and `fit`. | No |
| F2 | **Settings shows next trip 01** after #OS261101 | `js/settings.js:164-170` passes a literal `1`. The real counter is `outstation_ref_months.last` (live: 202611 → 1), which the page cannot read. | `id_formats_list` returns `next` for trips (this month's `last` + 1); settings.js reads `f.next`. | Yes |
| F3 | **Quotations missing from Documents** | `js/register.js:273-292` lists only quotations not removed **and** sent or signed. Live, 4 of 9 are neither (C02, S04, P02, S01). Removed quotations are dropped, though /verify/ answers them as Void. `quotation_delete` hard-deletes even a quotation that was sent (6 references are kept in `quotation_refs_kept`). | **Ask the user first** (it changes what "sent" means in `services.md`): stamp a quotation *issued* at its first Download, PDF or Copy link, and use that for both the Register and /verify/. List removed quotations that were sent, with Void. `quotation_delete` refuses one that was sent or signed (error `sent`). Correct `docs/rules/documents.md:199`. | Yes |
| F4 | **S$ approximation uses the old rate** (shows 3.15; Settings holds 3.18 from 26 Nov) | `js/money.js:81-94` `load()` keeps its first read for the life of the page. Only the tab that saved re-reads. Build quote does not listen to `adspace-settings`. The same stale read affects `quotes.js:1502`, `campaigns.js:114` and `crm.js:6740`. | In money.js: re-read after a few minutes, on visibility or focus, and when the day changes. Build quote repaints the footer and FX on `adspace-settings`. Optional: `quote_price` returns the rate it used. | No |
| F5 | **/verify/ finds nothing for ADP/QT2611-C02** (it exists: status sent, doc_code VBV6QDRH) | The last `verify_find` (schema.sql ~148847) requires `sent_out_at` or `signed_at`; C02 has neither. The `by_code` lookup does not cover quotations. | Use F3's "issued" predicate, and add quotations to `by_code`. Run the verify suites. | Yes |

---

## 3. Built later: approved but not started

### Build quote redesign (**the user wants the flow planned and a mockup approved first**)

**The user's complaint:**
- editing one brand forces a trip back and forth through steps 1 to 4;
- the first brand is never asked for a name;
- after two brands, Continue loops back to "Choose what to quote";
- buttons are the wrong shape and size.

**The cause, mapped** (`js/quotes.js`):
- `brandAdd` (≈1706) ends with `brandNew()` and `stepGo(1)`. That opens an empty brand with `B.kind = null`, so Continue on step 1 answers "Choose what to quote."
- `basket()` (≈1668) shows `#qbBrandRow` only once `B.brands` exists, so the first brand gets no name field.
- `brandEdit` jumps to step 2, while Save brand lives on step 3.
- The Summary repeats "Monthly subtotal" and "Monthly excl. SST" (`money.js:339-357`).

**The agreed direction.** Mock it up at 1280 and 390, get approval, then build:
- **One sheet, no steps.** Remove `#qbTrack`, `stepGo`, `stepNext`, `stepWrong` and Back.
- **Brands.** Each brand is a `.kcard`, built the same way for the first brand as for every later one:
  - head: the name, its meta, the monthly figure and a ⋯ (Duplicate, then Remove in red with Undo);
  - body: **Brand name first** (prefilled with the client's name for the first brand only), then a segment Plan · Package · Items, then that type's block, then the brand's extras;
  - one card is open at a time, and edits apply in place;
  - **Add brand** (`btn-quiet btn-sm` with the plus) appends a card that opens ready to fill;
  - remove Save brand, Editing and `B.was`.
- **Quotation part** (one `fsec` below the brands): Term, Date, Payment terms, Valid for, the discount, advertising budget, add-on rates, Bill to and More details.
- **Summary at a desk:** a cart grouped by brand. Each name takes the full width with its figure under it. Drop "Monthly excl. SST" when it equals the subtotal. The phone keeps View quote.
- **Footer:**
  - the total and the brand count;
  - Cancel (quiet), Preview PDF (tonal), and one blue **Create quotation** (**Save** when editing), shown once priced;
  - Create checks every card and opens the first card with a fault;
  - every button full height; a phone follows the shared foot rule.
- **Drafts:** drop `_step`; `_bi` becomes the card that is open.
- **Before editing,** grep the suites for `qbNext`, `qbTrack`, `stepGo`, `qbBrandAdd` and `data-qbstep`.

### Quotation pricing (Q1)
- **Must:** `quote_files_fit` skips a text `qty` (`"99"`), so the files cap is bypassed on /quote/. Refuse anything that is not a whole number, and add a test.
- Key add-on extra rates per brand; today they are de-duplicated across brands.
- Refuse a monthly package on a 1-month term.
- Add one SQL suite covering two brands and a package on each term.

### Client amounts and admin check (Q2)
- `amountOf` (`js/portal.js:207`, `js/crm.js:6384`) rounds per unit. Return each line's amount from the database (`quote_totals`) and delete both copies. Example: 3 × RM 333.33, 12 months, −5% reads RM 11,399.76 on the portal against RM 11,399.88 on the letter.
- `syncValue` (`crm.js:6975-7005`) leaves Value stale. Derive Value on every load, then delete it and its six calls.
- Show "Confirm without letter" (crm.js:6664) to admins only. In `override_service_state`, use `t.is_admin or t.role='admin'`.
- Add `public.me_is_admin()`, and use it in that function and in `hr_form_pass`.

### Review fixes S3 (branch `claude/review-fixes-1125-s3`, drafted)
- The portal's Invoices card hides itself when Bukku fails; show the failed state with Try again.
- `js/supplierform.js` drops bank changes when the account number is blank, yet reports them as saved.
- A failed feedback read hides the feedback request.
- Outstation:
  - add `for update` against the midnight close;
  - re-read the office position at each check-out;
  - count only photos that are not removed toward the 10;
  - retry a failed back-drive.
- Dead code to remove: `js/ops.js` `meetingHeld` and `statusCell`, `js/engage.js` `shortMon`, `js/money.js` `payLine` and its unused exports, and the date fallbacks at `crm.js:3104` and `settings.js:997`.

### Review fixes S4: retention and scheduled jobs (builder on tests branch `handover/review-fixes-1125`)
- **Must:** a colleague set inactive keeps their health data indefinitely. Add `team_members.inactive_at`, stamped and cleared by the before-update trigger. `privacy_retention` then reads `coalesce(removed_at, expired_at, inactive_at)`. Backfill from `updated_at`. Live: no colleague is affected yet.
- **Must:** `hiring_retention` leaves a candidate's email and IP in `signing_steps` (`doc_kind='hiring_doc'`). Delete them first.
- `privacy_retention` runs monthly (`45 18 1 * *`). Run it daily (`45 18 * * *`).
- `health_daily`: change `=` to `>=`, so a reminder that falls on a holiday is not lost.
- `supplier_email_begin`: add an advisory lock and a `sending` refusal under 10 minutes, as in `client_email_begin`.
- `feedback_mail_begin` / `feedback_request`: refuse `sending`, and refuse `recent` within `wa_repeat_hours` unless Again is pressed.
- Hiring emails:
  - the kick also wakes on `hiring_docs.expire_mail='queued'`;
  - the claims mark a stale `sending` as `unknown`;
  - `jobs_watch` counts failures.
- `ops_tasks_nudge` and `ops_tasks_remind` return 0 on a public holiday.
- `team_expire_access`: re-check `active` and the end time in the update.
- `ops_generate_recurring`: take the advisory lock before the `idem_key` check.
- Add an index on `ops_notifications (team_member_id, kind, created_at desc)`.

### Review fixes S5: tone sweep of standing lines
- Run a fresh copy review of `js/crm.js` and `js/letters.js`; the findings are on the tests branch `handover/review-fixes-1125`. #1479 lists 15 more:
  - refusals with no next step;
  - "billing person";
  - What it is / What works;
  - Add row;
  - "Quotes" where it should say quotations;
  - Sent again;
  - Website quotations;
  - Rate line;
  - Press a row;
  - the billing details request message, which has no 中文.

### Smaller items
- **Tone sweep 9 fixes:** branch `claude/tone-sweep-9-fixes` (14 files) is **built and never merged**. Merge main in line by line, run `words` and the affected suites, then merge.
- **PDF wording:** the user said "approve all", but **keep NET 7**, the house term (7 days from invoice).

---

## 4. Waiting on the user

1. **Delete 4 retired edge functions** in the Supabase dashboard: `report-thumbs-move` (Verify JWT off; its token is gone, so it refuses all calls), `bukku-peek`, `auth-templates` and `video-probe`.
2. **Decide:** keep or remove "Quotation Cover" as a kind in Documents' **Add** sheet. The recommendation is remove.
3. **Approve the expectation change in #1474:** a bill Bukku made but did not list is held (`creator_bill_made`).
4. **Rotate the Bukku token,** then update the `BUKKU_TOKEN` Supabase secret.
5. **Decide F3:** "issued" means the first Download, PDF or Copy link.
6. **Explain the screenshot** of the "Rate Card wording / Templates" card: what is wrong with it.
7. **Check on an iPhone:** Outstation thumbnails, the Add photo camera, and the Safari dark-mode toolbar.

---

## 5. Held (do not build without the user)

- WhatsApp overdue reminders.
- The supplier approval email sent on Approve.
- The closed loop from quotation to report, held until the team's first month has passed.
- The S3 storage-class rule.
- A database restore rehearsal.
- My growth and the AI read, held until about Dec 2026.
- UX brief batch 2.
- Onboarding by procedure.
- The city on quotation-link activity: unverified until the first real visit. Check with `select meta from activity_log where action like 'quotation.%'`.

---

## 6. At the end of the day

Once everything above is merged, run the full gate on main: `bash tests/snap.sh all` in the background, with a 2-hour limit. Its findings become the next batch.

**Flaky suites logged in STANDARD.md** (each failed once under load and passed alone; the causes are still to be found): `demo`, `crm` Last seen, `hiringsql`, `quotes` at 390, `outstationsql`.

---

## 7. Prompts to paste into new sessions (one per session, at most 4 at once)

> **A, finish and deploy:** Read HANDOVER.md on main in adspaceplt/digital-form. Do §1 items 1 and 2 in order. Merge #1479. Then deploy the 19 S1 edge functions from main, reading each one back. Report each build as `{YYMMDD}.{last 4 of the 7-character merge hash}`. Merge without asking.

> **B, Build quote:** Read HANDOVER.md on main in adspaceplt/digital-form. Finish §1 item 3 (#1478), then plan the §3 Build quote redesign. Show me mockups at 1280 and 390 and wait for my approval before building.

> **C, faults:** Read HANDOVER.md on main in adspaceplt/digital-form. Fix §2 F1, F2, F4 and F5. Ask me about F3 before building it. Merge each release without asking, and report the builds.

> **D, review fixes:** Read HANDOVER.md on main in adspaceplt/digital-form. Finish §1 item 4 (#1477), then S3, S4 and S5 from §3, each as its own release. Merge without asking.

> **Later, after A to D:** Read HANDOVER.md on main in adspaceplt/digital-form. Finish §1 item 5 (#1476, the campaign invoice), then Q1, Q2, the Tone sweep 9 fixes and the PDF wording (keep NET 7). Then run the full gate (§6).
