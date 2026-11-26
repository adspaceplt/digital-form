<!-- triggers: css/ js/ admin/ client/ creators/ creator/ review/ script/ verify/ card/ quote/ details/ feedback/ supplier/ careers/ demo/ index.html 404.html docs/PAGE-TEMPLATE.html img/ js/file-sw.js -->
# Pages, chrome, boot (CLAUDE.md §2)

Moved whole from `CLAUDE.md` §2, which keeps a one-line pointer here; read whole before changing a page's head, bar, foot, cover, favicon or share card, the console's boot, its worker, the build line, or adding a page.

- `js/chrome.js` is the only header and footer.
  - The mark comes from `brandLogo`, the kicker from `data-kicker`, the actions
    from `data-actions` (`lang`, `qr`, `push`).
  - Footer: left `© {year} ADSPACE PLT. All Rights Reserved.`; right `Terms of
    Service` → https://adspacestudios.com/legal/policies.
  - The footer is drawn with the header and sits last from the first paint
    (`.portalfoot { order: 1 }`). It moves to the end of body once the page is
    parsed. It is hidden while it precedes an open console.
  - A client page's bar reads left to right bell, sign out, 中文 (the page's
    own controls go in just before `#langToggle`), all one tonal family of
    one height and corner; the client portal's bar is sign out, 中文: no
    bell and no notifications there (the user, 2026-11-25). On a phone the name the page is for takes two
    lines, its label over it (`.brand-for-label`); under 400px the label goes
    (kept for a screen reader) and the name stays, ending in an ellipsis
    only where it cannot fit (the user, 2026-11-27, option A).
- Nothing moves after first paint.
  - The mark's ratio is kept in `localStorage` `adspace-logo-ratio` and drawn at
    that ratio (`aspect-ratio: auto R`).
  - On a first visit `.brand.is-waiting` hides the brand until the mark loads or
    fails (at most 2.5s). `ADspaceChrome.mark()` reserves the rail's mark the
    same way.
  - `data-boot` from the head script (off an `sb-*-auth-token` key; removed by
    `gate()` or a 4s timeout) paints signed-out white and signed-in without a
    sign-in bar.
- `.topbar .brand-logo` is `flex: 0 0 auto; max-width: 60vw`, because Safari
  drew it 0px wide. Safari cannot run in the sandbox; the user confirms on an
  iPhone.
- `loadMe` asks `me()`, the business figures, the system accounts, the VIC
  clients and the departments at once, never one after another
  (2026-10-26); a `me()` asked again after a session refresh asks the VIC
  clients and departments again under it.
- The console fetches a section's scripts on first ask (ON DEMAND,
  2026-11-22): a section script is never a tag of `admin/index.html` but a
  line of its `#lazyScripts` (address with `?v=`, `first` what it reads as
  it loads, `uses` what it calls; `tests/lazy.js`; a script is added only
  once its `first` have run, so a failed fetch leaves those after it to be
  fetched again, 2026-11-24); `showSection` draws
  `#consoleBoot` until `sectionJs` is held, leaving the address alone; an
  always-loaded script calling a listed global asks `ADspaceAdmin.need`,
  `needThen` or `whenSection` first, and what it decides before any section
  draws (who may open a section, a record's address) and what it does for
  every section (a ⋯ shut on a press elsewhere) is its own, never a listed
  script's (2026-11-22: Content Review read `laman-citra` as an id
  and Analytics left the rail, crm.js and analytics.js not yet fetched).
- The console boots as `.console.is-booting`: its own shell and rail with the
  contents hidden and a skeleton (`#consoleBoot`) until `me()` answers.
  `applyAccess()` removes it. A refused team row goes to Access denied; a
  `me()` that errors is asked again once after `refreshSession()`, and an
  error still standing reads Unable to load with Try again, never a console
  drawn with no access read. Never draw the client pages' bar in its place.
