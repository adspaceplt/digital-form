<!-- triggers: js/ops.js supabase/functions/meet-create -->
# My Work (`js/ops.js`, `?s=work`, permission key `ops`, mapped once in `sectionAllowed()`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Views (`view=`):
  - list (default, out of the address), board, calendar, months (an older
    `view=clients` reads as it). No Report view (removed 2026-10-12: the
    Dashboard carries the team's figures, its Detail page what only the
    Report held); an old `view=report` or `view=load` opens the list.
  - Each draws through `paint()` and `viewBox()`, never straight into a hidden
    box (`setView` draws a frame after the press).
  - A view without its permission falls back to the list.
- The list:
  - Show (`#workStage`): Open (`day`, the default: banded Overdue, Due
    today, In progress, Ready for review, Upcoming, No due date, Waiting,
    Completed today shut), Completed (`done`), All (`all`). Where the work
    has got to is Group by's question (stage, status), never a Show option.
  - The period select (`#workPeriod`): This week, This month, Last month,
    Last 7 days, Last 3 months, Last 6 months, This year. Every one runs to
    now but Last month, which ends where this month begins.
  - Group by day / stage / status / assignee / client / month; every
    card is shut off the day axis, and the heading carries its overdue count
    (`marksOf()`).
  - A search opens every card; a stage filter does not. A search finds any
    task the colleague may see, open or finished, any month, by title, code,
    description or number (`#WT00001`, `WT1`, `1`; `findAny`); the view,
    Whose work and the period do not narrow it.
  - The period draws only while finished work is listed and is named
    Completed (This week … This year); This month is its default
    (`data-default`), so it is counted only once moved.
  - An empty list says what it holds back: No open tasks. (Show completed),
    No completed tasks. (Show this year).
  - Whose work (`#workScope`) is a view, not a filter: Assigned to me,
    Created by me, The whole team (only with `ops.all`). No Following.
  - Clear filters returns the search and Show to Open; Whose work and
    Group by stay.
  - Mine keys on the owner's id, never their name.
  - The count is read against the chosen view.
  - Waiting for you (`#workWaiting`, 2026-10-08; on the Dashboard's Me tab
    since the revamp, 2026-11-13, My Work holding it no more): one card of
    what waits on the reader's
    decision: an extension asked of them (Decline / Approve in the row,
    `ops_decide_due_change`), a report they review, a booking Submitted on a
    campaign they run, a client request Requested and a set with Changes
    requested on a client they hold (Person in charge); each read asks its
    own `may()`, late first, then oldest, each row opening its record. Drawn
    only while it holds something. Awaiting approval (2026-10-10): a
    published set on a client they hold with posts the client has not
    decided, from `published_at`, and a booking at Reviewing on a campaign
    they run, from its last `option_qc` check, once either has waited
    `approval_reminder_days` (3, Due dates); Remind (tonal, while the
    approval reminder's template is on and `ADspaceWhatsApp.may('approval')`)
    opens the composer on the client's main contact with what waits and its
    link (the review page, the selection page) filled in. A candidate
    (2026-11-21) whose latest step on their page waits on the team
    (`hiring_waiting()`, read only where `ADspaceAdmin.hiringOk()`): Time
    chosen, New times requested or Offer declined to its Owners and the
    part, Offer accepted or Contract signed to the part, the position under
    the name, opening the candidate; it stays until a colleague acts.
- The read is bounded, and open work is not part of the bound. Open work is
  read in full, a thousand rows a page in id order (`readPages`) and put back
  in the final date's order; finished work is read from the period on (three
  filters, not one `.or()`). The period select draws only while finished work
  can be on the page. Who owns what is read for the tasks read alone
  (`readOwners`, 150 ids a part), never every assignee in the company.
- A colleague's own task on a client outside their reach names its client
  through `ops_task_clients(p_tasks)` (the name alone, tasks they may see;
  `2026-10-03-task-client-names.sql`).
