<!-- triggers: workers/links -->
# Short Links (`workers/links/`, `hi.adspace.me`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- The Worker reads `link_resolve(p_slug, p_qr)` with the anon key and gives one
  of four answers (ok, missing, paused, revoked).
  - Redirects are 302 and `no-store`.
  - The client's parameters are carried over, minus `q`.
  - `go.adspace.me` is never retired: printed QR codes encode it.
  - The host is `ADSPACE_CONFIG.linkHost`.
- A live link's row offers Copy, Open (its short address, a new tab), QR
  codes and the ⋯ (LNK-2, 2026-10-22), four fixed tracks on a phone
  (LNK-8). The Worker keeps which kind an `/s/`
  key is a day at its edge (`caches.default`, a kind the database named
  alone), so a person's visit is sent on without a read (LNK-3).
- Bulk import is behind the bar's ⋯ (`data-rare`) and is a sheet (`#importBox`, `links:work`, as the QR sheet's
  Create, Revoke and Restore): every line taken shuts it; a skipped line stays
  in the box.
- Pause and Resume live in the ⋯ (`links:work`).
  - Pause asks first; Resume asks nothing.
  - Both take `.select('id')`, filed as `shortlink.updated` with the detail.
  - `ADspaceGroup.keep` opens the card the row moves into.
- No Status column. A paused link stands in the Paused card, which says
  it once: no chip on the row (2026-10-27, LNK-10).
- Every colleague's namecard slug is listed under Namecards, between Live and
  Paused (read from `team_members`; Short link, Destination the card's own
  address, Colleague; Inactive or Card off as a chip; Copy and Open, no ⋯:
  edited in Team or My namecard), so a slug in use is in sight; the count
  takes them in and the search finds them by slug or name; a refused read
  is said (Could not load the namecards.), never drawn as none (the user,
  2026-10-07).
- After Live, Namecards and Paused, the list shows the addresses the host
  answers by itself (2026-10-14; the user: "there should have a place to see
  all hi.adspace.me/{slugs}"), each a card shut until opened: Content
  Review (`/r/{key}`, an Active client in Content Review), Video Scripts
  (`/v/{key}`, `/s/` before 2026-10-15, read through `script_links()`: the key is withheld from the
  table, `2026-10-14-script-links-list.sql`), Creator selection (`/s/{key}`, `/c/` before 2026-10-15, not a
  draft; Completed as a chip) and Creator pages (`/p/{code}`, Inactive as a chip); each read only
  where its section (or `campaigns.creators`) is at View, a failed read
  `Could not load the {group} links.` with Try again; Copy and Open, no ⋯
  (changed where the record is). The count and the search take them in.
- A short link never takes a colleague's card slug (`links_card_clash`,
  named `/{slug} is a colleague's namecard.`).
- A slug, a short link's or a card's, is three characters at least
  (`links_slug_min`, `team_card_slug_min`, `2026-10-14-slug-three-characters.sql`;
  the user, 2026-10-14): every one and two character address on the links
  host is the portal's own. A card's slug made from a short name takes the
  sign-in email's name, else the name with `card` after it.
- A client's review link as a short link (2026-10-12; the user: "dynamic
  title: {Content Set} {client brand name} - Content Review Portal by
  ADspace"): `/r/{review key}` and `/r/{review key}/{first eight of a set's
  id}`, nothing stored, so nothing to clean up. A link preview's reader (a
  chat app's user agent) is answered a page titled `{set} {brand} - Content
  Review Portal by ADspace` from `review_link_preview(p_key, p_set)` (anon;
  a live key with no passcode, shown in Content Review; a published set),
  with no image; everyone else a 302 to `/review/?k={key}#s-{set}`, which
  opens on that set alone, unfolded, and takes the mark out of the address
  (`tests/links.js`, `tests/reviewlink.js`).
- The other links a client or a creator is sent, as short links the same
  way (2026-10-13; the user: "video script and creator campaigns and creator
  portal"): `/s/{selection key}` a campaign's creator selection, `/v/{script
  key}` a client's Video Scripts, `/p/{creator code}` a creator's own page,
  and `/c` alone the client portal's sign-in (re-lettered 2026-10-15, the
  user: "use v for video script, take s back for selection", "C reserved
  for client portal"; `2026-10-15-short-links-relettered.sql`). A link sent
  before keeps working: `/s/` a Video Scripts key opens the scripts
  (`share_link_preview` `which`), `/c/{key}` its campaign. The console
  writes the new letters once `shareLetters` is on in js/config.js (the
  Worker live first), `ADspaceAdmin.shortLink(kind, …)` by kind
  (`campaign`, `script`, `creator`). A preview reader is
  answered from `share_link_preview(p_kind, p_key)` (anon): the brand for
  scripts (a script published), the campaign and the brand for a selection
  (no access code, not a draft) and for a creator with one open booking,
  else the plain title. The console's address and Copy link give the
  page's full digital.adspace.me link (the user, 2026-10-15: "full links
  everywhere except namecards"; `shareLinks` off in js/config.js, which
  `ADspaceAdmin.shortLink` and `shareUrl` read), and a namecard keeps its
  short link; the Worker still answers every short link already sent.