- `/`, the front door: `docs/rules/front-door.md`.
- The favicon on every portal page is the ADspace wordmark in Optima on white
  (never the monogram): `/favicon.ico` (16, 32, 48), `img/favicon-{48,96,192}.png`,
  `img/apple-touch-icon.png` and `img/icon-512.png`. A link sent to a
  client or a creator (`review/`, `creators/`, `creator/`, `script/`,
  `client/`, `verify/`, `quote/`, `details/`, `feedback/`, `supplier/`, `careers/`) names no share image, so WhatsApp reads it as its
  title and address as it does a Google Drive link (`twitter:card` summary;
  the user, 2026-10-12, `tests/seo.js`); the console and the namecard keep
  `img/share-1200.png` (1200×630, `summary_large_image`): the wordmark in
  Optima over Digital Portal in Slate Regular, on white. No icon
  hangs on the CDN.
- Only `/` may be listed: every other page carries noindex, `robots.txt`
  disallows nothing (a blocked page's noindex cannot be read), and
  `sitemap.xml` names `/` alone (`tests/seo.js`).
- `404.html` is the portal's cover:
  - English only, white, the cover family's own type and glyph (a document
    with a question mark);
  - Visit website and Contact support (its envelope) as tonal halves, no
    Client sign-in (the user, 2026-11-22); the portal's foot as static markup;
  - no `noscript` redirect.
  - The front door and the 404 are in the uxaudit walk.
- One `.cover` for every full-page state (no link, bad link, access code,
  closed, confirmed, nothing to review, access denied, the console's
  sign-in, a quotation waiting for the team), drawn as the cover family
  (DESIGN.md §4 Full-page state), with the same words on
  every client page (`js/words.js`). Where the browser holds a sign-in (the console, the
  client portal), every cover ends Reference {code}, the sign-in's code as a
  colleague's Devices block cuts it (`ADspaceAPI.sessionCode()`: the access
  token's `session_id` claim, no request; `sessionShort`, the one cut, Devices
  too), drawn by one watcher in `js/maintenance.js`; signed out, or on a
  public page (/verify/, /quote/, a link's page) whatever the browser holds,
  no line; never the token (`tests/covers.js`).
- The console's sign-in page and every cover are white to the edge
  (`body.is-plain`); the grey frame is the signed-in console's alone (the
  user, 2026-11-13: "fully white would be ok"). Client pages stay as they
  are, never v3 (the user, 2026-11-13).
- Malaysia's clock (`js/chrome.js`, 2026-10-12; the user: "this entire
  portal should follow the timezone of malaysia"): a device whose clock is
  not GMT+8 (Malaysia and Singapore share it) is told on every page that
  loads `chrome.js`, under its bar (`#tzBar`, `.tzbar`, the warn ground led
  by the amber dot; in the console's column, edge to edge under a client
  page's bar): Time zone difference detected: this device is on GMT+9
  (Asia/Tokyo). The portal follows Malaysia time (GMT+8)., in Chinese after
  the 中文 switch; its × hides it for the visit (`adspace-tz-hide`). An
  automated browser is not told unless it sets `window.__tzBar`
  (`tests/tzbar.js`).
- Every page carries `viewport-fit=cover`. Sheets, feet, the confirm bar, the
  console body and the rail pad by `env(safe-area-inset-*)`.
- On iOS alone, `js/chrome.js` adds `maximum-scale=1` (stops the focus zoom,
  keeps pinch).
  - Never on Android.
  - Never `user-scalable=no`.
- Under a coarse pointer `.console-head` takes `--chrome-solid` with no
  backdrop filter, because Safari colours the status bar from an opaque bar.
  A client page's `.topbar` is opaque there too (`--chrome-solid`;
  its glass, kept 2026-10-10, read grey behind the status bar on 2026-11-14),
  the root painted `--card` so the status bar takes white, never the grey page. The console's root
  is painted `--chrome-solid` under a finger too: WebKit colours the status
  bar from the root's background, never the head (2026-11-14). The `theme-color` meta follows the console's own theme (the head script
  and `wearTheme()`); client pages are white.
- A plain console page (sign-in, its code step, every cover, the
  whole-screen Upgrade, `admin/offline.html`) is one ground from the
  browser's toolbar down: its bar, its root and the `theme-color` meta take
  `--card` in both themes, the signed-in console `--chrome-solid`, set from
  the tokens by `wearToolbar()` on every `is-plain` or `is-maint` change,
  both ways (2026-11-25, `tests/covers.js`).
