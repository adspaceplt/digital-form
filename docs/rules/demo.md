<!-- triggers: js/demo.js demo/ -->
# The demo (`js/demo.js`, `demo/`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-22 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- The demo (`js/demo.js`, `2026-10-27-demo-access.sql`; the user,
  2026-10-27: "fake populated data unable to add anything … so i can sell
  ppl this portal", "Just enter in the email input"): four to eight digits
  in the sign-in's email box are asked of `demo_pin_ok` (anon, true only
  while Demo access is on and the PIN right, wrong ones counted as a
  link's passcode, `link_passcode` kind `demo`); the box takes an email
  address or that PIN alone: a wrong PIN and any value that is no address
  read Enter a valid email address., the same words, so the box never says
  a PIN exists (the client portal's sign-in refuses one alike). A right PIN keeps
  `adspace-demo` in this browser for twelve hours, and the head then loads
  `demo/seed.js` (a made-up agency, Sample Studio, its six colleagues and 48
  clients over two years, built on every load relative to today) and
  `demo/engine.js` (the stand-in, `tests/demo-build.js`) in place of the
  database, which the page never reaches again. Signed in as the sample
  director; every write refused (a table's insert, update or delete, a
  function whose name changes something, an edge function but Bukku's
  invoices read, which the engine answers with none held, an upload) with
  Demo: changes are not saved.; the mark, letterhead, foot and title the
  sample agency's; a bar over the console (`#demoBar`, the upgrade line's
  look) with Client pages (a menu of the client portal, Content Review, the
  creator selection, a creator's page, Video Scripts and a namecard, each
  on its sample link in a tab of its own, so nobody needs an address; the
  user, 2026-10-27) and Exit demo, which Sign out does too. The client pages
  (`/client/`, `/review/`, `/creators/`, `/creator/`, `/script/`, `/card/`,
  `/verify/`)
  load the same while it stands: the client portal signed in as a sample
  client's main contact (`client@example.com`), the rest on their sample
  links alone, each key holding a 0 that no real key's alphabet holds
  (`demo0r…`, `demo0c…`, `DEMO0…`, `demo0s…`, `demo0…`), so a real link
  opened while the demo stands is the real page; `/verify/` loads it for
  any reference (Verify document in Client pages opens it on the sealed
  sample's), answering the seed's January 1988 documents alone, a real
  reference Not found, and File check matching only a copy of the sealed
  sample the demo console drew (`adspace-demo-seals`, the hashes it handed
  out; the user, 2026-11-20, option A); each under the bar edge
  to edge (`.annbar.demobar`; the namecard has no bar); the creator's page
  opened bare, with no code kept, opens a sample creator holding a booking,
  and Exit demo lets go of a sample code it kept; signing out of
  the client portal returns to the console. A demo whose sample data did
  not arrive takes the real library away, never the real database: a client
  page reads Unable to load under the bar, the console Unable to load with
  Exit demo on its signed-out page; Sign out in the demo is Exit demo, never the
  console's clearing of the colleague's notes and drafts; a sheet's draft
  is let go as the demo starts and ends (audit, 2026-10-27). The sample data
  holds no registration a company could hold (zeros) and no real handle
  (`.sample`), and the demo opens no chat, call or profile (wa.me, `tel:`,
  Instagram, Facebook, TikTok, rednote), saying so in its bar; the client
  pages' guides it marks met are listed (`adspace-demo-guides`) and offered
  again on Exit demo (2026-10-29). Settings, Portal: Demo
  access (`team.settings`): On / Off and a PIN, a new one 6 to 8 digits
  (one of 4 or 5 set before keeps opening; audit 2026-11-15), kept as a
  bcrypt hash (`demo_state`, `demo_set`: `bad-pin`, `no-pin`; a new PIN
  clears the demo's wrong tries and locks), filed
  `team.changed` under Demo access, never the PIN.
