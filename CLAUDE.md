# ADspace Digital Portal — working rules

@DESIGN.md

Static site, vanilla JS, no build step, served by GitHub Pages at
digital.adspace.me (CNAME in the repo). Pages: `admin/` (console),
`creators/` (client-facing creator selection), `review/` (client-facing
content review). Supabase behind `js/api.js`; schema in
`supabase/schema.sql` (re-runnable; the user runs it by hand in the SQL
editor after every schema change and must be told when).

The design system, the components, the laws and the copy rules are in
`DESIGN.md`, imported above. Read both before any change.

## 1. Verified code engine

### Locked features (merged to `main`, PRs #3 to #52)

| Area | Locked behaviour |
|---|---|
| Header and footer (`js/chrome.js`) | One chrome on every page: mark from `brandLogo`, kicker from `data-kicker`, actions from `data-actions` (`lang`, `qr`); "Digital Portal" and "Logged in as {email}" in the console; outlined Sign out with icon. Footer left `© {year} ADSPACE PLT. All Rights Reserved.`, right `Terms of Service` → https://adspacestudios.com/legal/policies; footer on the floor on short pages. |
| Full-page states | One `.cover` component for no link, bad link, access code, closed, confirmed, nothing to review, access not assigned; same words on `creators/` and `review/`. |
| Content Review (`review/`, `js/review.js`, `js/mockups.js`) | Post mockups per platform (Instagram feed 4:5 1080×1350, Reels and Stories 9:16 at cover ratio, TikTok, Facebook feed and carousel, RedNote); Facebook carousel: 2 tiles side by side, 4 as 2×2, 5 as 2 above 3 with `+N` greyed on the fifth; handle shown on the mockup, not the client name; client logo fills the circle with no border or shadow; placeholder avatar is an illuminance gradient, never grey or rainbow; Approve needs a name and Approved reads outlined with Request changes hidden; Copywriting label, copy text control at the top; no Save as PDF; og:title `{client name} Content Review Portal by ADspace` on `review/` only. |
| Console: Content Review | Content sets folded, one open at a time; Publish / Unpublish (warn); resend for approval with a note; Google Drive import with a progress bar; S3 upload by signed PUT; only active clients listed. |
| Console: Clients (`js/crm.js`) | Lead intake (Client name, Source, Contact person, phone, email, Enquiry; Owner, Industry, Market); record in sale order; contacts as a table; Billing details fold with ring summary and billing contact from Contacts; Brand profile fold; Calls and visits with next actions and Undo; Services lines (qty × rate × months from a start date, Enquired / Quoted / Confirmed, prefilled not fixed); Documents (the Letter of Offer); Engagements only once Active; stage select on the head with the Active gate. |
| Console: Services (rate card) | Two tables, Services and Add-ons, categories as sub-headings; Active / Inactive; admins edit, everyone reads. Rates in RM. The unit on the Account management rows was seeded as printed and flagged as wrong. |
| Console: Creator Campaigns (`js/campaigns.js`) | One card per creator, folded; Confirm creators; steps Confirmed → Pending visit → Pending draft → Reviewing → Changes requested → Scheduled → Posted → Completed, each gated by its data (draft link, publish date, posted on or after the date) with Revert; withdraw / replace / reinstate in the ⋯; bulk dates; campaign due date; invoice number (`AINV2` + six digits) and PDF upload with Remove PDF and Undo; results as a table grouped by platform; Publish to client / Unpublish. |
| Client-facing creators (`creators/`, `js/creators.js`) | Selection with optional backups (recommended, never enforced); `View RedNote Profile ↗`, `View Instagram Profile ↗`; same status words and colours as the console; foldable amount card with View PDF; results readable on a phone without sideways scroll; English and Chinese. |
| Short Links | `go.adspace.me/{slug}` table, existing slugs entered by hand, permanent QR per link that can be revoked. Domain not yet moved (Rebrandly still live). |
| Team (`js/team.js`) | User groups (`team_roles`: Admin, Account, Sales, more can be added) carry the seven `can_*` switches and `is_admin`; a person is in exactly one group; state select Active / Inactive; Invite in the ⋯; `invite-member` edge function. |
| Activity record | Table (when, tag, subject, detail, who) grouped by day, filter tabs per section (Clients, Team, Content Review, Creator Campaigns, Short Links, Services), opened from a link in the top bar. |
| Documents (`js/documents.js`) | The Letter of Offer (kind `offer`; earlier rows `intent`, `cover`), issued by sales to the client from the record, numbered `AQT/INT/YYMMXXX` (sequence per month, file name swaps `/` for `-`), drawn in the browser with pdf-lib on the ADspace letterhead (the reference is the End Thank You Letter): wordmark in Optima, Co. Reg. and address left, the monogram and phone, email, website right; PRIVATE & CONFIDENTIAL; Our Ref / Date (12th September 2026) / To (registered name in capitals) / Attn (billing contact, role); the subject LETTER OF OFFER; Dear {contact}; an opening paragraph; the **quoted lines only** (enquired lines are not priced yet, confirmed lines are past this step) as Description / Qty / Unit price / Amount; Subtotal, SST, Total; a paragraph with the validity (30 days) and what follows on acceptance; Yours sincerely, ADSPACE PLT, the signed-in person's team name; an acceptance block the client signs (Signature and company stamp, Name, Designation, Date), kept on one page with the closing; the monogram bottom centre and Page x of y on every page. Once the client signs, the formal quotation and invoice are issued outside the portal. Stored as issued in `client_documents`, Void then Delete. |
| Money (`js/money.js`) | The only formatter. RM for MY, S$ for SG; SST 8% unless `sst_applies` is false; two decimals on every total. |
| State in the URL | `?s=clients|review|campaigns|links|services|team`, `client=`, `campaign=`, `tab=`, `set=`, `new=`. A refresh (or switching tabs) lands where the person was with what they typed. Kept as `?s=` after weighing `/admin/crm` style paths. |

