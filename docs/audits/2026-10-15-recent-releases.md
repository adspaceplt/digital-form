# Audit: releases merged since 2026-10-13

15 Oct 2026. Report only: nothing has been fixed.

- **Scope:** main from #434 to #484 (`3c106ae`, 51 merges), plus the open PR #485 (Letter of Offer summary, head `b9dc0cf`).
- **Tests:** `digital-form-tests` at `eb7308b`.
- **Live database:** project `hwwuigvdfubuymchsvyx`, read only (catalogue and grant queries; no logs, no writes).

Severity runs Critical, High, Medium, Low. Nothing was found at Critical. Each finding names the caller who meets it.

## Summary

| | High | Medium | Low |
|---|---|---|---|
| Safety (S) | 1 | 6 | 5 |
| Integrity (I) | 0 | 4 | 9 |
| Structure (R) | 0 | 2 | 2 |

Fix first: S1, S2, S3, S4, I1, I3.

## Safety

### S1 · High (conditional) · Quotation website · `supabase/functions/quote-request/index.ts:45-48`, `quote_website_create`
- **Path to failure:** a script posts straight to `quote-request`; CORS does not stop a script.
  - While the secret `TURNSTILE_SECRET` is unset, `human()` returns true for every request (`if (!secret) return true;`).
  - The only limit is five a day per contact, counted on the email or number the caller types. Neither is verified, so a new invented pair each time passes.
  - The count is not locked, so parallel posts from one contact also pass.
  - `selection.once` and `selection.platforms` have no length bound, and unknown keys are stored and handed back.
- **Result of each request:**
  - a new lead in Clients;
  - a quotation row;
  - a bell notice and a push to every colleague who works leads, titled with up to 120 characters the caller chose.
- **Evidence:** the deployed source (version 2) matches the repository. Whether the secret is set could not be read: the connector lists no secret names. Live there are 3 leads with source Website and 0 website quotations.
- **Fix:**
  - Refuse when the secret is unset, unless an explicit opt-out is set.
  - Add a per-IP and a global hourly limit in the function.
  - Cap the arrays and store only the keys `quote_price` reads.

### S2 · Medium · Quotation website · `quote_website_create` (`2026-10-14-quote-website-salutation.sql:66-72`), `quote_website_read`
- **Path to failure:** an anonymous visitor types any name and brand, plus the email *or* the WhatsApp number of a real Lead, Contacted or Proposal sent contact.
  - The quotation is filed under that real lead, and the colleagues are told "Quotation made on the website · {real client}".
  - The page and the PDF show the lead's name as kept in Clients. That confirms the person is an ADspace prospect.
  - The visitor can then press Proceed and attach any registered name, number and address. Use billing details copies them into the client's Billing.
- **Evidence:** the match is `lower(k.email) = v_email or regexp_replace(... k.whatsapp ...) = v_wa`, at line 71.
- **Fix:**
  - Reuse a lead only when both the email and the number agree, or always make a new lead and let the team merge.
  - Return the brand the visitor typed, never the client row's name.

### S3 · Medium · WhatsApp · `supabase/functions/wa-send/index.ts:317-327`
- **Path to failure:**
  - `wa_compose_prepare` checks that the colleague may send the named report, quotation or letter, to this contact, within their client scope.
  - The Document header, however, is whatever base64 the page sends (`body.pdf`). Nothing ties those bytes to `p_ref` or checks that they are a PDF.
  - So a colleague who sees clients A and B can send B's report to A's contact, and the record files it as A's report.
  - Malformed base64 throws in `atob` before anything is filed.
- **Fix:**
  - For a report, have `wa-send` read the kept file itself (`sm_report_file_key` as the caller, then S3).
  - For quotations and letters, require `%PDF` and keep a sha256 of the bytes sent on `wa_outbox`.
  - Catch `atob` and answer `bad-file`.

### S4 · Medium · Client checklists · `checklist_prefill` and `client_checklist` (`2026-10-15-client-checklists.sql:98-138`)
- **Path to failure:** a colleague at Clients View with Clients: Billing at No Access opens the Pre-advertising checklist.
  - The prefill sends `details.entity = clients.legal_name`. That is a billing column the grants withhold from this colleague.
  - It also sends the newest quotation reference. Quotations read at Clients: Services View.
  - The onboarding hint adds the quotation and its issue date.
  - The first `client_checklist_set` stores the prefill in `answers`, so every Clients View reader sees it from then on.