- The bar is two families: the console's `.console-head` (`css/console.css`)
  and every client page's `.topbar` (`js/chrome.js`, `css/portal.css`), one
  height, `--head-h` (64 at a desk, 56 on a phone), the console's signed-in
  head too; no page sets its own (the user, 2026-11-21); a
  change to one is checked on the other in the same push (2026-11-14: the
  status bar fixed on the console reached the client pages a release later).
- The console is a PWA:
  - `admin/manifest.webmanifest`, with scope and start `/admin/`;
  - wordmark icons in `admin/icons/`.
  - iOS draws a launch picture before the page's first byte
    (`apple-touch-startup-image`, `admin/launch/`): the wordmark over
    Digital Portal on white or the dark ground, one a device size and
    orientation, dark lines first; a size with no exact match is a blank
    screen, so a new device is added through `tests/launch-build.js`
    (`tests/launch.js`). iOS takes it when the app is added to the Home
    Screen.
- The phone tab bar (`#tabBar`): `docs/rules/tab-bar.md`.
- Arrange sections (`#railSheet`): `docs/rules/tab-bar.md`.
- Settings (`?s=settings`, `js/settings.js`): `docs/rules/settings.md`.
- `admin/sw.js` keeps `offline.html` and the wordmark for a page load that
  failed, and every same-origin file whose address carries `?v=`
  (`adspace-console-assets`), answered from the store first, one copy a
  file, the copy under an older stamp let go when the new one is stored
  (2026-10-26: a reopen after ten minutes asked the server about 69 files).
  The page itself always goes to the network (navigation preload on), and
  an unstamped file is never kept: a changed file without a new stamp would
  be served stale, so the `?v=` bump below is load bearing. It also holds a
  PDF the console drew, for an hour, at `/admin/file/` (`js/file-sw.js`,
  `adspace-files`; see `ADspaceDocs.save`). `client/sw.js` holds that
  alone, at `/client/file/`, registered by `js/portal.js`. A failed
  registration is silent.
- The rail's foot names the build with Settings' and the Activity record's marks (`#appVersion`,
  `.appver`, 11px mute): `{YYMMDD}.{commit}`, the deploy's day in
  Malaysia and the last four of the merge commit's seven-character short
  hash (`dcd08c6` reads `08c6`, never the full hash's last four) as one token
  (`261006.b43a`; the user, 2026-10-06: short, but which build; 2026-11-17:
  shorter), read from
  `/version.json` (its name and hover hold all seven characters), which the Pages build writes through Jekyll
  (`site.github.build_revision`, `site.time`); never typed by hand. Read raw
  (no build) or missing, the line is hidden (`tests/appver.js`). The line is
  Refresh app (the user, 2026-10-12): a button drawn as its words (no box,
  no underline, the mute ink, the soft ink on hover), the line's height its
  target, named `Refresh app, {build}` for a screen reader and on hover; the
  account menu holds no Refresh app.
- Refresh app (the build line):
  - it unregisters the console's own worker (`/admin/`) and empties its own
    caches (`adspace-console-*`, and `/admin/file/` in `adspace-files`),
    never the creator's, the selection page's or the client portal's
    (audit F7, 2026-10-10);
  - it never touches localStorage, IndexedDB or the sign-in;
  - notifications survive it: the next load subscribes again without asking
    (`ADspacePush.heal`, off the `adspace-push:{scope}` flag).
- The latest build (`#buildBar`, Require latest version): `docs/rules/portal-notices.md`.
- Pull to refresh works only in the installed app, and only on a list with no
  record, sheet or menu open.
- Page availability (`js/maintenance.js`): `docs/rules/portal-notices.md`.
- Announcements (`js/announce.js`): `docs/rules/portal-notices.md`.
- Notices (`js/notice.js`): `docs/rules/portal-notices.md`.

- Public holidays (`public_holidays`): `docs/rules/settings.md`.
