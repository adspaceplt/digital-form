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
- 2026-11-26, `hiringiv` (the five list fixes, which touch neither
  Settings nor Hiring's settings): "its Edit opens the figures, the reply
  time among them" fails at 1280 and 390, and failed the same on the
  branch's base (c881fdb, main with #1479, Settings sheets on one line):
  the Time limits sheet no longer reads its three figures' words as the
  suite asks. Held here until it ships.
- 2026-11-26, `hiringheld` (the unslop pass, which touches no Settings
  sheet): "its Edit asks the decision time" fails at 1280 and 390, as
  `hiringiv` does, from #1479's relabelled Settings sheets.
  Held here until it ships.
- 2026-11-26, `weight` (review fixes S4, whose always-loaded scripts are
  108 bytes smaller than main's by gzip): the console reads 1328.8 to
  1328.9 KB against its 1328.8 KB budget on main 2800345 itself; the
  hiring Settings sheets (`hiringheld`, `hiringiv`: no decision or reply
  time field under its old label) fail the same on main, likely from
  #1479's relabelled sheets. Held here until they ship.
- 2026-11-26, `pdfreal` (the Build quote and TERMS fit train, which
  touches no letter): the Letter of Offer and the client letter (sign,
  nosign) fail "its head and foot at the template's places on every
  page" (the foot's reference at 6pt, 794.5 down); the same three fail
  on main 8e9224f. Held here until it ships.
- 2026-11-26, `sql` (the received page's centring, which touches no
  function): "the schema's last wa_compose_prepare is this one, refusing
  feedback to a lead…" fails since F8 (#1504) redefined
  `wa_compose_prepare` after that band. Held here until it ships.
