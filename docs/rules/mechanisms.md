<!-- triggers: js/api.js js/money.js js/acts.js js/clock.js js/otp.js js/copy.js js/icons.js js/words.js js/captcha.js js/decide.js js/swipe.js js/chart.js -->
# Shared mechanisms

Moved from `CLAUDE.md` §2, One copy of each mechanism, on 2026-11-23. Each is the one copy of its mechanism: no page keeps its own.

- `js/api.js` is the only Supabase client. Demo content is only for a copy
  with no database configured: a configured page whose database library
  failed to load reads Unable to load and records nothing, and a review
  decision is shown only on the database's own `ok` (audit F5, 2026-10-10). It retries a GET once when the
  connection drops before the answer (`steadyFetch`); a write is never sent
  twice. Every request it sends is counted: one out `showAfter` (300ms)
  draws the loading line (`.loadbar`, appended inside its host on each
  request so whatever is laid over the host draws over it, 2px under the page's own bar across
  its width, under an open sheet's head across its card while one is open; the minute's `page_pulse` never shows it) until the last
  answers; a read (GET) unanswered at `giveUpAfter` (20s) is given up,
  never tried again, so the page says it could not load with Try again; a
  write is never cut off; a skeleton past `slowAfter` (8s) reads Still
  loading… (`ADspaceState.stillLoading`), and a dropped connection reads
  `W.offline`, never the browser's words; the three from
  `ADSPACE_CONFIG.loading` (the user, 2026-11-10: "is it really loading?";
  `tests/loadbar.js`). Refresh app and pull to refresh turn their ring and
  run the line until the page reloads.
