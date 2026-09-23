# Operations system — setup

The internal task, workflow, time and audit model behind the console's **My
Work** route. Phase 1 is the database: the tables, who may read them, and the
server functions every write goes through. Phase 2 is the page. Nothing in
either is visible to a client.

## 1. Apply the migrations

In the Supabase SQL editor, run, in this order:

```
supabase/migrations/2026-09-19-operations-system.sql
supabase/migrations/2026-09-19-operations-phase2.sql
supabase/migrations/2026-09-19-operations-phase3.sql
```

All three are safe to run twice. The first creates fourteen `ops_` tables, their
indexes and their read policies, seeds two workflows with their stages and six
task templates, and creates twenty-three `ops_` functions. The only edits it
makes to an existing object are two guarded columns on `team_members`
(`capacity_minutes_week`, `wip_guidance`), both planning figures.

The second adds four functions and nothing else: `ops_add_link`,
`ops_set_link_archived`, `ops_set_checklist` and `ops_set_video`. Three of
phase 1's stage gates are data the page had no way to set — Client review
needs a draft link, Delivered needs a final link, Editing is refused while
footage is marked not ready — so without them a task created in the console
reaches Ready and stops.

The third redefines one function, `ops_log`, so that the event every write
files also tells the person it concerns: the accountable owner is told about a
change somebody else made to their task, a new owner is told they were
assigned, and nobody is told about their own act. It adds `ops_notify`, which
writes the row. No table, column, policy or permission changes; the bell in the
console reads the rows and marks them read, which was already the one direct
write a browser may make.

`supabase/schema.sql` carries the same text under **THE OPERATIONS SYSTEM**,
**THE OPERATIONS SYSTEM, PHASE 2** and **THE OPERATIONS SYSTEM, PHASE 3**, for
a database built from scratch.
`tests/ops.js` compares each against its own migration byte for byte, so they
cannot drift.

The rollback is at the head of each migration.

## 2. Give somebody access

Operations access is the portal's own access ladder, set on the Team page.
There is no second set of switches. The brief's seven capabilities map like
this:

| Capability | Key and level |
|---|---|
| Use My Work, work assigned tasks | `ops` at **View** |
| Create tasks | `ops` at **Work** |
| Assign and reassign owners | `ops` at **Manage** |
| See the whole team's queue | `ops.all` at **View** |
| Open Reports | `ops.reports` at **View** |
| Edit templates and recurring rules | `ops.workflows` at **Work** |
| Correct another person's hours | `ops.time` at **Manage** |

**The four parts are granted, never inherited.** Every other part in this
portal falls back to its section, because a part is normally a pane *inside*
the section's job: a group that works Clients works its Billing pane unless
somebody says otherwise. These four are the other direction. Seeing every
colleague's queue, reading the reports, editing the templates and correcting
somebody else's hours are all *more* than "work my own tasks", so silence
means no: a group with `ops` at Work and nothing else gets its own work and
none of the four, today and after somebody adds a new group next year.

Suggested settings:

| Group | Access |
|---|---|
| Admin | Everything, as always |
| Operations lead | `ops` Manage, `ops.all` View, `ops.reports` View, `ops.workflows` Work, `ops.time` Manage |
| Creative team member | `ops` Work |
| Sales | `ops` Work, if they should raise client requests; otherwise nothing |

A colleague with no `ops` level at all sees no My Work item in the sidebar and
is refused by the database if they call a function anyway.

The route is named **My Work** on the screen and travels as `?s=work`; the
ladder's key is `ops`, which is the word the database uses. The two are mapped
once, in `sectionAllowed()` in `js/admin.js`.

## 3. What a client account can reach

Nothing. Every `ops_` function's first check is an active `team_members` row
for the signed-in address, and a client contact has none. Every `ops_` table's
read policy asks the same question. `tests/ops.js` signs in as a client
contact holding a real login, with a database role that has been granted
select on every table, and asserts the count comes back zero.

## 4. What a browser may write directly

One thing: marking a notification addressed to you as read. Every other write
goes through a security-definer function, so a stage, a commitment date, an
assignment, a completion timestamp and an audit event cannot be set from the
page, whatever it sends. The tables carry a select policy and nothing else.

## 5. The workflows that ship

**General deliverable** — Intake, Ready, In progress, Internal review, Client
review, Revision, Approved, Delivered, Done, with Blocked, Waiting for client,
KIV and Cancelled beside them.

**Video production** — the same, with Shooting and Editing where In progress
would be.

The gates are data, not opinion:

- Ready needs an accountable owner and a final due date.
- Editing is refused while the footage is marked not ready.
- Client review is refused without a draft or review link.
- Delivered is refused without a final link.
- Done needs a delivery timestamp or a stated reason.
- Completion is refused while a required checklist item is open.
- Reopening needs a reason.

Stages are rows in `ops_workflow_stages`, so the team edits them from the
console once Phase 3 lands rather than waiting on a migration.

## 6. Time

Three different things are measured and never added together:

1. **Cycle time** — first active stage to completion, from the events.
2. **Stage time** — one stage entry to the next, from the events.
3. **Active work** — minutes somebody deliberately recorded against a task.

Nothing records idle time, keystrokes, screen activity, applications or
location. A work session exists because a person pressed Start.

One open session a person, across every task, enforced by a partial unique
index and not only by the function: starting a second task closes the first
and says so.

## 7. The page

**My Work** (`?s=work`) is the queue and one task open.

The queue is banded by when the work is owed — Overdue, Due today, Due this
week, Later, No date set — because that is what orders a day. Later is shut by
default and so is Finished, which the stage filter has to ask for. The bar
carries a search, whose queue (only where `ops.all` is granted), a stage
filter, **Group by**, the count and **New task**.