- **Fix:**
  - Use `legal_name` only where the caller passes `client_billing`'s test, else the brand name.
  - Add quotation facts only at `clients.services` View.

### S5 · Medium (latent) · Clients columns · `schema.sql:19250-19262`, `2026-09-28-client-billing-columns.sql:41`
- **Path to failure:** CLIENT BILLING COLUMNS grants select on every `clients` column except the billing list.
  - `script_key` is withheld only because it was added after that block ran.
  - Running the section again, as CLAUDE.md asks for a new column, grants `script_key` to every colleague. A second run of `schema.sql` (what the Postgres suites do) does the same.
  - Every colleague at Clients, Content Review, Campaigns or Reports View could then read every client's Video Scripts key, which opens `/script/` with no other check.
- **Evidence:** live, `has_column_privilege('authenticated','public.clients','script_key','select')` is false today.
- **Fix:**
  - Add `script_key` to the `not in (...)` list in both files.
  - Assert the privilege false after two runs in `tests/sql.js`.

### S6 · Medium · Team · `ops_due_decider` (`schema.sql:6225`), `team_member_remove`, `push-send`
- **Path to failure:** a colleague is set inactive, or removed with their data kept.
  - A later extension request on a task they created still names them as the decider. They are told, and the request waits on someone who cannot sign in.
  - Their phone keeps its push subscription (deleted only on Delete their data), so it receives the task title and client name.
  - `team_hand_over` moves only the requests already asked.
- **Fix:**
  - `ops_due_decider` falls back to the current owner, then an admin, when the creator is not active.
  - Delete `push_subscriptions` on Set inactive and on every removal.

### S7 · Medium · Details form · `client_details_submit` (`2026-10-14-client-details-form.sql:276-284`)
- **Path to failure:** every active colleague at Clients: Billing Work is told "Billing details received · {brand}", from {contact name}. The recipient list never asks client scope, so a colleague in an Own clients only group is told about a client they cannot open.
- **Fix:** filter recipients as `client_row_seen` does, and mirror that in `tests/stub2.js`. The stand-in currently tells every active colleague.

### S8 · Low · Rate card · `rate_card_current()` (`2026-10-13-rate-card-versions.sql:273-284`)
- **Path to failure:** it asks only `is_team()`, while the tables it reads ask `allowed('services','view')`. A colleague at Services No Access reads the whole live card through the RPC.
- **Evidence:** live `prosrc` holds no `allowed(` call.
- **Fix:** require `services` or `clients.services` at View.

### S9 · Low · Team · `team_hand_over`, `team_work_held` (`2026-10-14-colleague-hand-over.sql:89-91`)
- **Path to failure:**
  - These two do not refuse `own` or `system-account`; `team_member_remove` does. A Team Full Access colleague calling the RPC directly can hand over a system account's work, or their own.
  - Also: `team_access_guard` ignores `removed_at`, so a direct update can make a removed colleague active again.
- **Fix:** add the two refusals, and refuse `active = true` while `removed_at` is set.

### S10 · Low · Details form · `client_details_submit` lines 240, 262-263; `js/details.js:98`
- **Path to failure:** the contact phone is checked by its digit count only and stored as typed. An anonymous submit can store a 500,000-character phone, which Use details then copies into the Billing sheet.
- **Fix:** refuse more than 30 characters, or store the digits alone.

### S11 · Low · WhatsApp · `wa_compose_prepare` (`2026-10-14-whatsapp-documents.sql`)
- **Path to failure:** it refuses only a removed quotation and a voided letter. A tab opened before a reissue, or a direct call, sends a superseded Letter of Offer or a quotation marked Not proceeding.
- **Fix:** refuse `superseded_by is not null` and status Not proceeding.

### S12 · Low · Edge functions
- **`brand-analysis` (`index.ts:82-84`):** contact masking misses `(012) 345 6789` and `012.345.6789`, and masks dates such as `2026-10-15`. Fix: allow `().` between digits and require nine digits or more.
- **`meta-import` `pictures` (`index.ts:308-317`):** follows redirects without checking the final host, and reads the whole body before the 4 MB check. Fix: check `res.url` and `content-length` first.