- `js/money.js` is the only money formatter and the only place a price is
  adjusted.
  - RM, or S$ for a Singapore client billed in S$ (`curOf(c)`: a payload's
    `bill_market`, else `market` SG with `bill_sgd`; the market alone never
    picks the currency); a Singapore client billed in RM reads its total's
    S$ beside it (`approx(n, c, at)`, ` (approx. S$ 952.38)` at `fx_sgd`).
  - SST at the rate in force on the document's own day (`taxOf(sub, m,
    applies, at)`, `taxLabel(m, at)`; a letter passes its `issued_at`, a
    campaign's booked creators the client's last confirmation (`kind`
    client), a selection still to confirm none)
    unless `sst_applies` is false.
  - Two decimals on every total, each charged figure (`rateFor`, `taxOf`)
    rounded by `cents()`, a half away from nought as Postgres rounds, the
    float nudged first (1,234.50 × 0.95 is 1,172.7749… in a float).
  - `TERMS` holds the older factor table (used when `term_pct` is null).
  - `ADspaceMoney.load()` reads the business figures once a page
    (`app_settings_read()`, anon too) and `setting(key, at)` answers them;
    the console waits for it beside `me()`, the client portal beside
    `get_portal`, the selection page beside `get_campaign`. `FIRST` is used
    only where the read fails, and is the one copy of a default (no page
    keeps its own); a failed read is not kept, so the next `load()` asks
    again. A figure is read at the day it applies to, as the database reads
    it (a report's deadline at its period's end).
- `js/decide.js` records a client decision.
  - The name grows out of Approve (`.namebox`), key `adspace_reviewer`.
  - While a name is held, the review and selection pages' name card ends in
    one line, Deciding as {name} · Change · Forget (`.decide-as`,
    `ADspaceDecide.whoLine`, words in `js/words.js`): Change edits it in
    place, Forget removes it from this device and the name field returns to
    a request. Decisions already made keep the name they were made under.
    The selection page's Confirm opens its name on it (2026-10-27, SEL-4).
  - Request changes steps aside while it asks (`.approve-row.is-asking`).
  - An open note box carries `.changebox-who`.
- `js/swipe.js` is the only swipe: on touch, a sideways swipe inside a
  `data-swipe` region presses the tab beside its strip's chosen one (nearest
  region wins). It is left alone within 24px of an edge, on a field, select,
  editable text, drag grip or `data-noswipe`, inside anything that scrolls
  sideways, with a ⋯ menu or the rail drawer open, over selected text, in a
  sheet without its own region, and unless plainly sideways (across 1.5 times
  the down), at least 56px or a fifth of the width, within 0.8s. A region may
  name a pair of buttons instead (`data-swipe-prev` / `data-swipe-next`, the
  Review Canvas): the finger moving left presses Next, a disabled one is left
  alone, and `data-swipe-media` lets a swipe start on a video above its
  controls.
- `js/chart.js` (`ADspaceChart.draw(host, spec)`) is the only chart, in the
  page's tokens: bars (label and figure over the bar, a mark for a limit),
  columns, a line (one of zeros is data, never No entries.; 2026-10-20), and a ring only for two to five parts of a whole (else
  bars), and a `meter` ring for one share of two parts (2026-10-12). Options:
  bars `inline` (label, bar and figure on one line; a row's `part` red at
  the bar's end), pie `total` (the whole in the middle) and status `tone`s
  on its slices, columns `labels` (the figure over each) and a category's
  `tone`; a row of columns or a line keeps every label its own width holds,
  else every second, else every third, counted back from the last, measured
  on the chart (`fitLabels`), never on the pane, so months never run
  together in a narrow card beside another (2026-10-27, the iPhone Duo). `ADspaceChart.spark(values, tone)` is a tile's trend, an image its
  words already state. The figures fold under every chart as a table; a
  column, a point and a slice give their figure on hover or a tap. No chart
  library.
- `js/acts.js` (`ADspaceActs`) is the one table of act glyphs and the one
  pending state (the user, 2026-10-10): every console `.btn` whose words are
  an act carries its mark (Publish the plane, Unpublish the struck eye,
  Edit the pen, Download the file, Copy the copy mark, Preview and Preview
  PDF the leaving mark after the words, Add and New the plus, Issue Letter of Offer the letter, Invite, an email sent and Send code the envelope, Use passkey the key, Open in Bukku the leaving mark after, Open {a console page} and View the chevron after; a quiet button as a filled one), given as the
  button is drawn where a screen wrote words alone; a form's own commit
  stays words; a way out (Preview, Download, Copy) and another way in (a
  passkey, a code sent) are never a commit, keeping the mark inside a form
  or beside a field. A press whose write disables its button shows, after 150ms,
  a turning ring in the button's ink at the button's width until it is let
  go. A new act joins the table, never a screen (`tests/acts.js`).
- `js/clock.js` (`ADspaceClock`: `day`, `today`, `parts`, `start`, `at`,
  `time`, `addDays`, `addMonths`, `between`, `weekday`; the words `date`,
  `clock`, `month`, English and Chinese) is Malaysia's clock (2026-10-12),
  loaded by the console and every client page: every page reads a day, a
  month, a weekday, a time of day and "today" from it, never from a Date's
  own getters, `setHours`, `new Date(y, m, d)`, `toLocaleDateString`
  without the zone (each the device's zone) or `toISOString().slice(0,
  10)` (the UTC day, yesterday before 8am here). A day alone (`2026-10-12`)
  is that Malaysian day; a date and time with no zone (a date field and a
  time field) is Malaysian time; a stored day keeps its form
  (`YYYY-MM-DDT00:00:00Z`). A client page writes a time 10:00am, no
  space (`clock(v)`; 上午10:00 with `zh`). Days are counted on the calendar, never by a
  device's midnight. Left as they are: calendar arithmetic in UTC on day
  strings, the report PDF's days (`dateOf`: the Malaysian day held as a
  local midnight), and the spreadsheet and CSV importers' own date reading
  (the user, 2026-10-12: never touched). `tests/myclock.js` holds Tokyo and
  Los Angeles across a month's end.
- `js/otp.js` (`ADspaceOtp`) is the code from an email typed as a box a
  digit (the user, 2026-11-11): the console's sign-in (`#authCode`), the
  client portal's (`#signCode`) and My records' lock (`#mineCode`), each an
  `input[data-otp-boxes]` kept as the value and laid unseen over
  `ADSPACE_CONFIG.signCodeDigits` boxes (8, Supabase's Email OTP length), so
  a paste, the iPhone's code from Mail and a screen reader meet a plain
  field; a whole code arriving presses the field's Enter once until it changes, never while an input method composes, the page's one check (2026-11-22: /creator/'s own second check sent each code twice).
- `ADspaceAPI.phoneWord` (`js/api.js`) is how every phone number reads,
  on every page (+60 12-345 6789, +60 7-123 4567, +65 8123 4567), whatever
  was typed (2026-11-18, the user: one portal showed 60167690532,
  0127106561 and +60 16-776 6878); a `tel:` link dials `+{waNumber}`. The
  stored value keeps what was typed; no page draws it raw (`tests/phones.js`).
- `ADspaceAPI.openStored(bucket, path, secs)` (`js/api.js`) is the one way
  a file kept in Supabase Storage opens: the tab at the press, a signed
  link, no opener, the tab shut on a refusal (the Handbook, a candidate's CV
  and documents, an HR document's sealed copy; 2026-11-19: Documents held a
  fourth copy, `tests/pwapdf.js`).
- `js/copy.js` says Copied one way. The fallback is `execCommand('copy')` over
  an off-screen textarea.
- `js/icons.js` (`ADspaceIcons.svg(name, cls)`, `platform(key)`,
  `journey(words, at)`) is the client pages' one icon set, the leaving mark
  (`out`, the drawing `js/acts.js` holds) and the chevron among them (outline glyphs at
  15px, stroke 1.8, in ink; never filled or coloured; a name it does not hold
  draws nothing) and the booking's one step track (`.cx-journey`), drawn
  alike on the selection page and the creator's page, its words `W.journey`
  in `js/words.js` (Booked, Shoot visit or Delivery, Draft due, Client
  review, Post date, Results; never a bare verb or a word that could read
  as one, the user, 2026-10-15), each breaking at its space, never cut.
- `js/words.js` holds every word two pages share (covers, statuses, actions) in
  English and Chinese, plus the tones (`W.TONE`, `W.tone`) and `W.dept` /
  `W.roleStd`.
  - Pages merge with `ADspaceWords.of({en, zh})`; `/review/` takes
    `ADspaceWords.en`.
  - The console's `STAGES`, `SV_STATE`, `RQ_STATE`, `RQ_KIND`, `OPTION_WORD`
    and `STATE_WORD` are built from it, never typed again.
- `js/captcha.js` is Turnstile (`interaction-only`, `flexible`, `theme` from
  `data-theme`).
  - One box per `[data-cf]` card; otherwise after the button's row (grid or row
    flex), else after the button.
  - The site key is `ADSPACE_CONFIG.turnstileSiteKey`. A token rides every
    emailed sign-in; where Cloudflare is unreachable the email still goes.
- A short month is `Sept`, never the browser's `Sep` (Safari): every English
  short-month format ends `.replace(/\bSep\b/, 'Sept')`, and My Work builds
  its dates from `MON_SHORT`.
