<!-- triggers: tests/ -->
# Logged defects (STANDARD.md §24)

Moved whole from `STANDARD.md` §24, which keeps a one-line pointer here. Read when a suite fails in code a release did not touch, and add the entry here.

Found by a test in code a release did not touch; fixed in the next release
and removed here when it ships (`CLAUDE.md` §1, one request, one release).
None open (2026-11-17: the thirteen logged were fixed at their cause or
found already passing on main; the story is in `docs/DECISIONS.md`, The
verification loop); the five found on 2026-11-18 fixed 2026-11-19; the
demo quotation's ADspace lines (2026-11-20) fixed 2026-11-21.
- 2026-11-21, `demo` (found running switched-off acts, release B, which
  touches neither file): "no page error" once read `window.__demoSeed is
  not a function`, the engine (`demo/engine.js`) run on a page whose
  `demo/seed.js` had not arrived; the same run again passed. Its cause (a
  seed request cut off by the suite's next navigation, or a seed load that
  failed) is to be found; held here until it ships.
- 2026-11-24, `demo` (the audit function release, which touches neither
  Analytics nor the stand-in): at 390 `s=analytics&tab=clients` read
  Analytics could not be loaded while 44 suites ran, and passed alone at
  once; likely the same cause as the 2026-11-21 entry above. Held here
  until it ships.