## Integrity

### I1 · Medium · Quotations · `quote_price`, `quote_website_request`, `js/quote.js:677`
- **Path to failure:**
  - `quote_price` always applies the snapshot's SST in RM, with no market and no `sst_applies` input. A quotation for a Singapore or SST-exempt client therefore reads "Monthly incl. SST" in RM.
  - Issue Letter of Offer copies those rates into a letter that prints S$ with no SST. The two documents disagree.
  - Proceed requires a 12-digit registration number. A Singapore prospect, whom the website accepts on `+65`, can never press it (`bad-billing`).
- **Fix:**
  - Pass the client's market and `sst_applies` into `quote_price`.
  - Accept the UEN form for Singapore in the page and the function.

### I2 · Medium · Quotation website · `js/quote.js:220-225`, `quote_website_create`
- **Path to failure:** `8123 4567` (Singapore without 65) and `12-345 6789` (a Malaysian mobile without its 0) are refused as invalid. `ADspaceAPI.waNumber` and `wa_number` read both, and the hint says "Malaysia or Singapore number". The lead is lost.
- **Related (Low):** a lead keyed by the team as `012…` is compared as `012…` against the incoming `6012…`, so the website makes a duplicate lead.
- **Fix:**
  - Use `ADspaceAPI.waNumber` on the page, and the same mapping in the function.
  - Compare the stored number through `wa_number`.

### I3 · Medium · Team · `js/team.js:778-791`
- **Path to failure:**
  - Delete runs `team_member_remove` even when the hand-over resolved `false`, for example because the colleague chosen was just set inactive. The colleague is removed while still holding the work, and the warning is replaced by "Removed. Their data is kept." in green.
  - The other way round: a `last-admin` refusal leaves the work already handed over and the colleague still in place.
  - Partly moved person-in-charge changes file nothing (`team.js:730-733`).
- **Fix:**
  - Remove first, and hand over only on success; or stop on a failed hand-over and keep the question open.
  - File each client that did move.

### I4 · Medium · Team · `team_member_remove` with Delete their data, and trigger `team_card_slug` (`schema.sql:47322`)
- **Path to failure:**
  - The erase sets `card_slug = null`. The before-update trigger reads null as "make one" and rebuilds the same slug from the kept name.
  - The slug stays listed under Short Links, Namecards, and blocks anyone else from taking it, against "its short link freed".
  - `tests/ops.js` builds the table without that trigger, so it misses this.
- **Evidence:** no colleague has been removed live yet (0 removed, 0 erased).
- **Fix:** have the trigger leave the slug empty when `erased_at` is set, and add the trigger to the fixture.

### I5 · Low · Quotations · `rate_card_draft`, `quotation_make`
- **Path to failure:** SST is snapshotted when the card version is published. A rate change set from a later day leaves every later quotation on the old rate, while the Letter of Offer uses today's. CLAUDE.md asks for the rate on the document's own day.
- **Fix:** set `sst_pct` from `app_setting('sst_pct', today MYT)` before pricing.

### I6 · Low · Quotations · `quotation_offer`
- **Path to failure:** it refuses removed and Not proceeding quotations, but not expired ones. The page shows Expired, yet Issue Letter of Offer works on it.
- **Fix:** refuse `expired` past `valid_until` (MYT).

### I7 · Low · Content Review · `review_caption_undo` (`2026-10-15-accept-caption-undo.sql:46-53`)
- **Path to failure:**
  - After Accept caption, a colleague replaces the file or corrects the caption. That is a correction, with no new decision and no `moved`.
  - Undo then overwrites the correction, and the round falls back to a decision made on a file the client never saw.
  - `posts.round` is also writable by the page under the posts policy.
- **Fix:**
  - Compare `content_version` and refuse `moved`.
  - Take the earlier caption from `post_versions`, not from the argument.

### I8 · Low · Reports · `js/reports.js:4637-4668` (Pictures from Meta)
- **Path to failure:**
  - `res.error` is never read. A report that left draft while Meta was being read has every write refused, yet the page says "Meta holds no picture for these ads."
  - Undo files "n pictures put back" whatever came back.
