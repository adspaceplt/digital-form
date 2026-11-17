<!-- triggers: client/ js/portal.js -->
# Client portal (`client/`, `js/portal.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- A contact prefers English or 中文 alone (`client_contacts_lang_check`; no
  Malay portal, the user, 2026-11-17). Until this browser presses the 中文
  switch, the portal opens in the signed-in contact's own language
  (`get_portal` `me.lang`) and the selection page in its client's primary
  contact's (`get_campaign` `lang`, `client_lang`), never stored as a choice;
  /review/ and /script/ are English alone (`tests/portal.js`, `tests/client.js`).
- It is one client at a time (a company select where one login holds access at
  several). The head is the console record's (`.rec-mark`, `.rec-who`,
  `.rec-ctl`): the mark, the name over the registered name, the state and
  Request change, which asks which change as a segment (Cancel service, never a bare
  Cancel beside the sheet's own; 2026-10-31; 2026-10-27,
  POR-1): Change of details, Upgrade,
  Downgrade or Cancel, the last three against a confirmed line (`#reqPick`);
  a line's ⋯ asks for that line alone.
- Under it one tab strip (`#cpTabs`, the view strip, `role="tablist"`, the
  arrows and Home/End move along it) and one pane at a time
  (`.cp-panes`, `data-swipe="cpTabs"`, `data-narrow="640"`). The pane rides in
  `?tab=` (Overview left out) and pushes history; a refresh lands on it. Every
  section is a white card (`.panel.cp-card`) with its title inside
  (`.cp-card-head`); a table inside a card is the card's rows.
  - Overview: the summary on the left on the record's proportion (one column
    at 900): Services (Confirmed and To quote as lines, open requests),
    Next content meeting (the soonest ahead: a calendar leaf and the time in
    MYT, Join and Add to calendar, an .ics), Latest report (Download),
    Engagements (the token links with a tile, Open at the right edge); each summary card's
    View all opens its tab. On the right: Your account manager (the person in
    charge, WhatsApp and Email) and Company (the facts).
  - Services: confirmed and To quote lines (enquired never shown), with
    Upgrade / Downgrade / Cancel in a confirmed line's ⋯ and, for a line of
    two months or more, where its term is (Month n of N, ending); then Requests once
    one exists (Withdraw with Undo while Requested). A request sent opens
    this tab.
  - Letters: Download redraws the snapshot.
  - Content Review, Video Scripts and Creator Campaigns (one sign-in,
    `2026-11-08-client-portal-one-sign-in.sql`; the user, 2026-11-08,
    approving the portal's release 1): tabs after Overview, each drawn only
    once it holds something, read by `portal_work(p_client)` (the published
    sets with posts, approved, changes and waiting, the waiting count on
    the tab; the shared scripts) beside `get_portal`'s campaigns; each row
    its name over its month, its state, and Open, its page in this tab
    (`/review/?k=…#s-{set}`, `/script/?k=…#{id}`, `/creators/?k=…`). Opened
    by a signed-in contact of its client, the review and selection pages
    ask `portal_link_pass(p_kind, p_token)` (`ADspaceAPI.portalPass`): no
    access code is typed, the page decides as the contact
    (`ADspaceDecide.sign`: Deciding as {name}, no Change or Forget), Back
    returns to the portal's tab, and trigger `portal_decider_stamp` files a
    decision on `reviews` or `option_reviews` under the contact's own name
    whatever name was sent. A link opened with no sign-in, or by a
    colleague, asks its code as before.
  - Reports and Meetings: tabs drawn only once there is one; an address
    naming one before it is drawn opens it when it is. A meeting ahead with
    a link offers Join on its row, never in a ⋯ (2026-10-20, POR-2).
  - Account: Contacts read-only, Portal access (Person · Sign-in email),
    Payment only once `ADSPACE_ORG.bank` is set.
- The portal never writes a record. A request is a row the team applies.
  Request change opens through `js/sheet.js` (focus held, Escape, focus back
  to the button, a press outside never closes it over typed text), and an
  unsent note comes back when it opens again until it is sent (audit F8,
  2026-10-10). Send keeps one key until the request is filed
  (`portal_request_once`, audit C1), so a reply lost on the way and a second
  press file one request; `portal_request` is the same with no key.
- A sign-in address is text, never a mailto pill.
- Covers: Client sign-in, Check your email, Access denied, Unable to load.
- A contact reads its name with Primary contact at the right of the line, the
  role under it, then the reach chips; who signs in is said once, under
  Portal access. A past meeting is Completed (已完成), a future one Upcoming.