### Non-negotiable validation before "done"

Nothing is pushed until every one of these has run on the final code:

1. `node --check` on every changed `js/*.js`.
2. Local server: `setsid nohup npx --yes http-server -p 8899 -s . >/dev/null 2>&1 &` from the repo root (it dies between turns; restart on `ERR_CONNECTION_REFUSED`).
3. The full behavioural sweep, every suite green (`0 FAIL`, no page errors):
   `for s in run camp client cprod bar newbadge prod qr regress backup keyin state race chrome crm sgd team; do node tests/$s.js tests; done`
4. `node tests/uxaudit.js tests` → must print `uxaudit: ok`. It walks every page and state at 1280 and at 390 with a coarse pointer and fails on: sideways overflow, a cell alone on its row, uneven card padding, uneven gaps between the blocks of a section (`stack`), text under 11px (`type`), a value that wraps or clips, buttons in one row at different heights (or widths on a phone), a control under 38px (44px touch; `.btn-sm`, `.input-sm`, `.select-sm` may be 32px on desktop), a field or icon-only button without a name, more than one green action in a view, text under 4.5:1, a control border under 3:1, a control that takes focus without a ring. The review page's post mockups (`.card-stage`) are outside the audit.
5. Screenshots at 1280 and 390 of every screen the change touches, and of every page after a rule changes (the whole walk is 18 screens; each one is opened and read) (`node tests/newshot.js tests` for the client record, billing fold and rate card; `SHOTS=1 node tests/uxaudit.js tests` for the whole walk into `tests/walk/`). Each screenshot is opened and read against the phone checklist in `DESIGN.md`, not just taken.
6. For any PDF change: `node tests/pdfreal.js tests` (real pdf-lib from `tests/pdfx`), then decode the text streams (python `zlib`, hex `Tj` strings) and confirm number, names, totals and headings.
7. Version stamp: every stylesheet and script tag carries `?v=YYYYMMDD` (`20260912b`, `c`… for further pushes the same day). Bump on every push that changes CSS or JS with one `sed` over `admin/index.html creators/index.html review/index.html docs/PAGE-TEMPLATE.html admin/drive-test/index.html`.
8. The deploy is confirmed from the GitHub Pages workflow run for the merge commit (`pages build and deployment`, conclusion success). `curl` to digital.adspace.me returns 403 from the sandbox and proves nothing.

Suites live in `tests/` in the repo (`stub2.js` is the Supabase stand-in; add every new table to it). Until step 2 lands they are in the session scratchpad under `scratchpad/t/`.

## 4. Workflow and constraints

### Git and delivery
- Branch `cl/exciting-mayer-fvg0dc`; one PR per batch, squash-merged to `main` by Claude; after a merge the branch is reset onto `origin/main` (`git checkout -B … origin/main`, force-with-lease push). Never stack on merged history.
- Commit message: a one-line title in plain English about what the person gains, a body in the same register, then the two trailers from the session reminder. PR body: What changed, Test plan (ticked), the two footer lines. No model identifiers in any repo artifact.
- The user is in "proceed and merge" mode: build, test, push, open the PR, merge, confirm the Pages build, then report. Ask only when readings differ materially; never re-explain settled decisions.
- When a schema change ships, the report says "re-run `supabase/schema.sql`" in the user-side list. Edge functions (`sign-upload`, `invite-member`, Verify JWT off) are deployed by the user with the Supabase CLI.
- Never ask for a URL, key or asset the repo or config already holds (`brandLogo`, favicon, fonts in `css/`). Check `js/config.js` and `css/` first.