- The row:
  - A tick (everyday task) or a progress ring (content task).
  - Assigned to is a pill, the disc and the name, one press opening the
    colleagues as the finder under it (`ADspaceForm.find`, any length of
    list; the user, 2026-11-13: "it requires a second click").
  - The name cell opens the task; the row is not one button.
  - The stage select moves the task (`moveTo()` is the one path for the row,
    the card, a drop and the task's head).
  - Under a finger a row swiped left shows its next step (`rowSwipe`; the
    user, 2026-10-11: quick actions): the name and date stay in sight, the
    stage and the ⋯ fade under one blue button at the right edge named as
    the task's own (`verbFor`), made as the swipe begins and gone as the row
    settles (a row at rest holds only its cells), pressed through `stepFromRow` as the select
    is. The swipe shows the act, never takes it, because a sideways swipe
    elsewhere changes the view (the row is `data-noswipe`); a press
    elsewhere, a scroll or another row's swipe puts it back.
  - One select for every task (`stageCell`): the whole workflow in position
    order, the current stage chosen, an unreachable stage greyed (never left
    out), a retired stage and Blocked listed only for a task on them.
  - Going back, skipping ahead, Cancelled and leaving a finished content task
    ask Why? under the control (`askWhy`, `ADspaceAsk.note` once); the reason
    rides the move (`p_note`, or `p_skip_reason` for a skip).
  - A move into AQC review asks who takes it (`openStep`, the creator first
    where that is somebody else) from the row, a board card and the task's
    own button alike; the same move never gives two results.
  - The outcome or refusal is named under the row (`.task-note`).
  - The stage track is 170px. A narrow row ends with the stage at a stated
    width; `is-tight` gives it its own line.
- Stage tone by `stage_group` (the status dot, `STAGE_TONE`):
  - not started and ready to start: grey;
  - in hand (in progress, a revision): amber, still running;
  - waiting on a person: amber;
  - cleared: green;
  - blocked: red.
- The board is one workflow at a time (`#workWf`, filled before the empty
  state; a retired workflow is offered while its tasks are in view).
  - WIP shows `n / wip_guidance`, `.is-over` past it.
  - On hold gathers blocked, waiting and kiv, and is drawn only while it holds
    something; it is not a drop target.
  - An empty column is drawn only where a task could move next, or at the
    workflow's entry.
  - The drag uses pointer events from `.bcard-grip` (`touch-action: none`),
    with a clone following the hand. Allowed columns are marked. The select
    stays on every card.
  - Every column runs the board's full height and takes a drop anywhere in
    it; in a gap the nearest column does. A card held at the board's edge
    scrolls it. A card never starts the browser's own drag, and a press on
    it selects no text (a stray selection cancelled the next drag).
  - No capacity strip (removed with the revamp, 2026-11-13): the
    Dashboard's Team tab names each person's open, late and delivered work.
- The calendar shows every task on its due date (the stage tone) and its
  post date (`--pub`), with a Due / Post key. A task whose next date is
  its post date shows once. A day holds five chips (`CAL_SHOW`), each two
  lines at 11px (`.cal-chip`), each its own block cut to the cell: the
  client (Internal, Lead · name; the stage dot before it) over the code and
  the format's short word (`2610W204 · Reel 30s`, `formatShort`), a task
  with no code its name; never the whole description (the user,
  2026-10-09). Then `+N more`. On a phone it lists only the days holding
  work, so a month with none reads "No tasks this month." (`.cal-none`). It also shows the content months the reader may
  see (read once with the calendar, held to Whose work: the reader's months
  or months holding a task on the list; the team's all): each month's
  meeting on its day (client · Meeting · time, opening its Months view),
  each report it owes on its due day (span end plus `report_due_days`;
  client · Accounts Report due, opening the report once made, else its
  report task, which it replaces on the day) and where it starts and ends
  (`.cal-mark`, a quiet line, never a chip; the user, 2026-11-17). A
  read of them that fails reads its fail line with Try again over the
  month, never an empty month, and a month or a meeting saved reads them
  again (`calStale`; review 2026-11-17).
- Months view (`view=months&wc=`, the tab named Months) is one bar, as every
  view (2026-10-22, WRK-M1): the view strip, the client (`#workClient`,
  `data-nofilter`, kept in the bar on a phone), the search, Filters, the
  count, the section's ⋯, New month and Add task, no label or heading; the
  list's own bar steps away (`placeMore`); on a phone the strip takes its
  own row, New month goes into the section's ⋯ and the count into the
  Filters sheet's head. Then that client's months, meetings and tasks
  (`clientWork()`), the client remembered per browser. A month's ⋯ is Edit, Add tasks (the New sheet on that client and
  month), Cancel month, Delete. A month whose tasks the filter hides
  says No matches (Show all), never No tasks this month.
- The phase 1 model:
  - The original commitment is written once; a date move takes a reason
    category and files the old and new value.
  - Cycle time, stage time and recorded work are three measures, never summed.
    Nothing records idle time, keystrokes, screens or location.
  - One open work session per person across every task, and one accountable
    owner per task (each a partial unique index as well as a function check).
    An ended assignment is kept.
  - Stage gates are data. Ready needs an owner and a date. Client review needs
    a draft link or a note. Delivered needs a final link. Done needs a
    delivery or a stated reason.
  - A second press of create, revise or generate is the same act (retry safe),
    two at once included: the key is locked before it is looked up
    (`ops_create_task`, `video_script_new`; audit 2026-11-15).
- `forwardOf()` reads the forward move off the workflow: the nearest stage
  ahead by `position`, skipping side lanes by `stage_group`. Never a
  hand-written list.
- A move back along the line is allowed with a reason
  (`back-reason-required`, filed `back: true`); never into a revision or a
  retired stage (`retired-stage`). A skip never files a revision or a
  retired stage as skipped.
- Reason categories are stored keys, named by `reasonWord()`: Client request,
  Scope change, Internal capacity, Pending assets, Pending confirmation,
  Incorrect date listed. The date sheet asks for one each time (Choose a reason, required;
  never prefilled), and its act reads Send request where it will only ask.
- Task fields:
  - Type: Retainer (key `engagement`), Ad hoc, Goodwill, Other (key
    `special`, 2026-10-09).
  - Format: the rate card's formats, optional.
  - Priority: Urgent, High, Medium, Normal (keys 1, 2, 4, 3: Medium took
    the key Low left, `2026-10-11-priority-deadlines.sql`, which made every
    Low task Normal once; an old 5 reads Normal; rows read in that order,
    `PRIORITY_RANK`). A priority is a deadline from when it was set
    (`ops_tasks.priority_at`, stamped by trigger `ops_tasks_priority_at` on
    creation and on every change of level): Urgent 24 hours, High 48,
    Medium 72 (Business settings `priority_{urgent,high,medium}_hours`, as
    at the day it was set; the Settings page's Priority deadlines). Only
    whoever created the task, My Work Manage or an admin changes it
    (`ops_update_task`, `priority-not-yours`;
    `2026-10-18-priority-set-by-whoever-set-the-task.sql`); Normal
    has none (the user, 2026-10-11: a task due the 29th raised to High on
    the 12th at 9am is owed by the 14th at 9am). Worked out on every read
    (`deadlineOf`, `ops_priority_by`), never written; the due date is never
    changed. It stops once the task reaches client review (an everyday
    task's Review) or is finished; On hold and Blocked count on. While it
    runs the row and a board card carry a strip down their left edge in the
    level's colour (red once over); while it comes before the due date its
    words stand in the Due column as a filled tag ("High · 31h left", red
    "High · 5h over", "Urgent · 19 days over" once over by a day; WRK-6), and the task card says Set to High … · deliver within
    48 hours, by … under the next step.
  - Complexity: Light, Standard, Complex (the key `simple` reads as Light).
  - The post date is required on a new content piece (below). It seeds
    the content month and week until they are touched (`ntTouched`). My
    Work says post, never publish (Post date, Set the post date).
- Duplicate (`ops_duplicate_task`: a new code, none of the history).
- Repeat (`ops_set_recurring`: weekly, monthly on a day, or every N days; ends
  on a date or a count). `ops_generate_recurring` is idempotent on rule and
  date.
  - The task a rule copies is its first occurrence: nothing is made on or
    before its day.
  - A monthly copy keeps its task's week; a weekly or every-N-days copy takes
    the week of its own date.
  - Made once is made: every date a repeat makes is kept
    (`ops_recurring_made`, by rule and by the task it copies; no policy, no
    grant), so a deleted copy is never made again and a repeat turned off and
    on again makes no date twice.
  - A task deleted stops its repeat (trigger `ops_tasks_stop_repeat`): a rule
    is seen and turned off only from its task.
  - One rule never stops the others: a make refused or failing is undone
    alone, kept on the rule (`last_error`, `last_error_at`, cleared by its
    next task), answered in `errors`, and named in the admins' morning
    notice (`jobs_watch`); the run goes on to the next rule.
- Repeats run themselves; nobody presses Run:
  - a client's month confirmed (its meeting set or marked not applicable)
    makes that client's repeats for it at once, as the person confirming
    (trigger `ops_engagements_confirmed`; a refusal never fails the
    confirmation);
  - every morning at 00:10 MYT (pg_cron `ops-repeats-daily`),
    `ops_recurring_daily()` makes this month's, and next month's in this
    month's last seven days (`ops_recurring_periods()`), each rule as the
    colleague who set it, else its task's owner, with that colleague's own
    access (`request.jwt.claims`). A rule neither can make waits.
  - Neither function, nor the trigger's, is callable from a browser.
- The bar's ⋯ holds Select tasks (Manage: a sticky bar with Reassign and
  Delete), and New month on a phone's Months; it is drawn only where one
  applies. Task templates (`ops.workflows` Work: edits families and makes
  no task, `ADspaceOps.openTemplates`), Task numbering (`ops.numbering`)
  and Due dates are Settings' alone (2026-10-29).
- A template is a family (`ops_template_variants`): one checklist and the rate
  card formats it serves, each with its own hours; a format belongs to one
  family (`format-taken`, naming it). A task's format fills it from its family
  inside `ops_create_task` (the checklist and the variant's hours; the
  caller's workflow and the month's dates stand), so every piece of the New
  sheet and every repeat alike. Reels (30s, 60s, 120s), Graphics (Static, GIF, Carousel),
  Report. Its sheet (`#tplEditSheet`) asks only that: Name, Active (a
  `button.switch`; an inactive family fills nothing), the formats with their
  hours and the checklist; a save sends the stored title, owner, due offset,
  estimate and workflow back unchanged (the user, 2026-10-12).
- A task is named by a code plus a description.
  - The code (`ops_code_of`: `YYMMW{week}{NN}` for the content month) is made
    once under an advisory lock; the owner or an admin corrects it in place
    (the name's one pen on the card opens the
    code and the description as one field, each part changed going to its own
    function; `ops_set_code`, `2026-10-08-task-code-editable.sql`:
    its shape kept, `bad-code`; the client's own for the month,
    `code-taken` naming the task; filed `code_changed`; Undo where it
    happened). The `#WT` serial stays the identity.
  - NN follows the month's plan (`2026-10-08-task-numbers-planned.sql`,
    trigger `ops_tasks_code_slot`): a Retainer piece (not a report task)
    takes the lowest free of 01 to `planned_count`, refused `plan-full` past
    it; any other task the lowest free after it (a month with no plan from
    01); a deleted number is used again; a type moved across is numbered
    again; a typed number keeps its range (`plan-range`, `extra-range`); the
    code is rebuilt from its month, week and number, so W1 is Week 1. The
    New sheet rests Retainer once the month's content reaches its plan.
  - The description is edited in place (`ops_set_content_desc`).
  - The number is `#WT00001` (`ops_serial`). The next number is set under `ops.numbering`
    (`ops_set_next_task_no`, refused at or below the highest in use).
- Scope is Client / Lead / Internal, checked once at creation
  (`ops_scope_error`):
  - Client offers active clients (paused by default; past on request);
  - Lead offers lead / contacted / proposal.
- Add task asks for a client or Internal every time.
- The content form offers Lead only where `clients.leads` is at Work, and
  Include past clients only where `clients.past` is; a refused read of the
  clients is named in the sheet, never an empty list.
- Add task and the content form open on one segment, Task / Content
  task (`.kindseg`). Switching swaps the sheet in place.
- Add task is one act: it saves, the sheet shuts, the list is read again and
  the new row says Added. (`state.rowSaid`).
- Every task has an owner from creation (the creator by default); the sheets
  offer no Nobody.
- A colleague whose group holds My Work below Work (No Access or View)
  takes no tasks (the user, 2026-10-15, option A: contract staff on sales;
  no setting of its own; View since 2026-10-18,
  `2026-10-18-tasks-need-my-work-at-work.sql`: a task asks Work to move):
  every My Work picker leaves them out (`ADspaceAdmin.takesTasks`,
  an admin always offered), Team's hand-over offers them for clients,
  campaigns and reviews alone (`TASK_KINDS`), the noon reminder skips them,
  and the database refuses them a live assignment or a month to manage
  (`ops_takes_tasks`, triggers `ops_task_assignees_takes_tasks` and
  `ops_engagements_takes_tasks`, `no-tasks`;
  `2026-10-15-tasks-need-my-work.sql`). Work already theirs is left as it
  is.
- Every colleague picker on a create form starts on the person creating it
  (Assigned to, a new month's Manager or one with none, a new lead's and a new
  campaign's Person in charge); they change it where someone else takes it.
- **Only the owner or an admin moves a task** (`ops_owner_may_move()`;
  `not-owner`). `mayMove(t)` hides the controls. The step says who has it.
- The step asks who takes the work.
  - One picker, Assign to, on the card and the step sheet alike (the user,
    2026-10-11: no switch, no tick box): its first choice keeps it with
    whoever has it (Me (name) for the reader's own; `__keep`), chosen on
    the owner's own steps; a hand-off opens on the person it usually goes
    to, else Choose a person.
  - The step sheet's act reads Move: its head names where it goes, so the
    label keeps one line in a phone's half.
  - `ops_transition_task` takes `p_assignee` and `p_skip_reason`.
- Skipping a step is ops Work with a reason, and never into a revision.
- Reassign (`ops_assign_task`, `ops_hand_over_task`;
  `2026-10-05-assignee-reassigns.sql`): the person a task is assigned to
  (My Work at Work, their own task) and any group above them (Manage, an
  admin); helpers and the reviewer stay a manager's, and both functions ask
  `ops_may_see_task`. `mayReassign(t)` draws the controls.
- Open to take (`2026-10-04-open-to-take.sql`, `ops_tasks.open_at` /
  `open_by`): the assignee or an admin offers an open task to the team
  (Offer to team / Withdraw offer in the ⋯, never asks;
  `ops_set_open`, filed `offered` / `offer_withdrawn`); any colleague at My
  Work Work whose client scope holds its client sees it (`ops_may_see_task`)
  and takes it (Take, asked first, naming who is told; `ops_take_task`,
  `not-open`, `already-yours`, `stale`), becoming its one owner, filed
  `assignment_changed` `taken`, the owner before told (kind `taken`). Any
  change of hands ends the offer (trigger `ops_assignees_close_offer`). The
  owner's row carries the Open to take chip; everyone else's own queue
  heads it under Open to take with Take where the stage would be.
- Urgent delivery: every unfinished task of a Paused or Past client reads
  Urgent delivery (`urgentDelivery(t)`, the red chip in place of the
  priority's; the first band on the day axis, above Open to take), worked
  out from the client's stage on each load (the list embeds
  `clients(name, stage)`; a client out of reach answers through
  `ops_task_client_facts`, else `ops_task_clients`), never written to the
  task, so the client back at Active clears it.
- On hold, Blocked and Cancelled go back only to the stage the task left
  (`ops_tasks.held_from`, stamped by trigger `ops_tasks_held_from`), and
  Cancelled also to the start of the line (`held-resume`; the user,
  2026-10-18: keep My Work's gates light, no AQC rule;
  `2026-10-18-held-tasks-resume-where-they-left.sql`); a task held before
  the column keeps the workflow's own steps. Reopen works on every
  cancelled task. Leaving Cancelled clears `cancelled_at`.
  A task finishes and reopens through `ops_transition_task` alone; the first
  model's functions are dropped (`2026-10-26-unused-functions-dropped.sql`).
- A task read that finds no row (deleted, or out of reach) closes its sheet
  or record and lands on the list with "That task is no longer available."
  (`taskGone`, `.maybeSingle()`); never the database's words.
- `derive(t)` is the one source for the head status, the next step and the
  stepper.
  - The next step is the one blue primary, a hand-off (`btn-go`) or your
    own progress (`btn-primary`) alike (2026-10-07).
  - One next-step button, named for where it goes (`verbFor`: "Move to
    Client review"), a paused task's (Waiting, On hold) Resume (the user,
    2026-11-14); no stage move beside it.
  - Draft due and Post date are a content task's: an everyday task (a
    month's report task included) shows its Due date alone, and its post
    date never reaches the calendar (the user, 2026-10-11).
  - The card's ⋯ is Take or Offer to team / Withdraw offer (where they
    apply), Duplicate, Repeat, Delete; who has the task is
    changed on its Assigned to row (the name and a pen at the facts' right
    edge, named Reassign; 2026-10-11), a task nobody holds from the
    next step's Assign, never from the ⋯. The row's ⋯ holds only what the row cannot do (Take where the row
    shows none, the offer, Delete) and is not drawn when empty. No timer,
    Revert, Move to another stage, Mark blocked or Cancel.
- The SOP workflow, numbered in this order: Ready to start, In progress, AQC
  review, Revision (Internal), Client review, Revision (Client), Approved,
  Scheduled, Live (`ops_mark_live`; a reason where the date differs),
  Performance review (+7 days, back to the creator), Completed, then On hold,
  Blocked, Cancelled, Taken down; rated 1–5 (`ops_rate_task`). Planning,
  Content meeting scheduled, Changes requested and Published are retired
  (`ops_workflow_stages.retired`): the month holds planning and the meeting.
  On hold and Cancelled are reachable from every open stage on the line,
  and lead back only to the stage left (above).
  General and Video are retired for new tasks.
- Results (`2026-10-10-post-results.sql`; the user, 2026-10-09: "doesn't
  have high views"): a client's task gone live records its views and
  engagements (`ops_set_results`, My Work at Work, `not-live`,
  `bad-number`; stamped `result_at` / `result_by`; filed `results_set` from
  and to) from the card's Details (Results, Not recorded until then), the
  week after it went live at Performance review. A month in Planning or
  Ready lists last month's best and weakest posts by views
  (`lastMonthRows`, three each), worked out on the page.
- Checklists for reach (`2026-10-10-checklists-for-reach.sql`, with its
  preview): Reels gains four checks (the hook in the first 3 seconds,
  licensed music, original footage, no absolute claims) and Graphics three,
  appended once each where the template holds them nowhere; the team edits
  them in Templates as any other.
- The everyday workflow: To do, In progress, Waiting, Review, Done, Cancelled.
- Time records: one stage table in workflow order (Stage, Visits, Time, a
  Total row); the sheet shows it open, with Recorded only where there is any.
- A draft link is optional. Without one the step asks Channel (`#stepVia`,
  WhatsApp / Other; the user, 2026-10-11: "no need type in where to send
  every single time"): WhatsApp files Sent to the client on WhatsApp., Other
  asks a Note; the database accepts the link or a note.
- A task is one card beside the list (`#taskDrawer`, `.sheet-side`,
  `open=`; the user, 2026-10-09: the full record was little used): an
  older `task=` address, a new task and a copy open it there; there is no
  full record.
  - The name with Copy title; under it one line: the client, the format and
    the month, the month itself opening its Months view (never `content` or
    `Graphic:`).
  - Next step, headed by the workflow's strip (`#dwSteps`, `paintSteps`:
    done quiet, the current step named, the next said; never buttons), then
    the report row on a month's report task, then Assigned to, Dates and
    Details (with Video for a task that has video details: Script and
    Footage readiness as selects saved by `ops_set_video`, since editing
    waits on footage), Checklist and Remarks stay open (Remarks: the
    comments, Add remark, Post); Brief, Files and links, Time records and
    Recent activity fold under More (`#dwMore`, shut each open).
  - A month's report task (`source_type` `report_social` / `report_ads`)
    carries its report (`paintReportRow`; the month's own, never one on
    request): once made, where it stands and
    Open report; before, Start report, made on the month's own span (a
    month starting on the 16th runs to the 15th) as New report does.
  - A link's Kind select sits left of its Address.
- The card's Details are changed where they are read (2026-10-08): Format,
  Type, Priority and Complexity as small selects drawn as the value
  (`.select.tdetail`: no box, the tonal ground on hover and focus, as
  `ADspaceAsk`'s field) (`ops_update_task`,
  `2026-10-08-task-details-editable.sql`: `deliverable_type`, `task_type`,
  `complexity`, `estimate_minutes`, each refused by name), and the Month and
  Week where the code may move (`ops_set_code` with the code built from
  them); each saved on change, put back on a refusal, filed `details_changed`
  from and to. For stays fixed: the client and its scope hang from it.
- Everything added can be corrected and taken back:
  - checklist items, links and comments (edit and delete are later events);
  - the brief and the priority (`ops_update_task`).
  - A required check has no ⋯.
  - A checklist tick repaints its own row only.
- A link may name a record (`ops_link_record`; kind `record`, `ref_type`
  campaign or set):
  - only the task's own client's, and once while the link stands;
  - Record in the Kind select (a client's task only) swaps the address for a
    picker of the client's campaigns and sets, less those already named;
  - it opens the console route in the same tab, reads the record's title as
    it is now (Deleted once gone), and has Remove and no Edit
    (`record-link`);
  - it is filed on both sides (`campaign.task_linked` / `set.task_linked`,
    `_unlinked` on Remove);
  - the campaign's Overview (`#campOvTasks`) and the set's panel
    (`#setTasks`) list the tasks naming them (`ops_record_tasks`: only tasks
    the reader may see, nothing without the record's section), drawn only
    where one does;
  - a task still owing its draft, with a set named, opens the link form on
    Draft with the client's review link written in.
- The content loop (`2026-11-10-content-loop.sql`; the user, 2026-11-10: one
  task one post, no switch): the Record picker also offers the client's
  posts (Content Review posts, `{set} · Post n`), linked by `ops_link_post`
  (`ops_task_links.post_id` on a `set` link; one post a task, one task a
  post: `has-post`, `post-taken`). A linked post moves its task by trigger
  (`ops_post_follow`, from `posts`, `reviews`, `batches`): its file AQC
  review, the set published Client review, the client's changes Revision
  (Client), the next round Client review, approval Approved; forward along
  the line or round the revision loop alone, from Ready to start through
  Revision (Client) only (On hold, Blocked, Approved and after are a
  person's; Scheduled stays manual), never where a person could not move it:
  a task never through AQC review goes to AQC review, not Client review, a
  task at Ready to start waits on its month (`ops_month_open_for_work`),
  and entering a review stamps Draft in (audit 2026-11-11); a task Content
  Review moved to Approved goes back with an approval taken back or asked
  again, and Undo of Add changes puts back the final date they pushed,
  where nothing moved it since, filed on the task and told to its
  owner, never failing the write. An unlinked task is unchanged. A post's ⋯
  Add changes (`review_record_changes`, a published set, no decision on
  the round) keeps the client's WhatsApp words as the team's changes, Undo
  where it happened (`review_revert_confirm`, any team decision); the set's
  panel names each task's post (`tests/contentloop.js`). Phase 2
  (`2026-11-10-script-follows-task.sql`): the picker offers the client's
  video scripts (`ops_link_script`, `ops_task_links.script_id`, one each
  way: `has-script`, `script-taken`); the script fills its task's Video
  (`ops_script_follow`, triggers on `video_scripts` and its scenes): Script
  Ready once published, the shoot from its day, Footage Ready once every
  scene is ticked shot, which moves a task at Ready to start into In
  progress; the script's facts name its task (`ops_script_task`). Phase 3
  (`2026-11-10-month-invoice-check.sql`,
  `2026-11-10-month-invoice-from-the-1st.sql`; the user: invoiced in
  advance, "issued 01/11 for November"): a month not cancelled is checked
  against Bukku from the 1st of its content month, whatever its stage,
  every night for four months while none is found or one stands unpaid
  (`bukku-sync` `month`, `ops_month_invoice_ask` as the caller,
  `not-started`, `cancelled`; `ops_month_invoice_take` and
  `ops_month_invoices_due` the service role's; `ops_month_invoices`, RLS
  on, no policy, no grant): an invoice of the client's Bukku contacts
  (a company billing other brands too left out, its invoice perhaps
  another brand's) dated within the content month's calendar month
  (`month_invoice_window`) is its invoice, one Bukku lists with no balance
  read Unpaid, never Paid (audit 2026-11-11); the month's card reads Invoice (number, amount, Paid or
  Unpaid; Not invoiced and when checked; Check Bukku) at Clients: Billing
  View (`ops_month_invoices_of`), and the Dashboard lists Months not
  invoiced at Billing Full Access once a read after the 1st found none
  (`ops_months_not_invoiced`).
- Dates:
  - The first draft is the team's own (`ops_due_decider` null) and must fall
    before the final date by calendar day (`ops_due_order_ok`, checked inside
    `ops_change_due_date`).
  - The final date moves only through the creator's approval
    (`ops_request_due_change` → `ops_decide_due_change`), except for its
    creator or an admin, who move it directly; `ops_change_due_date`, which
    both reach as definers, is closed to every browser
    (`2026-10-18-due-date-moves-through-its-ask.sql`).
  - Late = past whichever deadline comes first (the user, 2026-10-11): the
    final date, short of client review (`isLate()`, `reviewFloor()`), or a
    priority's, short of its review (`deadlineOf`). The Overdue band, the
    task card, `ops_report`'s late list (`over_minutes` for a priority's,
    read in hours under a day), open work by person, the on-time figures
    (met only where both were met) and the performance review's Timeline
    adherence figure (`perf_ops_rate`) read the same rule.
  - The control is named for what it will do: Request extension, or Change due
    date.
  - A row's date already set opens the due sheet (`openDue('final', row)`),
    which asks the reason; only a first date is set in place.
  - The ask is drawn under the dates:
    - Approve and Decline for the person asked;
    - Withdraw (`ops_withdraw_due_change`) for the asker;
    - nothing for anyone else.
  - The word "Move" is on no date control.
- A notification is written by `ops_log` / `ops_notify`, deduplicated per
  minute (a comment by its words).
  - The owner is told about another person's change.
  - A new owner is told they were assigned; a step that hands the task on
    tells them once (Handed to you … at …), never again for the move
    (`ops_log`, `2026-10-18-one-press-one-notice.sql`).
  - Nobody is told about their own act.
  - The bell is drawn for every colleague (a row is its reader's own), and
    re-reads every minute while visible, and on return, in the page's one
    check (`page_pulse`).
  - Each item leads with its section's rail glyph (`.notif-tile`,
    `ADspaceAdmin.glyph`): My records for a review, reflection, health or
    HR letter, Reports for a report, Video Scripts for a script, My Work
    otherwise. The bell lists
    unread first, then Earlier (`.notif-earlier`): read notices of the
    last seven days, ten at most (`.notif-item.is-read`); marking read
    keeps a notice there, never removes it. A colleague's notice (kind
    `notice`) leads with Team's glyph, says From {sender}, wraps its title,
    shows three lines of its message and opens nowhere: a press reads it
    whole in place and marks it read, the list left as it is (a row redrawn
    under the press read as a press outside the bell and shut it); one
    withdrawn is left out (`hidden_at`, asked for until a database without
    the column refuses it once).
  - A noon reminder (`2026-10-08-tasks-reminder.sql`,
    `ops_tasks_remind()`, pg_cron `tasks-reminder` at 12:00 MYT, Monday to
    Friday): every active colleague but an admin with no open task
    assigned to them, or who has never added a task, is told once that day
    (kind `tasks.empty`, opening My Work).
  - Task reminders (`2026-10-13-task-reminders.sql`, `ops_tasks_nudge()`,
    pg_cron `tasks-nudge` hourly from 10:00 to 17:00 MYT, Monday to Friday;
    the user, 2026-10-13: "not every single task needs to have a noti but
    it should have something"): each task's owner (never a system account)
    is sent one notice of what of theirs needs them, each task counted once
    as the first of Overdue (the late rule), Urgent (its deadline running),
    Due today (the due date or a priority's deadline), Not started (a
    starting stage, its draft due, else due date, within `task_start_days`
    (2), or with no date assigned that long ago); one task names it and
    opens it, several are counted ("5 tasks need attention: 2 overdue, 1
    Urgent, 2 not started.") with the first three named, opening My Work
    (kind `tasks.nudge`, push tag `tasks-nudge`), never more often than
    `task_remind_hours` (3); a VIC client's tasks are named first and
    counted apart ("2 for VIC clients"), and one that falls overdue after
    the colleague's last reminder is told at once, inside the window too
    (2026-10-15); both Business settings (Settings, My Work:
    Task reminders, 0 sends none). Not sent on WhatsApp. At 0, Add task (the
    quick sheet under Assigned to, a content task under its posts) says
    first that nobody will be reminded (`.remind-off`,
    `ADspaceWords.line.taskRemindOff`; SWITCHED-OFF ACTS, 2026-11-21); the
    task is still added.
- The month (engagement):
  - Made by hand, never derived from the client's service lines (the portal
    is supplementary: quotations and invoices are issued in Bukku). New
    month, New task and Duplicate offer last month and the next six
    (`fillMonths`).
  - It owes reports and starts on a day (`2026-10-04-month-reports.sql`):
    `reports` (`social` Accounts report, `ads` Advertising report, both or
    none) and `start_day` (1 to 28; the 16th runs to the 15th,
    `ops_month_span`), ticked and picked in the month sheet (Reports, Starts
    on), a new month taking both, and its Posts planned, from the
    client's month before (2026-10-27, WORK-3). Each
    report ticked is one live task (`ops_engagement_sync_reports`: the
    everyday workflow, format Report, the month's manager, one date: due
    23:59 MYT `report_due_days` (7) after the month's last day, no first
    draft date (the user, 2026-10-05), never from the Report template's
    offsets; `sm_report_gate` reads the same day; `source_type`
    `report_social` / `report_ads`); unticked, a task still To do is
    cancelled and a started one kept (`ops_engagement_cancel_reports`, the
    one copy); only a start day moved moves an open one's dates (filed), so
    another save never undoes an extension. Deleting the month cancels its
    report tasks nobody started first (`2026-10-04-month-delete-reports.sql`),
    and its question says so. `ops_engagement_counts` adds `content` (live
    less report tasks, `2026-10-04-month-counts-content.sql`): the New
    sheet's `n added` reads it; `live` / `open` still count the report, so
    the month stays in production until its report is done.
  - Two checks (Onboarding checklist, Pre-advertising checklist), seeded only on
    a client's first month and handed on when that month is deleted
    (`ops_engagements_hand_on_checks`), ticked by the client's checklist
    signed off (Clients, Checklists) and marked Not needed by hand; a row
    is the tick and the name with Not needed and Open (tonal, its chevron)
    at its right edge, under the name on a narrow pane (2026-11-11).
  - Posts planned is asked, never assumed: empty is refused, a whole number
    from 0 to 200 is taken (0 an advertising-only month's true answer), and
    the column holds the same (`ops_engagements_planned_range`). Reports is
    one answer of four, a segment (`#engReports`: Accounts, Advertising,
    Both, None; the user, 2026-11-03: a client taking content alone owes no
    report), a new month carrying the month before's, else Both; with no
    posts planned Accounts and Both rest and the answer moves to
    Advertising, put back once posts are planned; None is stored as no
    report and read as an answer, never a warning.
  - The card's head reads Runs (the month's span, its year) and Reports
    (each it owes, else None), each its pen at My Work Work
    on an open month, asking Starts on or the four answers and saving that one
    fact through `ops_engagement_upsert`, the rest as read (2026-11-02).
  - Its stage is worked out on every load (`engPhase()`), never picked:
    Planning until the ticks are answered and the meeting set (or not
    needed); Ready until the meeting has passed and the month holds a task;
    In production while any task is open; Ready to close (amber) once every
    task is finished and one done, where the card asks Add task or Complete
    month. A tick repaints the chip in place. The counts are
    `ops_engagement_counts` (the whole month, whoever asks; a refusal falls
    back on the tasks the page holds).
  - Only Completed (refused while a task is open, `tasks-open` with the
    count), Cancelled (the ⋯, asks, `Keep month`) and Reopen (back to
    Planning, never asks) are stored. Cancelled cancels the report tasks
    nobody started (`ops_engagement_cancel_reports`), Reopen asks for them
    again, and a report task nobody started follows the month's manager
    (`2026-10-05-month-edits-reach-reports.sql`). `ops_engagement_set_status` refuses
    Ready and In production (`derived-state`); a stored one from before reads
    as open. A task moves into production on the ticks and the meeting, never
    on the stored word.
  - The meeting is `meeting_minutes` (15–240) plus a link (Meet, Zoom or Teams
    only). The sheet (`#meetSheet`; the user, 2026-11-06) reads No meeting
    this month (ticked, the rest leaves, `#meetFields`), Channel, then for
    Google Meet Create link / Paste link (`#meetMode`; gone once its event
    is on the calendar, which a moved meeting moves), the link only where
    pasted or on Zoom or Other, then Date, Time (a select of quarter hours,
    8:00am to 10:00pm, a stored time off them kept as an option) and
    Length, Led by and Notes, nothing folded; a new meeting opens on the
    next free half hour. Only a meeting the calendar books (Create link, or
    an event already held) waits for the next half hour (`nextSlot()`: at
    3:00pm or 3:10pm the first slot is 3:30pm; `meetBooks()`), its date
    starting there and an earlier time refused on the sheet; a pasted link,
    Zoom, Other and On site take any day from the portal's floor, and the
    database refuses only a day before 14 Aug 2023 (`meeting-before-floor`,
    `2026-11-06-meetings-on-any-day.sql`). A meeting already held keeps its
    time when its sheet is opened. An On site meeting asks for no link
    (`2026-10-09-on-site-meetings.sql`; the user, 2026-10-09); once it has
    ended, whoever led it (else the month's manager) is told once to submit
    the outstation record (`ops_outstation_remind()`, pg_cron
    `outstation-reminder` every fifteen minutes, kind `outstation`,
    `outstation_told_at`; a moved meeting is told again), the notice
    carrying the form's address in `ops_notifications.link` (https only),
    which the bell and a push open in place of a console page.
  - The card (`engCard`) never repeats its heading: the month is named by the
    card above it, whose state chip (`.eng-mark`) shows only while shut. It
    is a card of its own above the tasks (the cards' hairline, the large
    corner; 2026-11-15, the user: "this is hard to read"): Manager, Planned,
    Runs and Reports as cells, each label over its value, the state and ⋯
    at the top right; on a narrow pane the state line first, then the facts
    as rows. The invoice, meeting, link and message are `.eng-row`s (a 120px
    label, 104 narrow, the value, the row's acts), the meeting changed by
    its pen (`data-a="meet"`, Set meeting while none), the invoice's number
    a `.linkbtn` in ink, Check again and Show quiet, the meeting in ink,
    never green; the message to the client set off by the card's hairline.
- New month never edits a month held: it offers only the months the client
  does not hold and sends `new: true`, which `ops_engagement_upsert` refuses
  `exists` (2026-10-22, WRK-1), opening on this month, else the next one
  free (2026-10-27, WORK-2).
- A press on one task reads that task alone, as does a task made alone or
  copied, which joins the list behind its card (2026-10-27, WORK-1); the catalogue is read once a
  visit and Waiting for you on entering and after a decision; a failed
  Waiting read is said in the card with Try again (2026-10-22, WRK-3, WRK-5).
- Every client deliverable goes into a confirmed month: one that exists, is
  open, and has its meeting set or marked not applicable (`no-month`,
  `month-closed`, `month-not-confirmed`). This holds for the New sheet,
  templates, Duplicate and repeats (a repeat waits, `held`). Everyday,
  internal and lead tasks are exempt.
- The New sheet (`#taskSheet`) is the one way work is added; there is no Bulk
  add or Run repeating tasks.
  - It reads Task details (For as a small segment with Include past clients
    at the right; Client and its Content month, Month for a lead, neither
    for Internal) and Posts, nothing else: complexity, a brief and a repeat
    are set on the task card (the user, 2026-10-12: "not so useful can
    remove so it looks nicer"). A client with no confirmed content month
    takes no posts: the posts step away for its line and Open Months
    (`#ntOpenMonths`), which shuts the sheet on the client's Months in My
    Work; a lead and an internal post need no month.
  - A content deliverable is posts, one shaded group with Add another
    inside it, each post one task headed Post n with its × once there are
    two: its description and format; its week and three dates; who it is
    Assigned to, its Priority and its Task type (the user, 2026-10-12: "7
    posts (6 retainers 1 adhoc) each have different dues different
    handling person, different urgency"), the deadline a priority sets
    from now said under that post ("Deliver within 48 hours, by 14 Oct,
    9:00am.", none for Normal). Add another draws the next as the post
    above (format, person, priority, type) with the week after (after
    Week 4, Week 1). Every post shares the client and month. Month reads
    `{n} planned · {n} added` (`ops_engagement_counts`); Retainer rests on
    a post once the other posts take what the plan has left.
  - `ops_create_pieces(p_payload, p_idem)` makes them through
    `ops_create_task`: 1 to 60 (`bad-count`), all or none, the same press
    twice the same act; each piece's own `owner_id`, `priority_level` and
    `task_type` stand over the payload's shared ones
    (`2026-10-12-pieces-of-their-own.sql`).
  - Every piece's line carries three dates, typed by whoever plans it and
    never worked out (`2026-10-06-three-dates-a-post.sql`,
    `dates_as_given`: no template offsets): Draft due (ready for AQC
    review), Due date (for client review) and Post date, each required
    (the user, 2026-10-09: "to curb delays";
    `2026-10-09-piece-dates-required.sql`): a line missing one is refused
    on the page and by `ops_create_pieces` (`dates-required` with the
    `piece`, "Post 2 needs its Draft due, Due date and Post date."), and
    nothing is made; a date further back than `task_past_days` (30, 0 to
    365; Settings, My Work: Due dates; `2026-11-10-task-dates-in-the-past.sql`,
    the setting saved by its SQL Editor part; the user's team, 2026-11-10:
    last week's work is keyed in afterwards), a draft due after the due date,
    or a post date before it is refused on its line. A task made before keeps
    what it has (Not set where blank); Add task, templates, copies, repeats
    and report tasks are unchanged. With several posts the button reads
    Create N tasks.
  - A move into Revision (Client) pushes the due date to today (MYT) plus
    `revision_due_days` (1) working days (weekends and public holidays passed
    over, `ops_add_business_days`; `2026-10-18-working-days-skip-holidays.sql`),
    only where that is later than the one held
    (trigger `ops_tasks_revision_due`, filed `due_changed`, reason Client
    request).
- Google Meet: only `meet-create` touches the calendar (the refresh token lives
  in its secrets), and only the record's own event (`admonth`/`adtouch` and
  its id): a stored id naming any other is never sent to Google, a delete
  clearing the record alone and a booking making its own (security audit
  2026-11-07).
  - It asks `ops_engagement_meet_prepare` (a month) or
    `client_touch_meet_prepare` (a Calls and visits meeting) as the caller.
  - It refuses a slot only where another online meeting overlaps it (a Meet
    link, or a Meet, Zoom or Teams address on the event; `slot-taken`,
    answered with the clash's start and end alone, never its title: it may
    be another client's); other events on the shared calendar do not count.
  - It re-reads until `hangoutLink` appears, and records `meet-pending`.
  - A record's event has one id, made from the record's (`admonth` or
    `adtouch` and its id's hex, Google's letters; 2026-10-19): a second
    press is answered 409 and takes the event the first made, never a
    second booking; its own event in the slot is no clash; one deleted and
    booked again is put back, confirmed, with a new Meet (`tests/meetfn.js`).
  - It names a setup fault (`meet-not-set-up` with the missing names;
    `google-token`; `google-refused`).
  - `ops_engagement_set_meet` accepts only a `meet.google.com` link. A null
    pair removes the event and its link, and leaves a typed Zoom or Teams link
    alone.
  - A month's Google Meet is deleted from its Link row's ⋯ (Delete, My Work
    at Work, asked first: `meet-create` `delete`): the event leaves the
    shared calendar and the link goes, the date and time stay, and Create
    Google Meet books a new one (the user, 2026-10-12); a link the database
    refuses to clear is said (`not-saved`), never answered deleted
    (2026-10-22, BE-8).
  - Not connected is not a failure of the save.
  - `clientMessage()` fills the one bilingual template, the team's words
    (`meeting_message_template`, `2026-10-29-meeting-message.sql`; Settings,
    Messages, Meeting message at `team.settings`; `meeting_message_save`
    refuses words without {date}, `no-date`, filed under Meeting message;
    the sheet refuses a field it cannot fill, naming it, 2026-10-29):
    {meeting}, {date}, {time}, {month}, {channel}, {link}, a line whose
    field has no value left out and a heading left empty with it; read once
    a visit, the seed's words standing in until it answers, Show and Copy
    filling it again at the press.
- The client portal shows meetings read-only (`portal_meetings`), never a task.
- Deletes:
  - `ops_delete_task` (Manage; the number typed back; a reason; an
    `ops.deleted` activity row);
  - `ops_delete_tasks` (bulk; the count typed back);
  - `ops_delete_engagement` (a reason; its tasks stay, its untouched report
    tasks cancelled).
- The task sheets live in `#workSheets`, outside the section.
- A stage move is dated the day it happened (`2026-11-19-stage-moves-dated.sql`;
  the user, 2026-11-19: moves pressed days later read the work late): the
  next step and the step sheet ask Date, today prefilled, back as far as
  `stage_back_days` (7, Settings, My Work: Due dates; 0 asks nothing) and
  never past today; a day before today goes to `ops_transition_task_on`,
  which makes the move through `ops_transition_task` unchanged and dates
  the rows it wrote and the stamps it set (Draft in, delivered, completed,
  cancelled), taken at 18:00 that day, never before the task's last move
  (`future-day`, `too-early` with `days`, `before-last` with `day`). A move
  made on a row, a card or by a drag is today's, its note offering Change
  date. `ops_task_events.created_at` is when a thing happened, which every
  figure reads; `recorded_at` when it was entered, said in the history as
  recorded {day} where the two differ. `ops_task_move_redate(p_event, p_on)`
  dates a move again: its colleague inside the window, or `ops.override`
  any day between the moves either side (`not-yours`, `after-next`), filed
  on the task as `move_dated`; an admin's pen on Draft in, Delivered and
  Completed opens it (`tests/stagedate.js`).
- Delivery against the due date (`ops_timeliness(p_from, p_to)`,
  `2026-11-18-delivery-against-due.sql`; My Work: Reports, client scope;
  by colleague and the most delayed at All tasks): a content or everyday
  task is delivered the Malaysian day it first reached client review,
  else the day it was done; a month's report task the day its report was
  marked sent (the first version sent of the month's own report), else
  the day it was done; work past its due date and not delivered is late by
  the days so far. Lateness is over all the work due (a day early counts
  nought); turnaround runs from the day a task was made, or a report's
  period ended. The targets are Business settings (`timely_pct` 85,
  `timely_late_days` 1; Settings, My Work: Delivery targets).