- **Fix:**
  - Name a refusal with `Not saved. The database refused the request.`
  - Count what Undo actually restored before filing.

### I9 · Low · Team · Work not counted by `team_work_held`
- **Not handed over or closed:**
  - contributor and reviewer rows in `ops_task_assignees`;
  - health talks a colleague asked of them;
  - past on-site meetings still waiting for the outstation record. `meeting_at > now()` excludes these, so the reminder still goes to the removed colleague.
- **Fix:** add the three kinds, or close them on removal.

### I10 · Low · Re-run hazards in migrations
- **`2026-10-14-quotations.sql:71`:** `grant select on table public.quotations to authenticated` undoes the website file's column grant. Run alone, it exposes the prospect's `billing` at Clients: Services View and restores the older `quote_price`, which allows 1 to 36 months.
- **`2026-10-13-task-reminders.sql`, run alone:** restores the schedules without the holiday check.
- **`2026-10-14-client-details-form.sql` and `2026-10-14-public-holidays.sql`:** neither states that the function hygiene file runs first. Applied out of that order, they revoke anon from the details form and the holidays read.
- **Live today:** the grants are correct (`quotations.billing` withheld; the three anon functions granted).
- **Fix:**
  - Grant the columns in the quotations file.
  - Mark superseded files as such.
  - Add the ORDER line to both banners.

### I11 · Low · Letter of Offer · PR #485, `js/documents.js` (one-off branch)
- **Path to failure:** the one-off summary is now about 85pt after a single `need(66)`, and the PR drops the second `need(52)`. A services table that ends near the foot draws Monthly incl. SST under the 64pt floor.
- **Otherwise sound:** First month due equals the monthly and one-off totals, and the stamps are bumped.
- **Fix:** `need(oneOff ? 90 : 66)`.