### At volume

Eight contents a week across thirty clients is about 290 tasks a month. Three
things carry that:

- **The read is bounded, and open work is not part of the bound.** Open work
  is read in full however old it is, because a task overdue since August is
  the first thing the queue exists to show. Finished work — the part that
  grows without limit — is read from the chosen period onward. The period
  select appears only while finished work can be on the page, which is the
  only time it governs anything.
- **Group by** re-bands the same rows: by due date, by client, by stage or by
  owner. Off the due axis every card is shut, so 290 rows read as thirty
  client headings with a count and an overdue mark each. That is the axis the
  spreadsheet always used, and it is the one to reach for when the question is
  "how is October going" rather than "what do I do today".
- **Thirty rows a card**, then `Show N more`.

A folded card is remembered per axis: a client card shut under By client says
nothing about a stage card under By stage.

### Three views

The same rows, the same search, filter and scope, asked three questions.
**List** is the queue above. **Board** lays one workflow's stages side by side,
in the workflow's own order, with the count in each column against the
work-in-progress guidance the stage carries (`4 / 5`, warn past it); the lanes
beside the line (Blocked, Waiting for client, KIV) are one **On hold** column,
and a finished stage draws only while the stage filter lets finished work onto
the page. The workflow select draws where Group by was, because the board has
fixed that axis. A card carries the same stage select a row does, through the
same function and the same gates. Above the board, **capacity**: each person's
recorded hours this week against the weekly capacity set on the Team page (your
own without `ops.all`, the team's with it). Nothing here measures attention; a
week with no sessions is a week nobody pressed Start. **Calendar** puts each
task on the day its final date falls, a press opening it; on a phone it is the
days that hold something, each named. The view travels in the address
(`view=board`, `view=calendar`); the list is the default and stays out of it.

### The bell

A change somebody else made to a task you own arrives as a row the database
writes beside the event, and the bell in the console bar counts the unread
ones. Pressing one opens the task and marks it read; **Mark all read** clears
them. Whose task, and what changed, in the team's words: `T1004 · Quarterly
report`, `The final date moved to 30 Sept 2026 by Aisyah.`

A task opens as a workspace on the same shape a client and a campaign use:
the number as its mark, the title, the stage as a chip beside the ⋯, and one
line saying what it is waiting on, derived on every repaint. Five panes —
Overview, Checklist, Links, Time, Activity — and a rail carrying the stage and
its moves, your timer, the dates, the people and the details.

Three things worth knowing:

- **One forward move is drawn as the action** and every other move the
  workflow allows sits in the select beside it. Which move is forward is the
  workflow's own to say: the stage nearest ahead by position, skipping the
  lanes beside the main line (blocked, waiting, KIV, cancelled).
- **A stage moves from the queue row too**, through the same function and the
  same gates, with the refusal named under the row. Blocked is not offered
  there, because it needs a category before it means anything.
- **Every refusal is named in the team's words**, not the database's. "Client
  review needs a draft or review link", never `needs-draft`.
- **The timer is one open session a person, across every task.** Starting one
  here stops the one running elsewhere, and the page says which task that was
  before you press.

## 8. Phase 4: the name, whose the work is, and the month

Applied by hand in the SQL editor, in this order, each safe to run twice:

1. `supabase/migrations/2026-09-23-operations-phase4.sql`. Adds the task's
   code, description, type and manager, the engagement tables, the content
   workflow, and the functions that create, name, duplicate, generate,
   repeat and hand a task on. Nothing already there is changed: every task
   keeps its serial, its stage and its history; a task from before gets its
   old title as its description and no code. General and Video are retired
   for new tasks and the tasks on them carry on. The same section is in
   `supabase/schema.sql`, so a full re-run of the schema is not needed.
2. `supabase/migrations/2026-09-23-price-list-preview.sql`, which reads and
   writes nothing and lists what the price list would change, line by line.
3. `supabase/migrations/2026-09-23-price-list.sql`, the rate card of
   2026-09-23. No price moves; wording changes on lines that still hold the
   seed's value, and two Meta advertising lines are added. A line corrected
   on the Services page is left alone.

What the team then has:

- **A task is named by a code and a description.** `2610W203 Content Post`
  is October 2026, week 2, the client's third task that month. The code is
  given on save and never changes; the description is edited in the record
  head, and the whole name copies on a press because it is the file name.
- **Scope is Client, Lead or Internal**, chosen on the sheet and checked once
  at creation. Task type (Engagement, Ad hoc, Goodwill, Special) replaces the
  template; the deliverable format is the rate card's list and optional.
- **Three dates**: the scheduled publish date (tentative until the content
  meeting), the first draft date, the final due date.
- **Duplicate** and **Repeat** in a task's ⋯; **Generate** beside New task
  for a month of tasks at once, previewed before anything is made, and for
  running the month's repeat rules.
- **The client record's Work pane**: the client's tasks by month, each month
  with its engagement (manager, pieces planned, the Drive folder, the content
  meeting, the thirteen readiness questions) and its status, which the
  database grants only when the questions are answered and the meeting is
  held or marked not applicable. Production on a task waits on the same two
  facts.
- **Hand over** beside the forward move: the next stage and the next person
  in one act, recorded and notified; a step the piece does not need can be
  skipped forward with a reason.
- **The term adjustment on a service line is a percentage**, prefilled from
  the rate card by the term's range and yours to change; the letter and the
  client's page read the figure the line holds.

## 9. What is not built yet

- **Content Review integration** and the reports the engagement record makes
  possible (planned against delivered per month).
- **Phase 5** the spreadsheet import, described in `OPERATIONS-MIGRATION.md`.

Each phase is deployable on its own and none of them breaks an existing part
of the portal.
