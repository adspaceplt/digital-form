<!-- triggers: js/team.js js/delreq.js js/admin.js supabase/ -->
# Access

Moved from `CLAUDE.md` §2, Access, on 2026-11-23.

- Access is a level per section, **none < view < work < manage**, in
  `team_roles.access` / `team_members.access`. `allowed(section, level)` is
  every policy's predicate; `allowed_of(member, section, level)` answers
  the same for another colleague (who a bell tells), never a raw read of
  `access ->> part` (`2026-11-24-saved-whole-and-told.sql`, `tests/wholesql.js`).
  - The page names them Off, View, Edit, Full control (`LEVELS` in
    `js/team.js`; the access restructure, 2026-11-17); the stored keys
    never move.
  - One rule, top to bottom (`2026-11-17-group-switches.sql`, plan version
    4): a portal switch (Business settings `ai_on`, `email_on`,
    `whatsapp_on`, set by `portal_switch_set` at `team.settings`, on from
    the start), then the group's switches (`team_roles.ai_on`, `email_on`,
    `whatsapp_on`, `sensitive_on`, copied onto each colleague by
    `team_role_defaults`, an admin holding all; Use AI, Send email, Send
    WhatsApp, Sensitive details, with Clients they see and Reports to
    (`reports_to`, never round to itself, `reports-loop`) under Main
    settings), then the section, then a tab, which never exceeds its
    section in `allowed()` and the page's `level()` alike (a granted part
    aside). AI off answers `ai_cap` 0; a send off refuses `send-off`: a
    send by hand asks `send_ok` / `send_ok_of` (`2026-11-21-send-switches.sql`:
    the portal's switch, then Send by email `client_email_on` or Send on
    WhatsApp `client_wa_on` (`manual_send_on`, `manual_send_set`), then the
    group's), every email or WhatsApp a colleague sends by hand alike (each
    email's prepare or begin, Send again, `wa_may_send`, a quotation sent on
    WhatsApp); an automatic send asks `auto_send_on` (the portal's switch and
    Automatic emails or Automatic WhatsApp); a sign-in code, an invitation
    and a verification code ask none. Sensitive details shuts client
    billing, creator payment details and supplier bank details, the two
    payment parts following their section. The page asks `may('use.ai')`,
    `may('send.email')` and `may('send.whatsapp')` (the group's alone: not
    permitted, the act is hidden; `:root.no-ai` hides every button carrying
    the AI mark (`svg.ai-mark`) and the Assistant). An act Settings or a
    daily limit stopped carries `data-gate` (`email`, `whatsapp`, `ai` or
    `ai:{use}`, `bukku`, `meet`, `meta` or `meta:checks`, `quotewa`; several
    space-separated, the first that stops it said; a button holding the AI
    mark is `ai` by itself) and,
    while `ADspaceAdmin.gateState(key)` reads it off, `js/admin.js` draws it
    disabled, a press, hover or focus opening `#gateWhy` with what stopped
    it and who can change it: the portal's switch, the send by hand under
    it, the portal's AI, the use's daily limit (`ai_uses_left()`, read as an
    AI act is drawn, again as one is redrawn after 30s and on return), Bukku
    not connected (`bukku_ready()`: no nightly read in three days), Meta
    checks off, Website quotations at 0; Google Meet, Meta and Bukku
    answering that they are not set up is heard once for every call
    (`functions` wrapped in `js/admin.js`) and kept an hour in this browser
    (`adspace-gate-off:{key}`, `ADspaceAdmin.gateLearn`); a link the team
    hands out (`data-page-link` on its tools) says under it while its page
    is set Upgrade in progress or Temporarily unavailable, now or ahead
    (`ADspaceMaintenance.pages()`), the link still copying; what the
    portal sends by itself warns where the team relies on it
    (`ADspaceAdmin.autoOff`, a `.msg.warn` line: an open campaign's Client
    link, Add task under Task reminders at 0) and the step still stands
    (`tests/sendswitch.js`, `tests/switchstate.js`). The five
    WhatsApp parts and the billing and payment parts are gone, their stored
    levels taken off (`2026-11-17-access-cleanup.sql`). `access_keys` (RLS
    on, no policy, no grant) lists every key and its tier, and `allowed()`
    reads the granted parts from it; the page's one list is
    `ADspaceAdmin.GRANTED` (the Team panel reads it), held equal to
    `access_keys` and the stand-in by `tests/access.js`.
  - Select is view, insert and update are work, delete is manage, each a
    policy of its own: never one `for all` policy, since Postgres checks a
    delete against USING alone (one reading at View let View delete;
    `2026-10-08-delete-at-its-level.sql`, `tests/sql.js` §DL). A draft
    report's rows delete at Work, the report's own steps.
  - A Delete at Edit is a request (`js/delreq.js`,
    `2026-11-17-delete-requests.sql`; the user, 2026-11-17: "Full control
    deletes; Edit files a request an admin approves"): its ⋯ reads Request
    delete, the screen's own question adds a Reason, and the call the
    screen then makes (a function on `delete_kinds`, or a table's delete by
    its key) is filed by `delete_request_file` in its place (`denied`,
    `may-delete` at Full control, `bad-kind`, `bad-reason`, `already`,
    `too-many` past 30 a day, `not-found` outside client scope), the record
    left and every admin told (`delete.request`), Undo where it happened
    withdrawing it. An admin decides in Settings, Portal: Delete requests,
    or from its own mark at the rail's foot (`#delReqOpen`, an admin's
    alone, after Settings'; in More's foot on a phone), which carries the
    red dot while any request waits (More too), the Settings row reading
    n waiting in red; the count is `delete_requests_list` read with the
    sign-in reads and again at each read of the list (2026-11-17)
    (`delete_request_decide`): Approve asks first, then the page makes that
    same call as the admin and closes it (`delete_request_done`; refused,
    the request waits again with the refusal); Decline asks a note. The
    requester is told either way. A list's records (several tasks) and a
    kind with no name column (a report's version, a booking) are each held
    and named as the request is filed (`not-found` outside the requester's
    sight); an admin never decides a request they filed (`own`), and only
    the admin who approved one closes it (`not-yours`;
    `2026-11-17-deletes-and-builds-held.sql`). A new delete function or table joins
    `delete_kinds` and the stand-in's `DK` together. `delete_kinds` and
    `delete_requests` have RLS on, no policy, no grant (`tests/delreq.js`).
  - A Request delete press arms that one question alone
    (`js/delreq.js`; review 2026-11-24): the question must open within
    10 seconds of the press, a question shut unanswered disarms it, and an
    answered one stays armed 30 seconds for the screen's call; every task
    of a list request is within the requester's clients (`client_seen`),
    and a request another admin is approving is refused `approving` for
    ten minutes from their press (`2026-11-24-delete-requests-held.sql`,
    `tests/delreq.js`).
  - Every function named as a delete or a purge that removes rows asks
    Full control (`'manage'`) or an admin, a colleague's own item aside
    (`health_talk_delete`, `email_template_delete`, `hiring_doc_delete`);
    an admin tool's delete asks its granted part at Full control and is on
    `delete_kinds`, and a request against a granted part asks `ops_granted`,
    never the section `allowed()` falls back to
    (`2026-11-27-deletes-at-full-control.sql`, `tests/sql.js`). A Delete
    drawn as a button carries `data-g="6"` and its `data-need` as a ⋯ item
    does.
  - The levels are drawn on reversibility (add, edit and publish are
    reversible; a permanent delete is not), never on CRUD verbs.
- One user group per person (`team_roles` → trigger → `team_members`); no
  per-person switches. A policy on `team_members` never queries itself; it
  takes inserts and updates at Team Full Access (`team_insert`,
  `team_update`) and no delete from any page
  (`2026-10-18-colleague-row-never-deleted.sql`): a removed colleague is
  deleted by `team_member_purge` alone (below).
- The group seeded as Account is named Marketing. Its slug `account` never
  moves.
- Sections: `ops` (My Work), `clients`, `whatsapp`, `review`, `scripts` (Video Scripts),
  `campaigns`, `reports`, `register` (Documents), `suppliers`, `links`, `services`, `team`, `activity`. The
  Handbook is not a section: every colleague reads it, an admin writes it.
- A part (`clients.billing`, `register.hr`, `activity.campaigns`…) answers with
  its own level where one is set, else its section's, in `allowed()` and the
  page's `may()` alike. Only exceptions are stored. A stored level equal to the
  section reads Same as section.
- Granted parts never inherit (`ops_granted()`, which stops answering the minute access ends as `allowed()` does; `2026-10-24-admin-tools-end-on-the-minute.sql`): `ops.all`, `ops.reports`,
  `ops.workflows`, `ops.time`, `ops.numbering`, `team.performance`,
  `reports.whitelabel` (on for Managers from 2026-10-07). Every act an admin
  alone could take is one (`2026-10-07-admin-parts.sql`; an admin's by
  itself, no other group given any): `ops.numbering` (Task numbering),
  `ops.override` (move anybody's task and its final date), `team.perfadmin`
  (`perf_is_admin()`: revenue and profit, Performance settings, a month's
  record removed, the department scores), `team.settings` (Business settings), `team.upgrade`,
  `team.invite` (asked by `invite-member` as the caller), `team.handbook`
  (the four functions and the bucket's add and remove policies),
  `reports.transfer`, `reports.ai`, `team.announce` (Announcements,
  2026-10-07), `register.types` (Document types, 2026-10-07) and
  `team.notice` (Notices, 2026-10-09) and `reports.meta`
  (Meta import and audit, 2026-10-10) and `campaigns.files_delete` (Delete
  approved files, 2026-10-10) and `clients.vic` (Mark VIC clients,
  2026-10-15) and `team.analytics` (Analytics, 2026-10-25) and
  `team.personnel` (Personnel, 2026-11-16) and `team.sessions` (Signed-in
  devices, 2026-11-20); each offers Manage
  alone (on or off), but `ops.outstation` (every outstation trip, read only,
  2026-11-23), which offers View alone. Team: Health (every colleague's answers by name) is
  no part: an admin's alone, never offered to a group (2026-10-18, below).
  `suppliers.pay` (Supplier bank details,
  2026-10-18) is granted too, at View (read) or Work (write). A
  new admin-only act is a granted part, never `allowed('admin')`. Their unset
  option reads `No Access`, and each offers only the levels the database checks
  (`PART_LEVELS`). A stored level outside them is shown and saved as what it
  grants (`offered()`).
- `ops.list`, `ops.board` and `ops.calendar` follow My Work unless set to No
  access.
- A client's record has a part a tab (`2026-10-22-client-parts-for-each-tab.sql`;
  the user, 2026-10-22: "AMV quote, AMV Service Lines, AMV Issue documents"):
  Contacts, Billing, Quotations (`clients.quotes`: Build quote, the
  quotations, their PDF and WhatsApp send, the rate card read, a checklist's
  quotation), Service lines (`clients.services`), Letters
  (`clients.documents`), Requests, Calls and visits, Brand (`clients.brand`:
  the Brand profile, content brief and brand notes by trigger
  `clients_brand_guard`, `brand-columns`; Meta accounts; the Brand analysis)
  and Checklists (`clients.checklists`), each following Clients where a group
  sets none and named in the panel over one line of what it covers
  (`PART_DESC`). Issue document on the record asks
  Letters or Documents: Client documents at Work (`register_may`); a tab of
  several parts (Services: Quotations, Service lines, Requests; Documents;
  Brand with Reports: White label) is drawn where any is readable
  (`PARTS_OF`, `data-parts`).
- Client scope (`2026-10-03-client-scope.sql`): `clients.leads` (Lead,
  Contacted, Proposal sent) and `clients.past` (Past) narrow Clients and never
  widen it (`PART_LEVELS` View and Manage); a group's `client_scope` is `all`
  or `own` (Person in charge, plus any lead nobody holds, to see and take,
  plus every client whose Sales by is the colleague: `clients.sales_by`,
  `2026-10-23-sales-by.sql`; the user, 2026-10-23: a sales executive keeps
  sight of a client handed to operations, at their group's own level).
  One rule, `client_row_seen_by(stage, owner, owner_id, sales_by, level)`,
  the Person in charge matched by `clients.owner_id` (stamped by trigger
  `client_owner_id_stamp` from the name, kept while that colleague holds it;
  never the name alone: a newcomer sharing a removed colleague's name sees
  none of theirs; `2026-11-17-access-security-fixes.sql`), held by a restrictive
  `client_scope` read policy and a `client_scope_guard` trigger (writes at
  Manage, `client-scope`) on the client and every table under it, by
  `ops_may_see_task` / `ops_may_see_engagement` / `ops_scope_error` /
  `ops_report` (every task read in it: open, finished, spans and reviews
  reached; a colleague's own tasks always), and inside `client_billing`,
  `sm_client_reports`, `sm_report_file` and `sm_report_snapshot`. A new table
  hanging off a client joins the do-block's list; a policy of its own asks
  `client_scope_free` / `client_scope_ok`, never `client_seen` (closed to a
  login, so the read fails for everyone). A removal from `clients`,
  `client_documents`, `documents`, `sm_reports` or `ops_engagements` asks it
  at Manage (`client_scope_removal`, before delete,
  `2026-10-03-client-scope-on-removal.sql`), so the delete functions keep to
  it too. The Activity record is not scoped. The stand-in holds the same rule
  (`scopeRowOk`).
- Columns other parts write are guarded by trigger at the part's Work level:
  `clients_billing_guard` (skipping a cascade, `pg_trigger_depth() > 1`, and a write with no signed-in caller: Bukku's read, the SQL Editor; 2026-11-04) and
  `campaigns_finance_guard`; a page's write on `clients` without Clients at
  Work changes only the review columns (`client_review_columns`,
  `review-columns`).
- Retired switches refuse:
  - `can_billing` → `clients.billing`;
  - `can_doc_void` → Clients Manage;
  - `hr` → `register.hr`.
  - One-argument `allowed(x)` means work, and survives for `admin`.
  - `allowed('remove')` is gone.
- `level()` returns 0 for a missing key, above the admin branch. A permission
  check refuses and never throws. `navItems()` selects `.navitem[data-section]`.
- On the page, `may(key, level)` hides controls: every control names its
  section or part and level (`data-need="clients.documents:manage"`), and
  `applyAccess` writes one rule over every key and level the person may not
  use (`#accessHide`); no stylesheet types a hide rule. A tab with
  `data-part` draws only where readable, and the address falls back to
  Overview.
- The team table answers a browser only the columns every page reads
  (`2026-10-18-team-list-holds-what-colleagues-need.sql`): the mobile, the
  access map, the access dates, the expiry, the removal, the erasure and
  `card_email` are withheld; every column of every colleague is Team's at
  View through `team_rows()`, and who takes tasks is `team_task_takers()`
  (My Work's pickers). A read of `team_members` names its columns, never
  `*` (refused); a new column is granted by running that file's part 3
  again with it named. The stand-in refuses the same.
- `is_team()` gates every team table and edge function. `authenticated` is not
  the team, because clients hold logins.
- A system account (`team_members.system`, `2026-10-08-system-account.sql`;
  IT's login, the user, 2026-10-08) is a full admin never offered for work:
  every colleague picker, the capacity bars, the review list, Health and the
  report reviewers leave it out (`ADspaceAdmin.isSystem`, one read beside
  `me()`; `sm_report_may_review`); Set access expiry for everyone skips it.
  It is the super admin (`2026-11-14-super-admin.sql`; the user,
  2026-11-14: "the most highest power on the portal"): it takes no work
  notice (trigger `ops_notifications_a_super_quiet` writes none to it, so no
  bell, push or WhatsApp; a failed scheduled job's `jobs.failed` still
  reaches it), and while it is active it alone makes or removes an admin
  (below).
  The mark is set only with no sign-in (the connector or the SQL editor;
  a signed-in insert sending it, a `removed_at` or an `erased_at` is refused
  by trigger `team_members_insert_guard`, `2026-10-18-new-colleague-added-plain.sql`);
  trigger `team_members_system_guard` lets only the account itself change its
  standing, access date, group, admin mark, email, removal or erasure
  (`system-account`; removal and erasure since 2026-11-24, without which any
  admin became super admin).
  Team shows it with a Super admin tag and no ⋯ for anyone else.
  - The team list is never derived from `auth.users`. The cutover sweep runs
    only while `team_members` is empty and skips client contacts.
  - A wrong row is stood down (`active = false`), removed, then deleted
    by an admin where it should not exist.
  - `no_team_client_overlap`: one address is never both a colleague and a live
    portal contact. Where a legacy overlap exists, `portal_clients()` returns
    nothing for a team address.
- The Team group panel (two parts since 2026-11-17, the user: "just main
  settings, and sections access (with advanced sections control)"; layout
  only, the stored map and every check unchanged):
  - `#grSum` reads the panel back as one sentence under the name.
  - Main settings: Start from Admin / Manager / Staff / View only (a panel
    matching none reads `Custom: n changes from {nearest}` in plain words
    beside it, `#grPresetNote`, worked out and never stored, no fold; a
    preset chosen over a Custom panel asks first, `Start from Staff?` · n
    changes will be replaced., S7; Admin in Start from is the only way to
    make a group admin, offered to the super admin alone; under it
    `#grPresetSum`, the preset under the pointer or focus, else the one
    chosen, in one line: `Staff: Edit on 9 sections, and View on …`;
    2026-11-26), then Dashboard Team tabs (`#grDash`, a `button.switch`,
    filed `Dashboard Team tabs: On → Off`), Use AI, Send email, Send
    WhatsApp, Sensitive details, Clients they see (`#grScope`) and Reports
    to (`#grReports`, None or a group; its line: the group chosen sees this
    group's colleagues' client feedback scores, `feedback_sees_manager`,
    the one reader of `reports_to`), a hairline between each; headings
    15/600, a section's name 14/500.
  - Section access: one row a section in the rail's order (`CHUNKS`), the
    name, its segment at the right edge holding that section's levels
    alone, each as wide as its words (never fixed tracks with empty slots;
    on a phone under the name, still at the right edge), the line for its
    level (`DESC`), and Advanced (n) under the segment, a `.btn-quiet
    .btn-sm` with the act table's chevron turned down while open
    (`advItems`): the section's own parts, the
    admin tools that act on it as switches, each with its line naming the
    Settings row it opens (`PART_DESC`; `team.settings` is Settings,
    `team.upgrade` Page availability, `team.perfadmin` Performance admin;
    `TOOL_HOME`: the portal's own, Page availability to Analytics, under
    Team), and its line of the Activity
    record (`activity.{section}`, Same as Activity record; HR Letters under
    Documents, the Handbook under Team; `ACT_HOME`); shut,
    `#grDiff-{section}` names only what differs. No Admin tools block, no
    Customise. The My Work views (List, Board, Calendar) are not offered; a
    stored one is kept through a save.
  - What this group can do (`#grPreview`, under Section access, read only,
    2026-11-26): each section opened, its level beside its name, the
    level's `DESC` line and what its Advanced sets apart, then the sections
    left Off on one line; an admin group one line.
  - Add member reads the chosen group's sentence (`sumText`) under User
    group (`#tmRoleSum`); its More details line reads `Access until: No end
    date` until a day is set.
  - Each group row reads its access as phrases held whole (`team-part`),
    and one ⋯ holding Edit then Delete for an admin alone, nothing beside
    it (a user group is made, changed and deleted by an admin: `roles_admin`
    and `team_roles_admin_guard`, `admin-only`; none on the Admin group, nor
    on an admin group for anyone but the super admin; the user, 2026-11-17:
    "menu only sit one option, edit stays outside?"). Services offers No Access,
    View and Full Access; Leads and Past clients offer no level above
    Clients; a client part that follows Clients is greyed while Clients is
    No Access (N2, N3).
  - Compare groups (the bar's ⋯, `#groupCmpBox`) reads every section and
    the admin tools for every group, read only.
  - Own clients only is never given with any Activity record access, a
    section or a tab (the record is not scoped): the sheet refuses it and
    trigger `team_roles_scope_guard` (`scope-activity`) holds it for every
    group but an admin's (`2026-10-10-letters-held-to-their-lines.sql`).
  - No preset below Admin opens Team, HR letters or performance reviews,
    their history included (`activity.team`, `activity.hr` shut; S5).
- User groups are Team's Groups tab (`tab=groups`, `#teamGroupsPane`); the
  strip reads Members, Hiring (`tab=hiring`), Groups, Performance and Health
  (`tab=health`, an admin's alone), each drawn only where readable, the strip
  only where two tabs show.
- The Admin group has no ⋯ and cannot be deleted. A group is deleted by
  `team_role_delete(p_slug, p_to)` (`2026-11-17-group-delete.sql`; the user,
  2026-11-17: "delete options for every create"): an admin's (`admin-only`),
  an admin group or a move into one the super admin's (`super-only`), the
  Admin group never (`fixed`); a group holding colleagues, removed ones
  too, asks New group for its n members (`no-target` without it) and moves them
  in the same transaction, each taking that group's access, the last admin
  kept (`last-admin`); then the name typed back; filed
  `team.group_removed` with how many moved and where.
- While an active system account exists, it alone (the super admin) makes
  a colleague or a group admin, or changes an admin's group, admin mark or
  standing, or makes or deletes an admin group (`team_super_ok()`,
  `super-only`, `2026-11-14-super-admin.sql`; with none active an admin
  does); the page offers an admin group, Admin in Start from, and Set
  inactive or Delete on an admin only to it (`ADspaceAdmin.isSuper`).
- Only an admin makes a colleague or a group admin, or changes an admin's
  group, access, access date, email or standing (`team_admin_guard`,
  `team_roles_admin_guard`, `admin-only`; 2026-10-17), and only an admin
  changes their own group (`2026-11-07-own-group-through-an-admin.sql`): Team Full Access is
  not admin, and is drawn no Set inactive, Delete or Access until pen on an
  admin's record (2026-10-27, TEAM-1). Nor does anyone but an admin turn on, change or take off a
  granted part (an admin tool, Performance, Supplier bank details …) on any
  group, their own included: the guard compares every key `ops_granted` is
  asked for, the page stills those switches and selects and saves them as
  stored (`2026-10-24-admin-tools-admins-only.sql`, S2; the user declined
  delegating Performance or HR Letters). A signed-in write never takes away the last active admin: it
  takes the team's admin lock first, so two admins standing each other down
  at once leave one (`team_members_last_admin`, `last-admin`;
  `2026-10-18-the-last-admin-is-kept.sql`).