- 2026-11-24, `crm` (the audit database release, which touches no page):
  "the Clients list's Last seen" timed out waiting for `.crm-c-seen` on
  Laman Citra's row while 44 suites ran, and passed alone at once. Its
  cause (a wait the list's first paint outruns under load) is to be
  found; held here until it ships.
- 2026-11-25, `hiringsql` (the section email templates release, which
  touches neither hiring nor its functions): "an interview never moved is
  refused the time-changed email" failed once while 40 suites ran
  (`hiring_mail_prepare` answered other than `not-moved`, then
  `careers_read` answered no interview), and passed alone at once and in
  the same release's earlier run. Its cause (the interview's slot or a
  read meeting the suite's next step under load) is to be found; held
  here until it ships.
- 2026-11-25, `quotes` (the forms in steps release, which touches no
  console page): at 390 "a page ready … not reached in 10s" after "the
  check names a code sent to an address outside Contacts" while 35 suites
  ran, and passed alone at once; likely the load cause of the entries
  above. Held here until it ships.
- 2026-11-25, `outstationsql` (the trip card's stop mark release, which
  touches no SQL): while 17 suites ran, the second photo on a stop
  (`outstation_photo_add`) answered without its trip, so the suite threw
  reading `stops` at line 302; it passed alone at once. Its cause (the
  answer under load, or a refusal the suite does not name) is to be
  found; held here until it ships.
- 2026-11-27 (05:50 MYT), `sql` (the interview missed release, which
  touches neither `quote_wa_allowed` nor its migration): "the day's
  Quotation ready messages to website quotations are held to the setting"
  read a third send the same day as still allowed (`a2` true). Run inside
  the 00:00 to 08:00 MYT window; likely the day counted on UTC's
  calendar. Held here until it ships.
- 2026-11-26, `sql` (the received page's centring, which touches no
  function): "the schema's last wa_compose_prepare is this one, refusing
  feedback to a lead…" fails since F8 (#1504) redefined
  `wa_compose_prepare` after that band. Held here until it ships.
- 2026-11-27, `uxaudit` (found walking main 631aaf2 for the page weight
  release, which touches neither Settings nor Content Review): the walk
  clicks `#setList [data-a="holidays"]` after choosing the Portal group,
  and the button is never visible there (Public holidays is now listed
  under another group), so the walk stops at Settings and Public holidays'
  `holYearStrip` is measured at no width; and `csStrip`, a strip #1523
  added, is not named in `STRIP_NAMES`. Held here until it ships.
- 2026-11-27, `quotesite` (the ad budget hotfix): a /quote/ start date
  before today is refused twice, `js/form.js`'s date note ("Choose a date
  from …") under the field and `#qsStartOnMsg` ("Choose a preferred start
  date from today onwards.") under that, one fault said twice. Held here
  until it ships.
- 2026-11-27, `copyscan` (the same release): a word-table line holding a
  semicolon (`fullBrand` in `js/quote.js`) is not listed, so the copy
  review never reads it. Held here until it ships.
- 2026-11-27, `crm` (QUOTE INTAKE's affected run, 112 suites at once):
  "a written next action still wins" failed once under the full run's load
  and passes alone on the same commit; the check reads the next step before
  the record repaints from the seeded touch. Held here until its wait is
  fixed at the cause.
- 2026-11-27, `settings` (the same release's re-run): "Sign-in and codes:
  its Settings row counts its templates" read an empty count once (its
  5-second wait for the row's line) and passes alone on the same commit.
  Held here until its wait is fixed at the cause.
- 2026-11-27, `demo` (CONFIDENTIAL-LINE's affected run, on main a8b2820
  merged in): "demo/engine.js is the stand-in of today" fails on main's
  own engine: it holds a website request's console Save
  (`qq.source === 'console' ? qeSel …`) that `tests/stub2.js` on the tests
  repository's main (f69f372) does not yet, so a rebuild from today's
  stand-in would take that behaviour out of the demo. Not rebuilt here.
  Held until the stand-in and the engine agree.
- 2026-11-27, `pdflibhash` (QUOTE REQUEST DELETED's affected run): its
  wait for `ADspaceDocs.lib` times out at 10s, the same on `main` (230ae41)
  as on the branch; the PDF libraries, untouched by that release. Still
  failing in the full gate of 2026-11-27 on main 7c85e8b. Held here
  until it ships.
- 2026-11-27, the day's full gate on main 7c85e8b (tests 1d34edb, 5,365 s,
  263 suites passed; `taxcodes` passed, its entry removed; `sql` 600 s):
  - `adsreport`: at 390 the Ad IDs card docks 54px from the right edge,
    not 16 (`{"left":16,"right":54,"bottom":92}`); likely a stylesheet
    change of 26 to 27 Nov (#1530, #1538 or #1544), not pinned.
  - `uxaudit`: the walk times out clicking `#crmLogAll` (the client
    record's Activity View all), never visible on the seeded client, so
    the walk stops in Clients and nothing after it is measured; likely
    #1560 (history kept by client id) or #1525, not pinned.
  Held here until each ships.
- 2026-11-27 (night), the day's full gate on main fb3b4e8 (tests 897269e,
  5,807 s, 277 suites passed, 6 failed). HANDOVER: snapshot fb3b4e8,
  277 passed / 6 failed, total 5,807 s; G2's fixes for `adsreport`,
  `uxaudit` and `pdflibhash` are not on main at this snapshot (none
  merged after #1574):
  - `adsreport`: "FAIL at 390 the Ad IDs card docks at the foot inside
    the gutters {"dock":true,"left":16,"right":54,"bottom":92}"; the
    entry above, not pinned.
  - `uxaudit`: "locator.click: Timeout 30000ms exceeded … waiting for
    locator('#crmLogAll')" (resolved, never visible); the entry above,
    likely #1560 or #1525, not pinned.
  - `pdflibhash`: "FAIL page.waitForFunction: Timeout 10000ms exceeded.";
    the entry above, not pinned.
  - `upgrade`: "FAIL the sheet lists every page in its group, the system
    pages last, each Available" (heads end `Other pages`; the suite reads
    `System pages`); #1565 renamed the group.
  - `overdue`: "FAIL 1280 no id is held twice on the console crmLinks"
    (and at 390); #1581 (the client's Services tab short links).
  - `quoteintakesql`: "FAIL app_settings_set is the schema's last
    definition, from 2026-11-27-ad-spend-figures.sql"; a later migration
    redefines it, likely #1575 (`2026-11-27-creator-bill-on-completed.sql`)
    or `2026-11-27-quote-details-asked.sql`, not pinned.
  Held here until each ships.
