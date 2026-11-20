<!-- triggers: js/team.js js/namecard.js js/card.js card/ supabase/functions/invite-member -->
# Team (`js/team.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Members sit under their group. Your own row shows the neutral `You` chip.
- A member row reads the initials, the name with the Employee ID beside it (`.team-eid`,
  mute; still searched), then department and position (and Until), then the
  email; the state column names only the exception: Inactive, Access
  expired, Removed, or Card off for somebody still working. Inactive,
  expired and removed colleagues leave their group's card for one Inactive
  card after the groups, shut until opened (opened for the row a stand-down
  or Delete moves there). A success line under the bar goes after 8
  seconds; a refusal or a warning stays until the next act.
- A colleague is a record of their own (`member=`, `mtab=`; the user,
  2026-10-18: "build it similar as client individual section"): the
  list is the Clients list's shape (the user, the same day: "it should be
  the same as client"), a row one button (the name, no disc since
  2026-11-04, the email, the exception, the chevron), no ⋯ on the list; it opens in
  place of the list and the Team strip, Back returns; the head is the
  name (no disc), Employee ID and post (the group and department are
  Overview's; TEAM-1, 2026-10-22), the state and the one ⋯
  of every act on a colleague (`memberMenu`, `wireActs`); panes Overview
  (Sign-in and access, Employment, Namecard, each value changed where it
  is read at Team Full Access: a word or a date its pen, a choice a
  select drawn as the value, saved alone through `patchMember`, refused
  in place as the sheet refuses, a name, email or Employee ID another
  colleague holds included (2026-10-27, TEAM-2), filed from and to; no Edit button; the
  user, 2026-10-18), Work (each open task they own, each client they are
  person in charge of, each open campaign they run, a row a record opening
  it as search does, one line at a desk, an overdue task's date in red;
  the tasks' counts first (overdue, due within 7 days, later, no due
  date), ten rows of a list, the rest behind Show all; the other kinds
  `team_work_held` counts on one line; Hand over at Team Full Access),
  Documents (every HR letter that is theirs in the register's own rows
  (`ADspaceRegister.paintForMember`): naming them, or carrying their
  Employee ID in its reference, and their downloaded performance records;
  an HR letter naming nobody takes the one colleague whose Employee ID its
  reference carries, trigger `documents_hr_member`,
  `2026-10-18-hr-letters-find-their-colleague.sql`; Issue document and
  Add existing document open on them), Performance (Open reviews: the months searched for their name,
  behind its own lock) and Health (their check-ins and talks from
  `health_team`, an admin's behind the master code), each drawn only where readable
  (`tests/teamrec.js`).
- A colleague's record has a rail, as a client's (`.rec`, 1.618 : 1,
  splitting below 1100, its blocks leading the tabs on a phone; TEAM2-9,
  2026-10-24), the same blocks on every pane so the strip and head never
  jump between tabs (the user, 2026-11-17): Their work (Team Full Access:
  the counts `team_work_held` and their open tasks answer, read once a
  visit and again after a hand-over, overdue in red, Open Work and Hand
  over work, the counts alone beside the Work pane)
  and Access (the access end off Overview, where it is set; at Team Full
  Access `team_member_seen(p_id)`: Active 2 hours ago / Active today,
  9:14am, Last sign-in 22 Oct, 9:14am from `auth.users`, else Not signed
  in yet and Invitation sent {day}). `team_members.last_seen_at` is
  stamped by `page_pulse` for the team audience alone, once in 15
  minutes, never moving `updated_at`; withheld from the column grants,
  read through `team_rows()` at Team Full Access (null below), cleared on
  erasure (`team_members_erased_seen`;
  `2026-10-24-colleague-last-seen.sql`).
- Devices (`2026-11-20-sign-in-sessions.sql`; the user, 2026-11-20: each
  session as a code, "A ok admins", no new writes or rows): a rail block
  after Access at `team.sessions` (granted, an admin's by itself), read
  from what Supabase keeps (`auth.sessions`) through
  `team_member_sessions(p_id)`: a sign-in a row, the device in words
  (`session_device`, the one reading of a browser's description), Active
  … from the session's last renewal (about hourly), Signed in, its code
  (the session id's first six), This device on the reader's own; five,
  then Show all. Sign out (`team_session_end`) asks, ends that one
  sign-in (the device signs out within the hour its access lasts), never
  the reader's own (`own-session`) or the system account's
  (`system-account`), filed `team.changed` under Signed-in devices. No IP
  address is read; nothing is written but the sign-out. Sign out all
  (`team_sessions_end_all`, `2026-11-20-signed-in-devices-idle.sql`; the
  user: "yes add sign out all devices") is a tonal `.btn-sm` under the list
  (beside Show all where drawn, else at its own width), drawn wherever the
  colleague holds a sign-in, never on the reader's own record or a system
  account's; it asks (how many devices, signed in again on each), ends every
  sign-in at once and is filed `{name} signed out on n devices`;
  refusals `own-account`, `system-account`, `none`, `denied`, `not-found`.
  Each night (pg_cron `session-idle`, 03:52 MYT) `team_sessions_idle_end`
  ends every colleague's sign-in whose latest renewal, update or start is
  older than `session_idle_days` (Business setting, 30, 0 turns this off, 1
  to 365; Settings, Portal: Signed-in devices; the user: "yes option 2"),
  never a system account's or a client contact's; one `team.changed` line by
  `system` a run that signed anybody out (`n devices signed out after 30
  days unused`), a `job_beats` beat (`session-idle`) every run, and a failed
  run raises so `jobs_watch` names it.
- Set inactive / Set active sits in the record's ⋯ (never on your own record). Send
  invitation asks first.
- Add member, Set access expiry, a member's values and Set inactive are
  Team Full Access (`team_admin`); a user group and Add group an admin's
  alone; Send invitation is
  `team.invite` (`invite-member`), which makes a team login only for an
  address an active colleague holds (`not_team_member`) and claims every
  invitation first, twenty a caller in 24 hours (`team_invite_claim`,
  `team_invites`, the service role's; `too_many`;
  `2026-10-18-invitation-goes-to-a-colleague.sql`); Add member invites only
  where `team.invite` stands, else adds the colleague plainly (2026-10-20,
  TEAM-12). A row with nothing it may press draws no ⋯.
- A colleague and a group are written only over the row as read (`.eq('updated_at', …)`,
  `team_roles_touch`, `2026-10-18-stale-team-save-refused.sql`): one changed
  meanwhile reads "Not saved. This changed since it was opened, and has been
  read again."; the group sheet stays open until its write answers, a refusal said in it with
  every change kept (2026-10-20, TEAM-2).
- Changing a member's email asks first, and is an admin's alone: the page
  offers it to an admin, and trigger `team_email_guard` refuses anybody else
  (`admin-only`; deleting a colleague's details empties it as before;
  `2026-10-18-sign-in-email-through-an-admin.sql`).
- The member sheet adds a colleague and nothing else; a colleague is changed
  on their record's Overview, Performance's Edit on Members opening it
  (TEAM2-6, 2026-10-24). Overview's User group asks first ("{name} moves
  from Marketing to Sales and takes that group's access."), Undo where it
  happened; on one's own record it is a fact (TEAM2-1). A refused read of
  the team says so on both lists with Try again (TEAM2-2).
- A member row carries:
  - Employee ID (`staff_code`, `^[A-Z0-9]{3,8}$`);
  - department, from the Departments list (below; a segment while four
    choices or fewer, else the select, `ADspaceForm.segFit`);
  - Position (`designation`);
  - role standard;
  - `capacity_minutes_week` (entered as hours);
  - Access until (`access_until`, a day in Malaysia, with an optional time
    `access_until_time`, five-minute steps, offered only once a day is set;
    no time is the day's end; empty for no end), never on your own row
    (`own-expiry`);
  - Mobile, Mobile on card Show / Hide (`card_mobile`) and Card On / Off
    (`card_on`).
- Add member asks Name, Sign-in email, User group (required) and Employee
  ID; Access until, department, position and mobile fold under More details;
  Send invitation email, unticked, is drawn only at `team.invite`; Add opens
  the new colleague's record, which says what happened (TEAM2-10,
  2026-10-24). Role standard, capacity and the namecard are set there.
- A colleague is stood down or removed (the user, 2026-10-14;
  `2026-10-14-colleague-hand-over.sql`, `2026-10-14-colleague-remove.sql`,
  the second run in the SQL Editor), and once removed an admin may delete
  them for good (the user, 2026-11-17: "also allow entirely delete a person
  from Team", superseding "a colleague's row is never deleted" of 2026-10-14
  and 2026-10-18): the removed colleague's ⋯ holds Delete alone, the name
  typed back, `team_member_purge(p_member, p_name)`
  (`2026-11-17-colleague-deleted-permanently.sql`: `admin-only`,
  `not-removed`, `own`, `system-account`, `last-admin`, `bad-name`), which
  reads every foreign key to `team_members` from the catalogue at the
  press (as a report's function, `adspace.sm_fn`, so a report they
  submitted or confirmed keeps itself without their name;
  `2026-11-17-deletes-and-builds-held.sql`), clears each nullable one, deletes the rows a required one holds
  (their time records, extension requests, assignments, quality checks,
  personnel record and salary, guides, section order), lets the cascades
  take their own data (performance reviews, health, notifications,
  devices), deletes their sign-in where no live client contact holds the
  address, and files `team.changed` Deleted permanently; their name stays
  as text on past work, documents and the Activity record:
  - Set inactive and Delete (the ⋯'s last item, red, Team Full Access, never
    one's own or a system account, not drawn once their details are
    deleted) first ask who takes each kind of live work the colleague holds,
    a picker a kind, only kinds they hold, Keep with them first for Set
    inactive; Delete's opens on Choose a colleague, required while anything
    is held, Keep still offered (TEAM2-5); with two kinds or more All their
    work to comes first and each kind reads Same as above until a colleague
    or Keep is chosen for it (`team_work_held`, read whatever the caller's
    client scope, `2026-10-24-hand-over-takes-clients.sql`): clients they
    are person in charge of and open campaigns (by name, listed for the
    Work pane), open tasks, months they manage,
    meetings ahead they lead, repeating tasks, reports in review waiting on
    them (left with them where the colleague chosen submitted it or may not
    review, and said), extension requests waiting on them, and templates
    naming them as default owner (`team_hand_over`, each filed on its
    record and one line under the colleague: Work handed over: 2 open
    tasks → Aisyah; …; the person in charge moved past the caller's own
    client scope, `adspace.team_owner`). The work moves first: Set inactive
    stands them down, and Delete removes them, only once it has (TEAM2-4).
    Work left with them, or a hand-over refused, is said with Open Work,
    the button to their Work pane, whose head holds Hand over work over a
    line of all they hold, the same pickers, and says after what moved
    what stayed (TEAM2-12). A rename is carried onto every client and
    campaign naming them, completed ones included, each filed, by trigger
    `team_members_rename_owner`; the page carries nothing.
  - Delete then asks Their data, Keep / Erase personal details, and the name typed back
    (the question opens on it); `team_member_remove_check` answers the
    removal's own refusals before any work moves
    (`2026-10-15-colleague-remove-check.sql`), then `team_member_remove` (`own`,
    `system-account`, `bad-name`, `last-admin`) sets them inactive and
    stamps `removed_at` (the row reads Removed, with no Set active);
    Erase personal details also removes the mobile, the namecard (off, its short
    link freed), the sign-in email and its login, their health check-ins,
    consents, log and talks, devices, guides met and section order
    (`erased_at`), and their number and words from every WhatsApp message
    to them (trigger `team_members_erased_whatsapp`). Their name, Employee ID and group, their name on past
    work and the documents they signed, and their own HR letters and
    performance records are kept either way.
  - Leaving (`2026-10-15-colleague-leaving.sql`, audit I3, I4, S6, S9, I9):
    a Delete whose hand-over failed removes nobody (the question stays open
    saying so); an erased colleague's card slug stays empty
    (`team_card_slug`); `team_hand_over` refuses `own` and
    `system-account`; a removed colleague is never made active again
    (`team_access_guard`, `removed`: with a sign-in a removal or an
    erasure, once made, is never moved or cleared, and moving an
    expired-then-removed colleague's date brings nobody back;
    `2026-10-18-a-removal-stands.sql`), so one who returns is added again:
    a name, sign-in email and Employee ID are unique among colleagues not
    removed (`team_members_{name,email,staff_code}_live_idx`,
    `2026-10-18-removed-colleagues-free-their-details.sql`), the page naming
    the field that clashes, and an edge function finding a colleague by
    email reads the active row first; an extension on a task whose creator
    has left is asked of the first active admin who is not a system account
    (`ops_due_decider`); an on-site meeting's outstation reminder goes to
    its leader while active, else the month's manager; trigger
    `team_members_leaving` takes a colleague's notification devices on Set
    inactive, an expiry or a removal, and on a removal ends their helper and
    reviewer places on tasks; trigger `team_members_talks_closed`
    withdraws every open health talk they asked or were asked the moment
    they stop being active (`2026-10-18-leavers-talks-closed.sql`).
- Access expiry (`2026-10-01-team-access-expiry.sql`,
  `2026-10-03-team-access-time.sql`):
  - every five minutes (pg_cron `team-access-expiry`) `team_expire_access()`
    stands down each active colleague whose moment has passed
    (`team_access_ends(day, time)`, MYT) (`active` false, `expired_at` stamped, filed `team.changed` by
    `system`), never the last admin with access; each open task they hold
    goes back to its creator where the creator takes tasks (told, kind
    `assigned`), else is left with no owner and open to take, the active
    managers told (`tasks.unassigned`), each move filed on the task
    (`team_expiry_hand_back`, `2026-10-18-expired-access-hands-tasks-back.sql`);
  - the row reads Access expired and Access until reads Ended {day} with its
    pen, the ⋯ holding no Extend access (TEAM2-8); moving the date to
    today or later brings them back at once (`team_access_guard`), and Set
    active on a passed date is refused (`expired-date`);
  - the bar's ⋯ Set access expiry (`team_set_expiry_at`, Team at Manage)
    asks for a date and an optional time, refusing a moment passed in the
    question (TEAM2-7), and sets them for every active colleague but the
    caller and a system account (an admin's for an admin alone), naming
    how many own end dates it replaces, Undo putting each back
    (2026-10-27, TEAM-3);
  - an expired address signing in reads Access expired
    (`my_access_expired()`), not Access denied.
  - the moment passes before the run comes: `is_team()`, `allowed()`,
    `ops_me()` and `me()` count a colleague only while
    `team_access_ends(access_until, access_until_time)` is ahead (an admin
    is the run's, which keeps the last admin with access), so nothing waits
    for the five minutes (`2026-10-18-access-ends-on-the-minute.sql`).
- Digital namecards (`js/namecard.js`, `/card/?k=`, `2026-10-03-team-namecards.sql`):
  - every colleague has a `card_key` (eight characters from the link keys'
    alphabet), made by trigger and never changed, so a printed QR keeps
    working; the card answers only while the colleague is active and their
    card is on (`card_on`, Team's sheet; off answers the cover, and the
    same address works again once on);
  - `namecard_get(p_key)` (anon) answers name, position, mobile, the
    sign-in email (`2026-10-03-namecard-login-email.sql`; whatever its
    domain, interns' personal addresses included; `card_email` is unread)
    and the card's short link (`slug`, 2026-10-07) alone; never the
    Employee ID, group or access;
  - the email row never breaks inside the address: it shrinks to 12px
    (`fitMail`), else breaks only before the @;
  - the pair under the card (turn, QR code) is two equal halves of the
    portrait card's width on every face, so a turn never moves them;
  - every pill on the card (Save contact, WhatsApp, the turn and QR pair)
    is 44px under a finger, the landscape card's too (the iPhone Duo pass,
    2026-10-18);
  - every card has a short link on the links host (`card_slug`,
    `2026-10-03-namecard-short-links.sql`): made as the colleague is added
    from the name's letters and digits run together (Xue Yi `xueyi`; a
    name with none, written in Chinese, takes the sign-in email's name),
    numbered with no dash where taken (`xueyi2`; `card_slug_from`,
    `2026-10-07-namecard-short-link-shown.sql`; the user, 2026-10-07),
    never following a rename, edited in the Team sheet's Namecard and by the
    colleague in My namecard (`namecard_save`; emptied, made again from
    the name); one slug is never both a card's and a short link's
    (`slug-taken`, both ways); `link_resolve` answers it with the card's own
    address while the colleague is active and the card on, else missing; My
    namecard shows and copies it; the card's QR face names it under the
    name (`hi.adspace.me/{slug}`, never the long address; the user,
    2026-10-07) while the QR itself keeps the card's own address;
  - whether the mobile is on the card is the colleague's own choice
    (`card_mobile`, Mobile on card Show / Hide, shown by default;
    `2026-10-03-namecard-mobile-switch.sql`): one card, one link and one QR,
    and hidden, `namecard_get` sends no mobile, so the card, its WhatsApp and
    Save contact go without it; set in My namecard (`namecard_save`, one
    write with the mobile and short link) and in the Team sheet, filed from
    and to;
  - the card is the signboard's lockup on the brand's five tones (`--nc-*`,
    light in both themes) in golden proportion: the wordmark runs the card's
    width over φ² (`--nc-sw` from the card's width), the tagline at 0.46 of
    its size runs it over φ (the signboard's 1.64), and the pair is centred
    on the card both ways; landscape at 760 and over (`is-land`), portrait
    under; it turns over to the person and the office (`ADSPACE_ORG`),
    turns its front to a QR of its own address, and Save contact is a vCard;
  - every number reads with its country code (`ADspaceCard.phone`:
    +60 12-345 6789, +60 18-762 5233, +65 8123 4567);
  - the colleague keeps their own mobile and short link in My namecard (the
    account menu, `namecard_save`, filed `team.edited`); the Team sheet edits
    everybody's; a row ⋯ offers Open namecard while the card is on. No bar on
    the card's page: it is the card alone on white.
  - the page is named eNamecard by ADspace (`<title>`, og:title) and, once
    the card loads, `{name} • eNamecard by ADspace`; a link preview reads
    the page before it runs, so it shows the general title.
