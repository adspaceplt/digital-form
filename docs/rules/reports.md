<!-- triggers: js/reports.js js/smreport.js supabase/functions/report-draft supabase/functions/meta-import -->
# Reports (`js/reports.js`, `js/smreport.js`, `?s=reports`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Reports is its own section (`reports` View / Work / Manage), not a part of
  Clients. `clients_read` also answers Reports View.
- Flow:
  - Draft → Submit (Work) → Confirm (Manage; never the submitter,
    but an admin may confirm their own after a question saying nobody else
    checked it: `2026-10-02-report-admin-confirm.sql`) → Publish
    (Manage).
  - A report is submitted to a named reviewer (`sm_reports.reviewer_id`,
    `2026-10-04-report-reviewer.sql`), asked for in Submit's question from
    `sm_report_reviewers` (Reports Full Access or an admin, never the
    submitter, the client's last reviewer chosen; an admin submitting is
    offered as Me and chosen, and confirms their own:
    `2026-10-16-admin-reviews-own-report.sql`). Only the reviewer, or an
    admin after "Confirm in place of {name}?" (filed "in place of"),
    confirms (`not-reviewer`); the reviewer, an admin or the submitter
    (Take back) sends it back. Change reviewer in the head's ⋯ (submitter,
    reviewer or admin; `sm_report_assign`, filed `report.reassigned`). The
    reviewer is told on Submit and on a change, the submitter on Confirm
    and Send back, each through the bell and a push opening the report
    (`ops_notifications.report_id`). The step reads "Waiting for {name} to
    confirm."; the list row names the reviewer. A report in review from
    before keeps the earlier rule until Assign reviewer (the same ⋯) names
    one. Only the functions set the reviewer.
  - The month's gate (`2026-10-04-report-month-gate.sql`, reports from
    October 2026): `sm_report_gate` finds the client's month whose span
    holds the report's last day and names what it lacks (`no-month`,
    `not-ticked`, `no-task`; for an Accounts Report alone `content`:
    content tasks fewer than planned, report and cancelled tasks not
    counted, and `posted`: fewer planned posts at Live, Performance review
    or Completed holding Draft due, Due date, Post date and the live date,
    `lacking` naming each task short of it and what it lacks, twenty at
    most; `2026-11-05-accounts-report-needs-posts-live.sql`, the user,
    2026-11-05; posts planned is a count, never a week each) and the due
    time (the report task's). Check and submit shows it as rows under the
    report's checks (Month in My Work, Report task with Open where My Work
    is readable, Posts live with a line a task short of it, Open on each,
    a planned post with no task said in red, Due). Mark delayed on a
    post's line (a draft at Reports Work; `sm_report_post_delay`, a date
    move's reason and a note of 300; `not-draft`, `not-in-month`,
    `posted`, `bad-reason`, `too-long`; Clear, Undo where it happened;
    filed on the task and the report, its owner told, kind `delayed`)
    counts it toward the posts planned; a planned post with no task can
    never be marked. The task keeps its dates (On-time posting still reads
    it late) and reads Delayed (the grey dot, beside the name on its row,
    its board card and its card's next step) until it goes live; the
    Dashboard's Needs attention lists it (Delayed posts). No band of its
    own. Report posts linked to their tasks
    (`2026-11-06-report-posts-linked-to-tasks.sql`, its SQL Editor part
    `-editor.sql`; the user, 2026-11-06: "close the loop"): with the
    Business setting `report_post_links` on (Settings, Reports: Posts
    linked to tasks, seeded On, `report_links_set`), a monthly Accounts
    Report's post takes its My Work task from its ⋯ (Link task, Unlink
    task; a lacking task's Link on Check and submit), the month's tasks
    and any marked delayed offered (an admin or Reports Full Access any of
    the client's), through `sm_report_post_link` (Reports Work, a draft,
    the post dated; `links-off`, `not-linkable`, `no-date`,
    `not-in-month`, `linked` for a link in another report), one task a
    post and one post an account a task (`same-account`, the account
    named; `2026-11-06-report-posts-many-accounts.sql`, its SQL Editor part
    dropping the one-link-a-task index; the user, 2026-11-06: one content
    on Instagram and Facebook): the post takes the task's
    description as its name and shows its code; the task takes the
    earliest linked post's day as its live date (the report is right where
    the task was not), its delay cleared, its views and engagements added
    up over its linked posts (`sm_report_task_sync`), and moves
    to Performance review (a task On hold, Blocked or Taken down stays),
    then Completed as the report moves into published and back as it
    leaves it, no other step of the report moving it (trigger
    `sm_reports_posts_follow`, nothing while the switch is off); a post
    with no figures writes none. Unlink (open with the switch off too)
    puts back what it changed where nothing changed it since, the stage
    only from Performance review, the post's typed name too, once its last
    link goes (one of several taken off works the date and figures out
    again from the posts left)
    (`sm_report_post_links`, RLS on, no policy, no grant, kept and ended,
    never in the snapshot); a post removed takes its link off (trigger
    `sm_report_post_removed`, the SQL Editor part). Reports Work moves a
    colleague's task here, as a report moves its own report task. The gate then counts a planned post once linked
    with its three dates set, naming one not linked (Live · Not linked to
    a post); off, the stage rule above stands. A white-label report is
    held to no post and links none. Link task offers a task linked on
    another account (Linked: {account}), never one already on this post's
    account, and once linked offers the same day's posts on the report's
    other accounts no task holds, ticked (Link on other accounts; never
    linked by itself). The task card reads In the Accounts
    Report · {month} · Posted {day} (on several accounts, each account and
    its day, earliest first) · n days after its post date, Open
    report (`ops_task_report_post` `posts`). Submit is
    refused `month-gate` unless an admin or Reports Full Access gives a
    reason, and `late-reason` once past due until one is given; Submit's
    question asks for it beside the reviewer, kept as `gate_note` /
    `late_reason` and filed. At Work a month not in order rests Submit.
  - A report made in Reports for a month that does not ask for it (an
    admin or Reports Full Access, Not planned) ticks that report on the
    month and makes its report task, as its maker, else as the month's
    manager (`sm_reports_month_tick`); a report task made after its report
    stands (a tick added in My Work later) takes the report's step at once (`ops_tasks_report_catch_up`;
    `2026-11-10-report-ticks-its-month.sql`; the user, 2026-11-10).
  - The month's report task follows its report to Done
    (`2026-11-21-report-task-follows-to-done.sql`, trigger
    `sm_reports_task_follow`, the task found as `sm_report_gate` finds it,
    the stage from `sm_report_task_target`, every move through
    `sm_report_task_move`; the user, 2026-11-21): a report made puts it In
    progress under its maker; submitted for review, confirmed or published
    and not yet sent, Review; marked as sent, Done, finished on the sent
    day (its last second in Malaysia, or now where that day is today), its
    timers stopped and filed `completed`. A finished task, whether the
    report or its owner finished it, moves only with its report moving
    back: marked as not sent, Review; back in draft (sent back or revised),
    In progress. A cancelled task never moves, and a white-label brand's
    report leaves it alone; a
    report given a brand after it was made puts the task back to To do
    under the month's manager (unless another of the client's own reports
    in the month holds it), and one given back to its client takes it
    again (trigger `sm_reports_brand_task`, `2026-10-15-white-label-task.sql`).
    Each move is filed on the task with `report_id`; a fault never fails
    the report's write. A draft report deleted puts its unfinished task
    back to To do, filed Report deleted (`sm_reports_task_reset`,
    `2026-10-09-report-month-at-start.sql`).
  - A report begins in its month (the same file; the user, 2026-10-09): a
    report from October 2026 with no white-label brand is made only for a
    month in My Work whose span holds its last day and whose Reports ticks
    ask for its kind (trigger `sm_reports_month_gate`, `month-gate`), unless
    an admin or Reports Full Access makes it. New report asks Monthly or Ad
    hoc (`#rpNewMode`; the user, 2026-10-11). Monthly offers the client's
    content months in My Work alone (`sm_report_months`), each named and
    spanned as the report will be (a month starts on its `start_day`), one
    report of a type a month: a month already holding it (same brand, same
    span) reads its stage (`· Published`) and is not offered; one whose
    Reports ticks do not ask reads Not planned, offered only to an admin
    or Reports Full Access; a client's own Accounts Report needs the month's
    planned content (`No content`; `sm_reports_month_gate`
    `no-content` at every level, `2026-10-11-reports-need-content.sql`).
    A white-label client is held to neither of the last two, for its own
    reports and its brands' (a brand takes the partner's months), either
    type. Ad hoc is a start and an end, any period, made on request. The
    month sheet's Accounts report tick rests while Posts planned is empty
    for a client not white label (`ops_engagements_accounts_content`:
    `accounts-needs-content`; a new month with no plan leaves out the tick
    it took from the month before).
  - On request (`2026-10-09-reports-on-request.sql`, `sm_reports.on_request`;
    the user, 2026-10-09: "Sometimes we need to create report on demand"):
    New report's Ad hoc makes a report the client asked for, on any period (`sm_report_create_for(…, p_on_request)`, filed On request).
    No month gate, no month rows under Check and submit (`sm_report_gate`
    answers `applies` false), the month's report task never moved or reset
    by it, never the month's report in `sm_report_months` or
    `sm_reports_owed`; a month's report never carries on from one, and an
    Advertising Report asked for compares with the same length just before
    it. The list marks it On request; the head reads Requested, By the
    client.
  - Then Revise (the next version as a draft) or Unpublish (with a reason).
  - A report published tells the client's Person in charge (the user,
    2026-11-03): the active colleague the client's `owner` names, in the
    bell and on their phone, opening the report (kind `report.published`,
    "{client or brand} · {period} · Published by {name}"), never the one
    who published it (trigger `sm_reports_published_notice`, once a move to
    published; `2026-11-03-report-published-notice.sql`). The client is not
    told: that stays Mark as sent.
  - Mark as sent (Reports at Work; `sm_report_sent`, `sm_reports.sent_on` /
    `sent_by`): one date, today by default, never after today nor before
    the period (`bad-date`); filed from and to. The head's Sent fact is the
    one control: a Mark as sent button, then the day with its pen; the ⋯
    holds only Mark as not sent (2026-10-09: it repeated the pen). A
    published row reads Sent {day} or Not sent. Once a
    published report not yet sent has its PDF drawn (Preview PDF or
    Download), a line under the head asks Sent to the client? (`.rp-sentask`:
    Mark as sent, today, and a close mark; kept through a repaint until
    answered or closed), and the way back is Undo where it happened; no
    Share or WhatsApp button (the user, 2026-10-06).
  - Download (the head's ⋯, every report, Reports View) saves the PDF under
    its own name with no tab: Preview PDF's tab holds a passing `blob:`
    address that cannot be shared, and the browser may name a file saved
    from it at random.
  - Transfer client (the head's ⋯, `reports.transfer`, a draft only;
    `sm_report_move`, `2026-10-06-report-move-client.sql`) moves a report
    started under a temporary client to an Active one with no report of its
    kind for a day of its period (`not-draft`, `not-active`, `exists`); its
    rows and AI uses follow it, filed `report.saved` under both clients.
  - White label (`2026-10-07-white-label-on-the-client.sql`): the partner
    is the client (billed, with its portal) and ADspace services the
    partner's own clients under its name, so the report stays under the
    partner. A client is made a partner on its Brand (Reports, White label:
    `clients.white_label`, read with the record alone, never the list), and
    ticked it needs its wide logo (`clients.report_logo`, a PNG drawn down to
    1200 by 400; the sheet refuses Save without it and the database's
    `clients_white_label_logo` too; filed `client.brand`). Both the tick and
    the report's choice are Reports: White label at Work (a granted part;
    `clients_white_label_guard`, the Brand sheet's Reports section drawn only
    for it). The Brand pane reads it as one White label group (`#crmWlBrands`:
    White label, Wide logo, then Brands with Add brand; 2026-10-15). Brands (`2026-10-07-white-label-brands.sql`): a white-label
    client keeps a saved list (`client_brands`, RLS on, no policy, no
    grant; `client_brands_list`, `client_brand_save` at Reports: White
    label; unique within the client in any case, `taken`; stood down, never
    removed; a rename reaches its reports not published; filed
    `client.brand`), on its Brand with Add brand and each brand's ⋯ Rename /
    Set inactive. A report is its client plus a brand (`sm_reports.brand_id`;
    the client's own has none): one a client, kind, period and brand
    (`sm_reports_client_brand_period_idx`), New report's Client list (each
    active brand straight under its client, `{client} › {brand} · White
    label`, value `b:{brand id}`; one pick, no For field; the user,
    2026-10-15; `sm_report_create_for`), the head ⋯'s White label (any
    report not published, drawn only where the client is white label and
    holds a brand; 2026-10-22, RPT-2; `sm_report_brand`, `exists`, `bad-brand`, filed
    from and to), accounts carried from the same brand's last report and
    the AI quota counted by brand (`ai_drafts.brand_id`, filled by
    trigger). A brand's report sets `label_client` to its own client and
    `brand_name` to the brand. A white-label report is not transferred
    (`white-label`). The list names it by its brand with a White label
    chip, the client under it. There is no list of partners
    (`report_partners`, `report_partner_clients` and `sm_reports.partner_id`
    were dropped on 2026-10-24, `2026-10-24-unused-tables-dropped.sql`, with
    `activity_viewers`, `ops_kpi_targets` and `video_script_reviews`). Each brand says whose mark heads
    its reports (`client_brands.logo`, `partner` by default or `adspace`;
    `client_brand_logo`, the brand's ⋯ Use ADspace logo / Use {client} logo,
    never asks, filed from and to; the row's `ADspace logo` chip;
    `2026-10-07-white-label-brand-logo.sql`). `sm_report_snapshot` sends that client (its name and wide
    logo, while still ticked and the brand takes it) and, with a brand, the brand as the client's
    name and no client logo; the PDF draws the logo at the head of every page
    in place of the ADspace wordmark (15pt high, two fifths of the line at
    most; the name in the wordmark's face where no logo is held) and a
    published version keeps both. Everything else stays ADspace's (the
    glossary link, the file's properties). The report head's facts read
    For {brand} and Logo {client}.
  - An account on a platform the database's list does not hold is kept as
    `other` with `sm_report_platforms.platform_name`
    (`2026-10-06-report-platform-names.sql`, carried forward by
    `sm_report_create`): the account sheet offers 抖音, Pinterest and
    大众点评 by name, and Other asks for the Platform name (required).
    `platWord()` (both scripts) names it everywhere; never "Other". An
    account kept as Douyin before reads 抖音 (`RENAMED`; the user,
    2026-10-07).
  - A trigger refuses row edits once a report is not a draft, and refuses
    status or stamp changes outside `sm_report_*`.
  - Publishing freezes `sm_report_versions.snapshot`.
  - Kept as sent (`2026-10-07-report-files-kept.sql`): once a version is
    published its PDF is drawn from that snapshot and stored once under
    the bucket's `private/{client}/` (`sign-upload` private, then
    `sm_report_keep_file`: Reports Work, the key under the report's own
    client, never replaced; `file_key`, `file_at`, `file_by`; its own
    write passes `client_scope_guard` under `adspace.keep_file`, so a
    client seen at View is kept too, `2026-10-07-report-file-kept-in-scope.sql`). A file
    stands for the publish it was drawn after (`file_at` not before
    `published_at`), so a version published again keeps the next file.
    Every download of a published version (the head's Preview PDF and
    Download, Select's Download, the client record's Engagements, the
    client portal) hands over that file, read back as bytes through
    `sign-download` `{ reportVersion }` (`sm_report_file_key`, asked as the
    caller: a colleague at Reports or Clients View on a client they see,
    any version; a client's contact only the version the portal shows),
    never a link; a version with no file is drawn from its own snapshot and
    kept then, and a kept file that does not open is drawn again with
    "The saved PDF could not be opened, so it was generated again.". The head's ⋯ Versions
    (`#rpVerSheet`) lists every version newest first (published when and
    by whom; On the client portal, or Unpublished and why) with its own
    Download, and its ⋯ Restore and Delete (the user, 2026-10-25,
    `2026-10-25-report-versions-restore-delete.sql`): Restore
    (`sm_report_version_restore`, Reports at Work, a draft or published
    report, asked first, over a draft in warn saying its edits are lost
    with no undo (2026-10-27, RPT-13); `in-review` otherwise) writes that version's kept
    snapshot back over the report's rows and commentary as the draft, a
    published report becoming the next version's draft, the portal keeping
    what it shows until a version is published, filed `report.revised`
    Restored from version n; Delete (`sm_report_version_delete`, Full
    Access, asked, no restore) removes a version the portal no longer
    shows (`on-portal` for the newest not withdrawn), filed
    `report.version_deleted`, its PDF left in S3.
  - Delete (the head's ⋯, Reports Full Access, the period typed back as the
    page writes it, which `sm_period_word` writes alike: 16 September to 10
    October 2026; `2026-10-13-period-words.sql`) removes
    a report in any state with every version (`sm_report_delete`,
    `2026-10-11-report-delete-seen.sql`; the user, 2026-10-11); one the client
    has read says so in its question and in the record (`report.deleted`:
    had been published, n versions removed from the client portal).
- The list is one tab a stage (`#rhTabs`, the view strip, swipe and the
  arrows; `tab=` in the address, Drafts left out): Drafts, In review,
  Confirmed, Published, each with its count, opening on the first that
  holds any. Under the tab, a card a report month (`period_start`), newest
  first, a published row's Sent or Not sent in its own right column on a
  narrow pane (`.rh-sent`, 2026-10-27, RPT-11). Published is held to a period (`#rhPeriod`, Last 3 months by
  default, Last 12 months, This year, All months; drawn only on that tab),
  only its newest month open; a search (client, code, month, type) looks
  through every report, whatever the tab and the period. New report opens
  on the type as a segment (Accounts Report / Advertising Report). Only
  Active clients.
- Select reports (the bar's ⋯, Reports View) turns each row of the tab into
  its tick (`.rh-row.is-picking`, the row a `label`) under a bar
  (`#rhBulk`: a tick for the whole tab, `n selected`, Download, Mark as
  sent on Published at Work, Publish on Confirmed at Manage,
  Done); changing tab clears the ticks. Each act runs one report after
  another through the function one report uses (`sm_report_sent`,
  `sm_report_publish`), and what is refused is named against its report
  (`#rhBulkMsg`). Mark as sent asks one day for all (today, never before
  the latest period), with Undo over the list putting back each report's
  own day. Download saves each file under its own name.
- Four steps, a strip with each step's summary, Next: {step}, and Check and
  submit. Every step's foot reads Next: {step}, Save beside it where the
  step saves, and the editor's way out is Back (2026-10-22, RPT-7); the
  Commentary step is done, its tick drawn, only once every block is
  written (RPT-8).
  - The head is the record head: the name, then the state, Preview PDF and
    the ⋯ at the right edge; the meta under them (type · period alone),
    then the facts each under its label (`.rp-facts`: Version, Client
    portal, Sent, For, Logo; one left out where it has nothing to say;
    two across in a narrow pane). On a narrow pane the
    button reads PDF (`.rp-pdf-short`). Preview PDF opens a tab at the
    press (`openTab()`, "Drawing the PDF…") and puts the drawn file in it
    (a `blob:` address), so the browser previews it; where the tab is
    blocked the file downloads (the user, 2026-10-05).
  - The step foot is an action row, the primary at the right edge.
  - Check and submit ends in one too (`.rp-actions`): Send back, then the
    step forward at the right edge, each at its own width (the base `.btn`
    is `flex: 1`, so an action row states `flex: 0 0 auto`); who it waits on
    sits to their left; on a phone the pair are equal halves under it.
  - An empty step's line does not repeat the head's Add.
  - An account is named by its handle (`account_name`, labelled Handle):
    a new account takes the client's Brand handle for the platform picked
    (`handle_ig`, `handle_fb`, `handle_tiktok`, `handle_xhs`) and follows the
    platform while untouched. The PDF names the platform, never the handle.
  - The commentary has no title or headline. An ads report's is four
    fields. An accounts report's is the summary, then one block a platform
    group (written to its lead account: Summary line, What worked, Areas to
    improve, Focus for next month, the advertising report's words) and,
    under its own Top posts label (`.rp-tophead`), Why it stood out for
    each of its top three posts (`ADspaceSmReport.topOf`, ranked on that
    platform alone). The older across-platform fields show under Across all
    platforms only on a report that holds some; an account sheet shows its
    own remarks only where it is not its group's lead and holds some. The
    step counts the summary and each platform (`commentaryState`).
- The client record lists a client's reports on its Engagements pane, each
  in its content month (Clients: Engagements); there is no Reports tab on
  the record.
- The client portal reads only the newest version that has not been withdrawn
  (`portal_reports`, `portal_report`), and names it as its cover does
  (`ADspaceSmReport.titleOf`).
- Accounts carry forward.
- Posts paste from a spreadsheet, or its CSV file, by header name. Thumbnails
  are 320px JPEGs kept on S3 (`2026-11-20-report-pictures-on-s3.sql`; the
  user, 2026-11-20: "Ok move to s3"): every picture a sheet, a paste or
  Meta gives is put under its report's client's `private/{client}/thumbs/`
  (sign-upload purpose `thumb`, Reports at Work in scope, a JPEG of a
  megabyte at most) before the row is written, and the row and every
  version published since name its key (`keepThumb`, js/reports.js; an
  upload refused writes nothing and says The picture could not be saved.
  Try again.). A key is read through an hour's S3 link sign-download signs
  for the reader (`thumbs`, `sm_report_thumbs`: a colleague at Reports or
  Clients View in scope, any key the report's rows or versions name; the
  client's portal contact, a live version's), many in one call
  (`ADspaceSmReport.thumbsFor`, the one copy for the console's rows and the
  PDF, the PDF fetching across origins through the bucket's CORS GET). A
  data URL from before the move still draws as it is; `report-thumbs-move`
  moved them once (docs/S3-STORAGE.md §7).
  - A slashed date is day first unless the paste shows otherwise (a second
    part over 12) or is a Meta export (`Post ID` and `Publish time`), which
    is month first.
  - A Meta Business Suite export: Title is never a title (it repeats the
    caption, and is the caption where Description is empty, as on a
    Facebook photo; the post is named by its format and date, its caption's
    first line under it), Description is the caption, Publish time the date
    (written in US Pacific time, read as the Malaysian day of that moment,
    `metaDay`), Reactions,
    comments and shares the interactions, Post type (and a `/reel/` link)
    the format. Where a paste names no interactions (Instagram: Likes,
    Comments, Shares, Saves) they are the sum of those parts, and where it
    names no engagements they are the interactions, so either figure an
    account shows is filled. One post a Post ID: a Lifetime row is taken as it is (figures
    to the day of the export); day rows are added up inside the report's
    period, reach left blank (it cannot be added across days). The summary
    line says which, and says in warn before Import a file with no Views or
    Reach column (Meta's daily breakdown carries neither).
  - A post already in the account is matched by its link and updated, never
    added twice; a blank cell never clears a figure.
  - Select (`data-a="pickposts"`) ticks posts: Move to account (two accounts
    or more) and Remove (asks, naming how many), each with Undo.
- Ads reports (`kind = 'ads'`):
  - Meta and TikTok in one report (`2026-10-05-ads-platforms.sql`): each ad
    names its platform (`sm_report_ads.platform`, `meta` default or
    `tiktok`); Meta's figures stay at the top of `ads_totals`, TikTok's under
    `ads_totals.tiktok`, and reach is never added across platforms. The
    import and the ad sheet ask the platform (a segment, Meta first; a paste
    with TikTok's own headers picks TikTok until the person picks), a paste
    matches only its own platform's ads, and TikTok's hook is 2-second views
    over impressions, its hold 6-second over 2-second. Only where both are
    held: the ads list and the PDF head each objective with its platform
    (Leads · Meta, Traffic · TikTok), Step 1 asks TikTok's figures apart,
    the summary is a By platform table (impressions and spend totalled,
    reach not), the tax note reads On Meta, and Open in Ads Manager is
    Meta's alone. TikTok's campaign report (the team's first export,
    2026-10-10) is read as it comes: a row named by its campaign where no
    ad is named, Spend the amount spent, Results its result (Conversions
    only where no Results column), a CTR given as a fraction read as a
    percentage where clicks over impressions say so, and its Total of N
    results row the account's figures for Step 1, never an ad. It holds no
    reach, age or video figures: an ad level export with them is asked for.
  - `first_month` carries the reading guidance; a later month compares against
    the previous period: a new report takes the latest published Advertising
    Report of its client and brand not asked for that ends before it starts,
    from the version the client was shown (`sm_report_create_for`, kept as
    `ads_totals.prev_from`; `2026-11-17-ads-report-compares-with.sql`; the
    user, 2026-11-17: a report asked for in between became Huna's
    comparison), and Step 1's Compare with offers every published one ending
    before it; the one chosen stands as read values, never fields (the
    user, 2026-11-18: what the client was sent is not touched; a correction
    is a new version of that report, published and sent). Typed figures
    (`prev_typed`) are offered only where no published report ends before
    it, or the report already holds them. An objective's results line
    leaves out a part counting nothing (an ad with no result reads no
    0 Results). A new report is never a
    first month by itself (`2026-10-01-ads-first-month-unticked.sql`: most
    clients advertised before the portal); with no earlier report the period
    before is prefilled (the previous calendar month, else the same length
    just before) for the team to type its figures, and the team ticks a
    client's true first month.
  - One row per ad and objective.
  - Ad accounts (2026-11-17, Huna: Step 1 held one of two accounts): Step 1
    keeps each ad account's own reach, impressions and amount spent
    (`ads_totals.accounts`, by Account ID with Meta's name), written by
    that account's import (its account row) or typed in Step 1 a section an
    account; with two accounts or more Step 1's impressions and amount
    spent are their sum and its reach is each account's own, never added
    (`withAccounts`; the PDF's By ad account table naming each Ad account
    1, 2 … in Step 1's order, never Meta's name or Account ID, which are
    the agency's own and may name another client (the user, 2026-11-18),
    `report-draft`'s `by_ad_account` sending figures alone); a report from before reads its
    Step 1 figures as the one account whose ads they cover, to the sen
    (`legacyAccounts`).
  - Figures add up (2026-11-17; the user: "whats the purpose of the audit
    seriously??"): Check and submit holds Submit and Publish, with no Meta,
    where Step 1 is below what its ads add up to (each account's own, and
    the accounts added up), the previous period's objectives spend more
    than its amount spent, or the previous period differs from the
    published report it names or shares its dates with (`sumIssues`), each
    a row with its one-press fix (Combine ad accounts, Use that report's
    figures) and Undo where it happened. Step 1 above its ads is not held:
    an import leaves out an ad with no results. A total held against the
    sum of its lines (ads, objectives) allows only the rounding Meta makes,
    each line rounded to the sen alone and the total once: half a sen a
    line and half for the total, never a percentage (2026-11-18, Laman
    Waringin: RM 3,401.38 against objectives adding up to 3,401.40 could
    not be submitted); a figure compared with its published report is
    held to the sen.
  - Ads Manager's own cost per result; a reach result reads `RM 1.33 / 1,000`
    under Cost per result in every table, never Per 1,000 reached; the
    console's row and the PDF read one rule (`ADspaceSmReport.cprOf`,
    `perThousand`; 2026-10-22, RPT-1).
  - Paste from an Ads Manager or Ads Reporting export (2026-10-01). A row on
    the report is one creative (the name without its creator code), objective,
    ad set and result type: its copies, age bands and days are gathered into
    it; two result types (Post engagements, Interactions) are never added
    together; Post engagements reads Engagements. Ad ID ties each row to its ad; without it, one name with two
    result types is refused, and a row that would match two of the report's
    rows is left out and listed as unclear, never written to the first. The row keeps its Ad IDs and the Account ID
    (`ad_ids`, `ad_account`) as the team's reference: the row and the Edit
    sheet's foot (left of Cancel) name how many (`2 Ad IDs`, a `.linkbtn`)
    and open them over the page (`#rpIdsPop`, a `.popcard` through
    `ADspaceMenu.pop`, above a sheet, Escape first): each a copy control,
    Copy all, Open in Ads Manager; never the IDs in a line under the name. A
    later paste is matched by them first, and never to a row of another ad
    account (`sameAccount`: a creative of one name in two accounts is two
    rows, each under its account's name in the console, `Ad account ending
    4321`, never in the PDF; the user, 2026-10-30); never printed in the PDF. A table's total row gives the figures once.
    The export's first row (no ad name) is the account's own reach,
    impressions and amount spent for the period, reach counted once: it
    fills Step 1 where empty, and a typed figure is kept (the sheet says so).
    A paste naming ads already in the report updates them with what it holds
    and adds the rest: a day export the dates (first and last day with
    impressions), an age export the age split, an export with neither the
    figures and reach as Ads Manager counts them per ad. Dates otherwise:
    Starts and Ends held inside the period, else the reporting range. Rates:
    a Hook or Hold rate column's formula is found from the rows; without one,
    hook is 3-second plays over impressions and hold ThruPlays over 3-second
    plays. Rows from two ad accounts are refused. With no Objective column an ad's objective is the one its result type names (Reach and ad recall Awareness, Leads Leads, link clicks Traffic; `objectiveOfResult`), the sheet's Default objective only where none is named (2026-11-16, Laman Waringin's reach ads filed as Leads). The result type comes from
    the first row naming one (never `mixed`), read as its word
    (`ADspaceSmReport.resultWord`). The creator code (`_000` to `_999`) is
    dropped on import and hidden on the list and the PDF
    (`ADspaceSmReport.adName`).
  - Write with AI on the Commentary step of both kinds (`report-draft` edge
    function, secrets `ANTHROPIC_API_KEY` and `REPORT_DRAFT_MODEL`,
    `docs/REPORT-DRAFT-SETUP.md`): sends the report id and Notes for the
    draft (`#rpAiNotes`: reasons, changes, goal, next month's budget;
    required, a field on show, the press refusing in its line with the
    caret in the box until it holds words (the user, 2026-11-03: "everyone
    needs to input something for the AI to read"; page-side); kept
    in this browser under `adspace-draft-notes:{id}`, never saved with the
    report); the function reads the report as the caller (Reports Work, a
    draft) and sends Claude its figures, the notes and the client's last
    finished report's commentary, the client's name (and a white-label
    brand's) masked as `{brand}`, never a contact or image. The drafts and
    the check name the client by `{brand}`, filled with the name the report
    is for once the answer is back (`brandIn`, which also puts 贵公司, 贵司,
    贵品牌 and the like back to the name); never "your company" or a Chinese
    honorific (the user, 2026-10-07). It writes in a formal, client-facing house
    style taken from the team's approved reports (`SYSTEM`, `SOCIAL_SYSTEM`),
    held to its fields by structured output: the model in use refuses a
    forced `tool_choice`. An accounts report sends the platforms and top
    posts the step shows (`platforms`, `posts`) and gets back each
    platform's four fields and each post's remark, read platform by
    platform. Every press asks first (Write a draft?, or Replace the
    commentary? over written text), saying it uses one draft and how many
    are left; nothing is saved until Save.
  - A report has a draft language (`sm_reports.lang`, 'en' or 'zh',
    `2026-10-01-report-language.sql`), the English / 中文 segment beside
    Draft with AI (`#rpAiLang`), saved at once; a new report takes the main
    contact's preferred language, set by trigger `sm_reports_lang_default`
    whichever way it is made (New report, My Work's Start report;
    2026-11-17). It decides only the language Draft with
    AI writes in (`ZH` in `report-draft`): the PDF's template is English
    throughout and what the team wrote prints as written (the user,
    2026-10-01: Meta's own terms read in English). The PDF's Chinese layer
    (`ZH_WORDS`, `ZH_COUNT`, `ZH_RULES` in `js/smreport.js`) is switched off.
    Chinese drafts read smooth and easy, as an account manager writes to
    the owner, never a stiff audit report (`ZH`, TONE IN CHINESE; the
    user, 2026-10-16); a cost per result reads as an average (平均每次对话成本
    RM 19.72, never a bare 每次). A 中文 press asks for Chinese at the head
    of the request too (`ZH_ASK`), and one answered in English is asked once
    more inside the same press (`readsChinese`; 2026-11-17).
    Chinese text is drawn in Noto Sans SC (`ADSPACE_ORG.fontCjk`, below).
  - Every draft keeps to `SHARED`: only what the client needs, a few points
    a field, one sentence a point, and candid both ways (the user,
    2026-10-07: never "creative is bad", never so protective it reads as if
    nothing ever goes wrong). The result is judged, never the work we made;
    a shortfall is said plainly with its figure, how far short and what we
    will change; a month weaker than the last is called weaker in the
    summary; a slip on our side the notes name is owned in one sentence; a
    win credits the choice behind it, with its figure; where the figures
    show no cause it says so; nobody is blamed without the notes; no result
    is promised. The words in `AVOID` (English and Chinese: judgements of
    our work, praise no figure carries, comfort phrases in place of a figure,
    words that colour a figure) are never used, and the check finds them and
    a picture brighter than the figures. The ads field `fix` is headed Areas
    to improve: an ad that cost more is read against its objective's own
    cost per result (`group_cost_per_result`, the marked ads left out) or
    the previous period, never against the best ad by name, as a multiple
    or a gap, or as the worst or highest (the user, 2026-10-16: "is this a
    proper way … to present client-facing report"), and an ad within about
    a fifth of that figure is not an area to improve.
  - Every press is counted by the database before Claude is asked
    (`ai_draft_claim`, `2026-10-01-draft-with-ai-limits.sql`), by subject
    (the report, or any of the same client and kind whose period shares a
    day with it, deleted or not: `ai_drafts` keeps client, kind and period,
    `2026-10-04-ai-draft-subject.sql`), a day from 12:00 am MYT and reset
    each midnight (`ai_draft_day()`, `2026-10-04-ai-draft-daily-reset.sql`).
    Every limit is a setting in `ai_draft_limits`, one for each use a
    person a day, an admin's the same (`2026-11-03-ai-limits-each-use.sql`;
    the user, 2026-11-03: "AI usage settings ok approve build"):
    `drafts` (Report drafts), `checks` (Commentary checks), `caption`,
    `script`, `analysis`, `checklist`, `analytics`, each a standard (null
    the default, 0 stops it) and a colleague's own figure for any use
    (`{colleague id}:{use}`, null the standard), read by `ai_cap(member,
    use)` alone (every claim and every count left; `_admin` figures and the
    day's total of AI uses are no longer read); then `per_report`, a
    switch (1 on, 0 off): one draft and one commentary check a report a
    day for whoever asks (the same period of the same client is the same
    report, `ai_draft_same`; a revision brings no new check), refused
    `report` / `report_check`, the day's own refused `drafts` / `checks`;
    every refusal names the reset time. There is no team cap: the team's and a group's totals are
    their colleagues' limits added up (`team` refused `bad-scope`). A
    press the API refused before it generated keeps no tokens, is marked
    failed and is not counted; one that reached the model and ended with
    no answer (its length, a refusal, nothing usable) is `incomplete` and
    counted (`ai_draft_done`, `ai_draft_tokens`; 2026-10-17, the user:
    "count every failure except rejected") against the day, never against
    the report's one draft or check of the day (`ai_draft_same`,
    `ai_check_claim`), so Try again works; nor does a run still `pending`
    ten minutes on (its function was stopped; 2026-10-18). `ai_drafts` has RLS on, no policy and no grants. A refusal
    (`ai-limit`) names the scope, the limit and when the next draft is free.
    Beside the button the count left reads `1 left` (`ai_draft_left`, the
    lesser of the report's and the colleague's, read without writing); at
    0 the button rests and the line under it says why and when the next
    is free.
  - Every amount an Advertising Report's commentary states is one the
    report holds (`figureSlips`, js/reports.js; 2026-11-13: seven published
    reports read an objective's cost per result with the ads that brought
    nothing left out): each ad's spend, cost per result, cost per 1,000
    reached and return; each objective's, every ad counted, an ad with no
    result type counted with its objective's one; the account's; the period
    before's and the change; what a few ads spent together; and an amount
    the period before's own report gave. One that matches none is a row of
    Check and submit (Figures in the commentary) and holds Submit and
    Publish; an amount with no cents is left alone. `report-draft` sends
    `by_objective` (the period's spend, results and cost per result, every
    ad counted) and its `group_cost_per_result` counts every ad that spent
    (`tests/objcost.js`).
  - Next batch (`2026-11-13-ads-next-batch.sql`; the user, 2026-11-13: "approve build both"): an Advertising Report's step between Commentary and Check and submit, never opened on by itself; Write with AI (`report-draft` `mode: 'next'`, its own use `ai_next_claim`, 3 a day, AI usage's Next batch) reads the report's ads and, where `meta_checks_on()` and an ad account is linked, Meta's frequency, CTR, spend and results by day over the period's last 14 days (`meta-import` `daily`, asked as the caller), and keeps up to six suggestions on the report (`sm_reports.next_batch`, a draft field), each a kind (Winning, Tiring, Clicks without {result}, New idea, Evergreen), its ad, title, evidence, plan, reason and points, a number none of the figures sent holds dropped; Add to commentary appends its points to Focus for next month with Undo, filed `report.saved`; Create task opens Add task prefilled (`ADspaceOps.add(pre)`), one task a suggestion: once its task stands, not cancelled (the task made from it kept on the suggestion as `task_id` while the report is a draft and read by its id; one made before, or past the draft, found by its title among the tasks made after the report's period ended, never an earlier month's; read once a visit, one request; review 2026-11-17), the row offers Open task #WT… in its place (the user, 2026-11-17); a Commentary step left on screen with words changed since it was shown or saved asks before the tab closes or reloads (`textUnsaved`, the page's `beforeunload`, which the build's idle probe hears too); those added print on the PDF's Next Batch page while `next_batch_print` is on, the snapshot sending them alone, never the evidence, and `figureSlips` reads its amounts (`tests/nextbatch.js`).
  - The Report audit (2026-10-09; the user: "there shouldnt be any
    mismatches"; `2026-10-09-report-audit.sql`): one card under Check and
    submit's checks (`.rp-aicheck`: Report audit, Run audit with the
    commentary checks left, then a check row a part, `.rp-part`), in two
    parts, each reading No issues / n to fix / Not run.
    - Against Meta (no AI use): `meta-import` with `audit: true` reads every
      ad account the client (or its brand) links, or the linked Page and
      Instagram account the report holds an account for, and the page runs
      Meta's export through the importer's own plan (`adsPlan`, `parseRows`,
      a post matched by `linkKey`: Instagram by its shortcode, else host and
      path without www., trailing slash or tracking query), so a difference
      is exactly what an import would change. Exact, at the precision held,
      but Reach (Meta's estimate, revised while a period runs), which
      matches within `reach_allowance_pct` (Business settings, 0.5 from
      the start, 0 to 5; `2026-10-10-reach-allowance.sql`; the card then
      says Reach within n% of Meta on n figures): each figure Meta gives an
      ad (by Ad IDs, else name,
      audience, objective, result type), its age split, Step 1's impressions
      and amount spent (reach only where one ad account answers; with two,
      each account's own reach, impressions and spend too), an ad Meta
      ran with spend and results that the report lacks (Add; one with no
      spend or no results is never asked for), one with figures Meta shows no
      delivery for (Remove, its own press alone), each post figure and a
      post on either side. The differences are one table (`.rp-metatable`:
      Where, Figure, Report, Meta in ink at 600, Difference, the act at the
      row's end; in a narrow pane the three figures side by side under their
      labels; words and splits wrap, figures keep their line);
      Meta's rows carrying an Ad ID a report row holds are gathered into
      that row as it was made (a spreadsheet with no ad set column makes one
      row of a creative's copies in two ad sets; 2026-10-12), for the audit
      and Import from Meta alone (`fromMeta`), never a spreadsheet or CSV
      file. A result type is the same however it is named (Leads (form) and
      Leads, Estimated ad recall lift (people) and Ad recall lift, Reach and
      reach; `resultKey`); a cost per result the report does not hold is
      the one it works out, to the cent; Meta's play time is to the second;
      an empty count is Meta's 0. A figure an export may carry no column
      for (result type, hook and hold rate, play time, retention, the age
      split) that the report does not hold is listed apart, Not in the
      report, and never counted (2026-10-12); Use Meta's figure fills it. The ad account's own time zone
      (`meta-import` `tz`) is named on the card where it is not GMT+8.
      Use Meta's figure, Add, Remove, and Update all from Meta (the figures
      and missing rows, never a Remove) write through the rows' own writes
      with one Undo, file `report.saved` (Report audit · n figures taken
      from Meta), file the reading again from the same answer, and check
      the commentary again where it had been checked and a check is left
      (else its line says the figures changed since). It runs only when
      Run audit is pressed (and an Advertising Report at Publish), never by
      itself (the user, 2026-10-09: every open page filed a reading), and
      reads the report's figures again at the press (`freshFigures`), so a
      page opened before a colleague took Meta's figures never files them
      as differences.
    - Each reading is filed (`sm_report_audit_save(p_id, p_outcome,
      p_rows, p_note)`: `match`, `mismatch`, `unavailable` with Meta's
      refusal, `override`; `sm_report_audits`, RLS on, no policy, no grant;
      the figures' print taken by `sm_report_meta_print`; the same reading
      again refreshes its time; a new outcome filed `report.audited`,
      Report audit) and read by `sm_report_audit_last` (Reports View). A
      match reads Matches Meta as of {day, time}; a figure changed after it
      holds the report again.
    - The gate (`sm_report_audit_blocks`, `meta-audit`), only where the
      client links Meta (`sm_report_audit_needed`; else Not linked, with
      Link accounts opening the client's Brand at Clients Work): Submit
      waits on a match of the figures as they stand (the page rests it:
      Match the figures to Meta to submit.); Publish reads an Advertising
      Report again at the press and needs a match since confirmation, while
      an Accounts Report publishes on the reading it was submitted on (a
      post's figures are lifetime totals that grow by the hour; one
      submitted before the audit is not held). Meta moved since: Send back
      with Meta's changes (its reviewer, submitter or an admin in review,
      Manage once confirmed) returns it to draft with the changed rows as
      its note. Meta not answering (not connected, token, not shared, busy,
      failed) reads Not checked: Meta unavailable and holds it; an admin
      alone continues without it (Continue without Meta, a reason, filed;
      the part's mark then the amber dot, never the done tick),
      at Publish since confirmation. Reports Select's Publish does
      not read Meta: an Advertising Report it holds is refused by name.
      While the period runs (today in Malaysia on or before its last day;
      `sm_report_running`, `2026-10-12-audit-while-period-runs.sql`; the
      user, 2026-10-12) nothing is counted: a reading is shown for
      reference and never filed, Submit is not held, and an Advertising
      Report's Publish is refused `period-running` until the day after.
      What the reader must know or do is a note under its part
      (`.rp-anote`: `--sunk`, led by the amber dot, ink at 13px), never the
      part's mute line.
  - The Commentary (the figures check until 2026-10-09; `report-draft` with
    `mode: 'check'`, `2026-10-04-ai-check.sql`):
    the commentary as it stands, drafted or written by hand, read against
    the report's figures; it lists only what is wrong (a figure not in the
    data, a claim the figures contradict, a comparison across result types
    or platforms, a word against our own work), each as where it is, the
    words, what the figures show and the words to use (Use). A report in
    draft or in review, Reports Work, asked first (Run audit's question names
    both parts and the AI use); the colleague's check on
    the report for the day where `per_report` is on, and one of the
    person's commentary checks a day (`ai_check_claim`; what is left read by
    `ai_check_left`, the button resting with the reason at 0), never one of
    a report's drafts
    (`ai_drafts.purpose`, `ai_draft_same` drafts only). Kept with what it
    read (`ai_check_done`, `result`, `basis`) and read by anyone at Reports
    View (`ai_check_last`), so the reviewer sees the same check; a
    commentary changed since says so. Filed as `report.ai_drafted` (AI used)
    with Report audit · Commentary and the count (older rows keep Figures
    check). A finding is put right where it is
    found (2026-10-09): on a draft at Work, Apply puts its words in place of
    the quoted ones (Remove words where it gives none), Apply all does every
    one still standing, each through the draft's own save with Undo where it
    happened and filed `report.saved` (Report audit · Commentary · n
    corrections applied); a finding whose words are gone and whose fix stands reads
    Applied.
  - A draft and its check agree (2026-10-09): Write draft reads its own
    answer with the check's rules before handing it over and puts right what
    the check would flag, inside the same press (never one of the day's
    checks; skipped past 70 seconds), and takes out a word that colours a
    figure (only, just, 仅, 只有) before a figure or a number word (only
    one, only a single; never "the only") wherever it still stands
    (`plainFigures`, `tests/plainfig.js`); a place among
    ads or posts (the cheapest, the second most viewed) is said only from
    the ranks the function works out (`cost_rank`, `rank_views`,
    `rank_engagements`), never read off the figures; tokens are kept once a
    press, every call added up.
  - What the AI is told sits apart from the report's own words: one shaded
    block (`.rp-aidraft`, `--sunk`) holds Draft language (the pill) at the
    left and Write draft at the right edge with what is left before it
    (`.rp-airow`; on a phone a line each), then Notes for the draft under a
    hairline; the hint and the fields follow it (the user, 2026-10-05).
  - The words: Write with AI (Commentary, Write caption and Write script
    alike, the AI mark before the words; 2026-10-10, the user: "not clear
    that this is going to be written by AI"), Writing while it runs, Written
    by AI. Read before submitting. on the Undo line; Run audit (Check and
    submit); AI usage (the Settings page); filed under subject AI; never
    "Draft with AI" or "Write draft".
  - Commentary written with AI is declared read at Submit (2026-10-10):
    `ai_written(p_report)` (`2026-10-10-ai-written.sql`, Reports View)
    answers whether Write with AI drafted the report; where it did, Submit's
    question carries the declaration (`ADspaceConfirm.ai`: the line and a
    tick that refuses until ticked), and the submit files `report.saved`
    Commentary written with AI, read and confirmed.
  - AI usage (the Settings page, `reports.ai`; `ai_draft_usage()`: the
    standards in `limits`, each person's `used`, `cap` and `own` for each
    use, every colleague who may write with AI listed before a first use:
    Reports, Content Review or Video Scripts at Work, Clients: Brand at
    View, Clients: Checklists at Work, Analytics; 2026-11-04), as approved (2026-11-03): Resets at 12:00 am; Today, a person a
    row (`button.aiu-tr`, the whole team their sum first) over seven use
    columns in fixed tracks, each `used/limit` (Off at 0), red with words
    where full, Own limits as a chip; on a narrow pane a person is a card of
    labelled uses two across; Standard limits, Edit (its head's `.btn-sm`)
    turning the seven into small fields in place and the report rule a
    switch, Save and Cancel in the foot; a person pressed asks Limits for
    {name}, a field a use (empty the standard, what they used today under
    each); This month, a use a row with its tokens (and searches) and US$,
    then Total. 0 to 500; only what changed goes through
    `ai_draft_set_limit`, each filed `team.changed` under AI from and to.
    No explanatory lines.
  - Captions (2026-10-08, `2026-10-08-caption-writer.sql`) are their own
    count (`ai_drafts.purpose` `caption`, with `batch_id`, `caption` 20 a
    day), read by `ai_caption_claim` / `ai_caption_left`. Brand analyses
    (2026-10-10) are their own count too (`analysis` 3, `purpose`
    `analysis`), priced with their web searches. Scripts (Video Scripts'
    Write script, 2026-10-09) the same way (`script` 10,
    `ai_drafts.script_id`); report drafts count `purpose` `draft` alone and
    commentary checks `check`.
  - Cost (the user, 2026-10-08: "Also check costing"): every call keeps
    `input_tokens`, `output_tokens` and `model` on its `ai_drafts` row
    (`ai_draft_tokens(p_id, p_in, p_out, p_model)`, once, the caller's own
    row, from both functions, drafted or failed). This month (MYT) reads the
    estimated cost in US$, by use (Report drafts, Commentary checks, Captions),
    the tokens and the prices, each row priced at the prices of its own day:
    `ai_price_in` (4) and `ai_price_out` (20), US$ a million tokens, Business
    settings (`app_settings_set`, from today; Edit prices, `team.settings`).
    A use from before tokens were kept is counted as not priced.
  - A draft is paid for once asked, so it is saved to the report as it
    arrives (`storeDraft`), a line opening with a dash kept as the point
    above's sub-point, as the PDF prints it (the user, 2026-11-03), and to the page's copy, the strip reading it at
    once (`localDraft`, 2026-10-27, RPT-10), with Undo putting the earlier text back
    (`restoreDraft`); a save that fails puts the draft in the fields with
    "Save before leaving.". While one runs, closing or reloading the tab
    asks first (`beforeunload`), and an answer that lands after the person
    moved to another step or screen is saved all the same and shown when
    that report's Commentary is next opened, once (`aiKept`).
  - Out of a draft the commentary check's findings fold under one line,
    and once confirmed or published they read as found, never to fix
    (2026-10-20, RPT-6, RPT-7).
  - Check and submit ends in the report's Record of changes (the user,
    2026-11-03: "who did it, what they did, when and optional why … full
    set"): every line filed against the report (`activity_log.ref`, the
    report's id, filed by `sm_report_log` and the page's `fileReport`; read
    by `sm_report_history(p_id)` at Reports View on a client in scope,
    whatever the reader's Activity access): steps, saves, imports, audits
    and AI uses, drawn by `ADspaceRecords.paint`, newest first, the why in
    each line's detail; a step its record lacks (a line filed before
    2026-11-03 that two reports of one period shared) drawn from the
    report's own date; then Total (so far), on the card's own padding.
  - Each objective lists its ads as the PDF ranks them: cheapest cost per
    result first, then those with no result by spend, most first. An ad's
    name opens its Edit; its ⋯ reads Open in Ads Manager, then Edit and
    Duplicate, then Mark or Clear ad error, then Remove (`data-g`); on a
    narrow pane a table with no picture gives up the picture's track and
    the dates wrap between their parts (2026-10-22, RPT-4, RPT-5).
  - Ad error (`sm_report_ads.ad_error`, `2026-10-16-ad-error.sql`; the
    user, 2026-10-16: a Meta delivery fault read as the cheapest ad): an
    ad's ⋯ Mark ad error asks a reason (200 at most) on a draft at Work, the
    row reads the Ad error chip and sits last in its objective, Clear ad
    error never asks, each filed `report.saved` with Undo where it
    happened. It stays in every total and table; the PDF never ranks or
    bolds it, puts it last with ¹ and one neutral note under the table (Not
    ranked: minimal delivery), never the word error. Nothing marks one by
    itself (an ad made days before the period ends spends little).
    `report-draft` reads it as `not_ranked` (left out of `cost_rank`, its
    reason never sent) and never names it an error or a mark, even where
    the notes do; the check flags those words (`AVOID`).
  - ROAS (`sm_report_ads.purchase_value`, `2026-10-25-ads-purchase-value.sql`;
    the user, 2026-10-25): a Sales ad alone holds a purchase value (the ad
    sheet's Purchase value with its ROAS read beside it; Ads Manager's
    Purchases conversion value column; `meta-import` from `action_values`),
    never below nought. ROAS is purchase value over amount spent
    (`ADspaceSmReport.roasOf`, `roasWord` `3.25x`), the objective's over the
    ads holding a value. Where any Sales ad holds one, the step, the PDF and
    `report-draft` (`roas_rank`) rank its Sales ads by ROAS, highest first,
    those without after by cost; the PDF's summary adds Return on ad spend
    and the Sales table's ROAS stands where CTR does, each marked ² with one
    note (as reported by Meta, from purchases its tracking attributes, may
    differ from the client's own records). A report holding none reads as
    before; `sm_report_meta_print` adds the value only where set.
  - Select on the Ads step ticks several ads (`.bulkbar`): Move to objective
    and Remove (asks, naming how many), each with Undo.
  - The Ads and Posts step heads keep the import and Add on show; Select,
    Import from Meta and Add pictures from Meta sit behind one ⋯ (`secMore`),
    each item drawn where its button was, the ⋯ leaving once none can be
    pressed (2026-10-20, RPT-2). In a narrow pane a row's figures carry
    their unit (`rp-unit`: 12 results, / result, views).
  - The age split must total 100% (±0.5).
  - Step 1's Results by objective show, until a figure is typed, each
    objective's results as the PDF adds them from its ads (the field's
    placeholder, read live; a mix of result types named part by part) and
    its amount spent beside them (`.readfield`, never typed).
- A commentary part the PDF numbers (What worked, Areas to improve,
  Focus for next month, and the older parts across platforms) reads
  numbered in the console as it prints (the user, 2026-11-03): a point a
  line, 1, 2, 3, and a line indented or opening with a dash its sub-point,
  a, b, c (`pointsHtml` over `ADspaceSmReport.pointTree`, the PDF's own
  reading); in a draft such a part reads first and its pen opens the box
  (`readFirst`, the box's own value redrawing it), an empty part staying a
  box.
- A step read and not edited (in review and after) is the facts card
  (`factsCard()`: `.ovcard` > `.ovsec`, each label beside its value, written
  text keeping its lines), one section a group: This period, Results by
  objective, Previous period; the commentary's fields, then a block a
  platform.
- Figure fields (`numFields()`, `data-num`) show a count with separators, a
  percentage to 1 decimal, and money as RM or S$. `numIn()` reads them back.
- Money fields take `inputmode="decimal"`; counts take `numeric`.
- New report: Monthly and Ad hoc are never both live, End's `min` is
  Start, and an empty date reads Select date.
- The ads PDF:
  - Ad performance ranks each objective's ads in a table; the cheapest is
    marked only among results of the same kind. Each objective's heading
    counts its creatives and the ads Meta ran (each Ad ID once, a typed row
    one ad) where those differ (`Leads · 21 creatives · 64 ads`), else its
    ads; under the glossary line (in the first month's How to read this) the
    page says a row combines every variation of one creative and what a
    weak row means (`VARIATIONS`). Creative performance then
    gives each creative (the name without its creator code) one card: one
    image, a line per objective and result type (amount spent, results,
    cost per result, reach, CTR; a missing figure a dash) under a head in
    Slate Regular, as every table in the report, the age split and video
    figures from the line that spent the most (2026-10-01).
  - The executive summary's Results by objective is one table under an
    italic band naming it (`band`), each objective's results, amount
    spent, cost per result and share of spend as a percentage; no bars.
  - An image added to one row of a creative is put on its other rows.
  - A result in a PDF table is its count alone (0 where an ad spent with
    none): the objective heads the table and the client reads the cost per
    result. The console's rows carry no result word either (the user,
    2026-10-02); `ADspaceSmReport.shortResult` stays for the sheet.
    A full block step separates one objective's table from the next.
  - The tax note follows the market: WHT and SST for MY; DCC and GST for SG.
  - Ad names never break at an underscore.
- Import controls read Import from spreadsheet and Import from Ads Manager.
- Meta checks (2026-10-10, `2026-10-10-meta-checks-switch.sql`; the user,
  2026-10-09: the imported figures did not tally with Meta, so hide it
  without touching manual entry, and keep it a setting): Import from Meta
  and the Report audit's Meta part run only while `meta_checks_on()`: the
  setting `meta_checks` is 1 (Business settings, the Settings page's switch,
  from today; 0 from the start) and the colleague holds `reports.meta` at
  Work (granted). Off, the import buttons are not drawn, `meta-import`
  answers `meta-off` for ads and posts, `sm_report_audit_needed` answers
  false so Submit and Publish never wait on Meta, and every manual import
  (spreadsheet, Ads Manager export) is untouched. The stand-in seeds it on.
- Import from Meta (`meta-import`, `docs/META-SETUP.md`, 2026-10-08): in the
  step head's ⋯ beside Import from Ads Manager (Advertising) and Import from
  spreadsheet (Accounts),
  drawn only on a draft at Work whose client (or brand) has a link
  (`meta_links_list`); with two ad accounts, or a Page and Instagram, it asks
  which (`ADspaceConfirm`, choices). The function reads Meta with the system
  user's token (`META_SYSTEM_TOKEN`, Graph `v26.0` unless
  `META_GRAPH_VERSION`, `appsecret_proof` with `META_APP_SECRET`), as the
  caller (Reports at Work, the report read under its own policies, the asset
  one the client linked), writes nothing, and answers Meta's export as text
  (`shape.mjs`: Ads Manager's with the account's row first and an Age text
  after; Meta Business Suite's Lifetime export, the Malaysian day). The page
  opens the existing import sheet (`pasteAdsSheet(opener, pre)`,
  `pasteSheet(opener, pre)`) named Import from Meta with it in, so one
  importer, one matching (Ad ID, link) and one summary line; the age split
  follows the figures in the same press, updating only ads it holds; an ad
  with no spend or no results is left out and counted in the summary line
  (`adsPlan` `withResults`, the audit alike; the user, 2026-10-09), and a
  copy of a creative that never ran is read after the copies that did and
  never writes over the ad they fed (its result type and zeros); posts go
  to the report's account on their platform; filed `Imported from Meta` /
  `From Meta`. An ad's reach is its age bands' sum where they name an
  Unknown band (`reachWithAges`, 2026-10-13): the Graph API's own reach
  leaves out people Meta could not age, which Ads Manager's export by age
  counts (2609W3_Balance: 800 against 6,484). Then each ad or post with no picture of its own takes
  Meta's (an ad's creative, a post's image or a reel's cover frame), read
  through `meta-import` `pictures` (Meta's own image hosts alone, one
  reader for a creative and `pictures`, `readMeta`: a redirect followed by
  hand, three hops at most, each held to them before it is asked, six a
  call, streamed and cut at 4 MB; 2026-10-22, BE-7; Meta's addresses expire within days; each ad's creative,
  as each post's metric here and in `brand-analysis`, asked of Meta on its
  own: Graph v26 refuses the `?ids=` read of many at once, 2026-10-12), drawn down to the
  320px JPEG and kept on the row (`.is('thumb_data', null)`: a picture the
  team chose is never replaced), filed `From Meta: n pictures added`; a
  picture Meta refuses leaves the row without, never the import. A refusal is one line under the step's head (`META_SAID`:
  not connected, token, not shared with the system user, busy, link gone),
  never Meta's words. Every figure is Meta's; none is AI's.
- Pictures from Meta (2026-10-13; the user: "can the import from meta take
  the creative image only"): on a draft's Ads step wherever the client
  links an ad account, whatever Meta checks says (a picture is not a figure;
  the user, 2026-10-13: the audit "inaccurate", the pictures needed without
  it), drawn while an ad holds Ad IDs; `meta-import` `creatives` (never
  `meta-off`) reads, for the
  report's own rows (three a call), the creative of the first Ad ID in an ad
  account the client links (the image, a link's or carousel's picture, a
  video's cover, its preferred frame, then the thumbnail at 1080; an image
  named by its hash alone read whole from the ad account's images before
  that thumbnail, which Meta crops square; 2026-11-17), never a
  preview of the ad and never a figure. It asks first, a tick replacing the
  pictures already held; only `thumb_data` is written, an ad left without
  is counted in one line, filed `From Meta: n pictures added` / `replaced`,
  and Undo puts each earlier picture back.
- The PDF:
  - Every section on its own page, on a golden-ratio scale, on the
    letterhead template (AL: 54pt sides, 72pt top and bottom, the wordmark
    and the page count; DESIGN.md, Print; 2026-11-20); no Methodology page. Page titles and the commentary's block
    heads are in title case (Executive Summary, Ad Performance, What Worked,
    Areas to Improve): a formal document.
  - Tables are white cells under a shaded title row, the title row and the
    grid in one grey (#f2f2f2: `HEAD` = `EDGE` = `FILL`, as the rate card
    draws it; every table head, a creative card's line head, a top post's
    figure labels), heads in Slate Regular, figures at one weight and
    centred (2026-10-02). A summary table (`roomy`: the account table, Results
    by objective, By platform) takes S(4) rows; working tables keep S(3).
  - Commentary reads one block per part: its head, its points numbered
    under it, on both kinds of report (never a label column beside the
    points).
  - The ranking table gives the ad's name the widest column, so a name reads
    whole; a missing cost per result or CTR is a dash. A figure never breaks
    inside its cell: each figure column is at least its widest entry in the
    cheapest row's heavier face, every objective's table shares those
    tracks, and the name takes the rest.
  - The foot is PRIVATE & CONFIDENTIAL and the page count on the margin's
    line; no draft or version line.
  - A draft carries DRAFT (INTERNAL USE ONLY) and a report in review PENDING
    REVIEW (INTERNAL USE ONLY), repeated over every page and drawn last
    (`WM` in `js/smreport.js`, drawn by `ADspaceDocs.watermark`) on the report's golden scale: S(4) in Slate
    Book at the golden angle (31.7°), the size times φ² apart along a row and
    φ⁴ between rows, each row offset half a step, grey at a tenth's opacity;
    confirmed, published and every version the client reads carry none.
  - A page break falls between points, never inside one: each numbered or
    lettered point is one unit (`unit`), split only when taller than a page.
  - A top post card is named by its title, else its type and day; its meta
    line adds only what the name does not (the platform where a page holds
    two, the date and type under a title). Its figures run the column's
    width. It carries no caption: the appendix row prints the caption whole,
    each paragraph wrapped (`captionLines`; past 40 lines it runs together
    and ends on `…`), the row as tall as it needs. The appendix has no Date or
    Format column: the Post column takes their room, a post named by its type
    and day says both, and a titled post carries them on a line under it.
  - Views by week colours each platform as its own (`PLAT_COLOR`, one
    Pantone family of equal brightness, never the platforms' fluorescent
    brand colours or a black (the user, 2026-11-10, set A): Facebook Marina,
    Instagram Living Coral, the two together Very Peri, TikTok Ultimate
    Gray, rednote True Red;
    a missing or repeated colour takes the next of `MORE_COLOR`); only the
    marks take colour. An account on platform Other is named by the account
    (the PDF names the platform otherwise, never the handle).
  - Every emoji is drawn and embedded before any page is laid out
    (`sh.ready()` before `draw`).
  - A "bold font" letter pasted into a caption (Unicode's mathematical
    letters, U+1D400 to U+1D7FF: 𝗙𝗿𝗼𝗺) prints as its plain letter, a bold
    one in the heavier face (`plainOf`, `boldMath`), never as an emoji
    picture.
  - An accounts report reads: Executive summary; Insights and
    recommendations, one block a platform; each platform's page with its top
    three posts ranked on that platform alone, each with its figures and its
    remarks; the appendix of every post with its figures. Posts are never
    ranked across platforms.
  - Named `{client} {report} {period}.pdf`.
  - The first kind is the Social Media Accounts Report.
- Meta switched off (SWITCHED-OFF ACTS, release B): Import from Meta
  carries `data-gate="meta:checks"` (off while Meta checks are off, or Meta
  answered `not-connected` within the hour); Add pictures from Meta (a
  creative's picture, read whatever Meta checks) and Edit Meta accounts
  carry `data-gate="meta"`; each drawn disabled with its reason.