### I12 · Low · WhatsApp greeting · `contact_greeting` (`2026-10-15-whatsapp-greeting-and-counts.sql`)
- **Path to failure:** with salutation Ms and the name "Ms Jane Doe", it greets "Ms Ms Jane Doe". With no salutation, "Tan Sri Ahmad" greets "Tan".
- **Fix:**
  - Drop a leading word equal to the salutation.
  - Recognise the two-word titles (Tan Sri, Puan Sri, Dato' Sri, Datin Sri) before the one-word test.

### I13 · Low · Stand-in · `tests/stub2.js`
- **Path to failure:**
  - `quotation_create` (`:8667`) answers `again` from the key before it checks client scope. The database refuses `client-scope` first.
  - `quotation_billing` (`:8689`) asks scope at Work, where the database asks View.
  - The details form's notice is noted under S7.
- **Fix:** match the database's order and level.

## Structure

### R1 · Medium · Gate · `tests/gate.sh:30`
- **Path to failure:** `acts`, `deletes` and `analysis` are not in BROWSER, so the daily `gate.sh all` never runs them. Each has a `tests/STATUS.md` row (`:84`, `:85`, `:188`) and appears in the File → suites map.
- **Fix:** add them to BROWSER.

### R2 · Medium · Walks · `tests/uxaudit.js`, `tests/matrix.js`
- **Not walked or seeded:**
  - Build quote (`#qbBox`) and a client's quotation rows (no quotation is seeded);
  - Services' Wording and Versions tabs and the wording editor (`#rcwBox`);
  - Team's Hand over and Delete questions;
  - Billing with a details form answered.
- **Why it matters:** CLAUDE.md requires a new pane and a new state in the walk in the same push.
- **Fix:** seed and walk them.

### R3 · Low · Money formatting · `js/quote.js:205-209`, `:479`, `:481`; `js/quotepdf.js:38`; `js/ratecardpdf.js:61`
- **Path to failure:** these format money themselves (`toLocaleString`, `'RM ' +`). `/quote/` does not load `js/money.js`.
- **Fix:** load `money.js` on `/quote/` and use `ADspaceMoney.money2` in all three.

### R4 · Low · Typed figures and ids
- The terms `[3, 6, 12, 18, 24]` are typed in `js/quote.js:199` and `js/quotes.js:297`; the database holds the real set.
- The slugs `static-graphic` and `reels-60` are typed in `js/quotes.js:443-444`.
- "Advertising budget above RM 20,000" is typed in `js/quotepdf.js:196` and `js/quotes.js:519`; `BUDGETS` in `js/quotes.js:26` is unused.
- `wa.me/adspace` is repeated as a fallback at `js/quote.js:544`.
- **Fix:**
  - Read the terms and the largest budget from the live card.
  - Find the lines by `spec.role`.
  - Delete `BUDGETS` and the fallback.

### R5 · Note · Live function source
- `issue_letter` on the live database differs from every copy in the repository by its comments alone; it was applied with them stripped. The logic is identical.
- Every other function added or changed since 13 Oct matches `schema.sql` exactly (md5 of `prosrc`; 46 functions).
- **Fix:** none needed. Note it so a future byte-for-byte live check does not read it as drift.

## Checked and found sound
- **Row level security and grants:**
  - RLS is on with no policy and no grant on `client_checklists`, `client_detail_forms`, `public_holidays` and `wa_outbox`.
  - `quotations` reads through `quotations_read` plus the restrictive `client_scope`, with `billing` withheld by column grants (live).
  - `clients.script_key` is withheld (live).
  - Every `client_scope` policy is restrictive (live).
- **Anon surface:** the 39 security definer functions anon can run on the live database are exactly `open_to_anon` in `schema.sql`. `quote_website_create` is closed to anon and to signed-in colleagues (service role only).
- **Migrations:** the 29 dated 13 to 15 Oct are each mirrored byte for byte in `schema.sql`. Each ends with `functions_tidy()` where it adds functions, carries a rollback, and is named by a Postgres suite.
- **Postgres suites:** `sql`, `smsql`, `lettersql`, `levels` and `ops` pass against this SQL (`gate: ok`).
- **Pricing:** quotations are priced only by the database. `quote_adjust` bounds quantity, rate and months and ignores unknown keys. `issue_letter` reprices from the stored lines, keeps the page's figures only within a sen, and applies SST at today's rate (MYT). The one-off items add up.
- **Retries:** a quotation key repeats one quotation, `quotation_offer` locks the row, and the details form submits once under a row lock. `portal_request_once` and `confirm_selection_with` were not changed in this period.
- **Public pages:**
  - Details form, review and share-link keys are eight characters from 31 (pgcrypto), and a website quotation's key is 20.
  - The expiry is held by the server.
  - `share_link_preview` answers nothing for a draft, a campaign with an access code, or a creator with no single booking.
  - `public_holidays_between` is capped at 800 days.
- **Team removal:**
  - `team_member_remove` is held at Team Full Access and refuses `own`, `system-account`, `bad-name` and `last-admin`. Running it twice is harmless.
  - No public table references `auth.users`, so deleting a login cascades into nothing. HR letters, performance records and signatories are kept.
- **Checklists:**
  - The sign-off is refused to whoever prepared it, admins included.
  - A month's check cannot be ticked by hand (`use-checklist`; `ops_engagement_checks` is read only).
  - Reopen keeps the signed copy.
  - `client_checklists_due` is scoped.
- **Edge functions:** `brand-analysis`, `meta-import` and `wa-send` authorise as the caller, claim AI use before Claude, and send no secret to the page.
- **Code structure:**
  - No `window.confirm`, `prompt` or `alert` anywhere.
  - Sheets, questions, menus, growing boxes and dates use their one copy.
  - New deletes and updates take `.select('id')`.
  - `?v=` stamps are current for every changed file, PR #485 included.
  - `node --check` passes on every changed script.
  - Typed and database text is escaped on `/quote/`, `/details/`, quotations and checklists.
  - The stand-in refuses unknown arguments for every new function.

## Not checked
- **Whether `TURNSTILE_SECRET` is set:** the connector cannot list secret names, so S1's severity stands as conditional. The user can confirm it under Edge Functions, Secrets.
- **Deployed edge function sources:** only `quote-request` was compared with the repository. The others were read from the repository alone.
- **Browser suites, uxaudit and matrix:** not run; another session runs the full gate today. No finding above rests on a browser run.
- **Supabase logs:** not read, as instructed.
- **Safari and a physical iPhone:** not available in the sandbox.