### Folder and file rules
- Root HTML files (`index.html`, `404.html`, `verify.html`, `ap01.html`, `ap02.html`, `ap03.html`, `ap-dale.html`, `accv-new.html`, `3pform.html`, `einvoiceinfo.html`, `interview-quiz.html`, `sales-program.html`, `supplier.html`) are the user's existing site. Never edit them, never edit `404.html`.
- Portal pages are folders with an `index.html` and clean paths (`/admin/`, `/creators/`, `/review/`), never `.html` in a URL. New pages start from `docs/PAGE-TEMPLATE.html`.
- One stylesheet `css/portal.css`; one script per section in `js/`; `js/api.js` is the only Supabase client; `js/money.js` the only money formatter; `js/chrome.js` the only header and footer. No build step, no framework, no bundler, ES5-style function scripts wrapped in an IIFE.
- Docs for setup live in `docs/` (`CONTENT-REVIEW-SETUP.md`, `S3-UPLOAD-SETUP.md`, `DRIVE-IMPORT-CHECK.md`, `FIX-ACCESS-DENIED.md`).
- Secrets never enter the repo. The Supabase anon key and the Google browser key are public by design and held back by their restrictions (Google key: websites `digital.adspace.me/*`, Drive API only). The delete code lives in the database.

### Infrastructure and assets (established, do not re-ask)
- Hosting: GitHub Pages, custom domain digital.adspace.me. Cloudflare Pages (`adspace-form.pages.dev`) only builds PR previews; the move to Cloudflare Pages was tried and abandoned (Access Denied), the site stays on GitHub Pages.
- Supabase project `hwwuigvdfubuymchsvyx`; tables and policies in `supabase/schema.sql`; `activity_viewers` is the older per-email list, superseded by user groups.
- Media: S3 bucket `myadspace`, region `ap-southeast-5`, prefix `content`, ARN `arn:aws:s3:::myadspace`, public read through CloudFront at https://mycdn.adspace.me; uploads by signed PUT from the `sign-upload` edge function; Supabase storage capped at 50 MB, so video goes to S3.
- The PDF is never stored: the portal keeps the data snapshot in `client_documents` (client, contact, lines, totals) and redraws the file on Download. Void keeps the row; Delete (only after Void) removes it and the letter can no longer be regenerated. Nothing goes to S3 or the CDN unless a person uploads it (the campaign invoice PDF is the one upload).
- Brand assets: header mark https://mycdn.adspace.me/adspace-brandname.png (`brandLogo`), favicon and og:image https://mycdn.adspace.me/adspace-favicon.png; in the repo for print: `css/adspace-mark.png` (the monogram, with alpha, taken from the reference letter), `css/SlateBook.TTF` (text), `css/SlateRg.TTF` (heavier face), `css/OPTIMA.TTF` (the wordmark). Older `ADspace.png` and the website favicon were rejected.
- Issuer (`ADSPACE_ORG` in `js/config.js`, entered by the user): ADSPACE PLT, registration 202304002162, SST J31-2401-32100002, 61-02, Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia, advertise@adspacestudios.com, 60187625233 (printed as (60)18 762 5233), adspacestudios.com. Bank line still blank.
- Emails: support and issuer advertise@adspacestudios.com, account manager marketing@adspacestudios.com, admin login adspacestudios@gmail.com. Terms https://adspacestudios.com/legal/policies.
- Short links domain go.adspace.me (about 50 slugs on Rebrandly, to be moved later).
- Google Drive import uses the browser key in `js/config.js`; the Drive folder link is the only URL accepted (`/folders`).

### Behavioural guardrails the user gave (verbatim spirit)
- "This should be automatic on your structure when designing." Every rule in `DESIGN.md` is applied before the user sees a screenshot, never after.
- "Do not state the obvious." "Be concise and direct." No explanatory copy anywhere.
- "Return means go back." Back for navigation, Revert for a state, Restore for a record, Reinstate for a person.
- "Every action needs a way back." Nothing is deleted by one click; soft remove, Undo, Void then Delete.
- "Big card for short messages": a message is a line, not a card.
- "Same status throughout": the console and the client page use one vocabulary and one colour set.
- "Prefilled, not fixed": catalogue values seed a line and stay editable.
- "A phone screenshot is reviewed, not just taken."
- "Why do I need to fill in the handles here": intake asks for what is known on day one only.
- "Not AI SaaS": flat, quiet, corporate, Apple and Cloudflare register.
- "Memory like a goldfish": when a rule is learned it is written here the same push, with the section it belongs to, so it never has to be repeated.
