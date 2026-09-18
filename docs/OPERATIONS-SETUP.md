# Operations system — setup

The internal task, workflow, time and audit model behind the console's **Work**
group. Phase 1 is the database: the tables, who may read them, and the server
functions every write goes through. Nothing in it is visible to a client.

## 1. Apply the migration

In the Supabase SQL editor, run:

```
supabase/migrations/2026-09-19-operations-system.sql
```

It is safe to run twice. It creates fourteen `ops_` tables, their indexes and
their read policies, seeds two workflows with their stages and six task
templates, and creates twenty-three `ops_` functions. The only edits it makes
to an existing object are two guarded columns on `team_members`
(`capacity_minutes_week`, `wip_guidance`), both planning figures.

`supabase/schema.sql` carries the same text under **THE OPERATIONS SYSTEM**,
for a database built from scratch. `tests/ops.js` compares the two byte for
byte, so they cannot drift.

The rollback is at the head of the migration.

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

A colleague with no `ops` level at all sees no Work group in the sidebar and
is refused by the database if they call a function anyway.

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

## 7. What is not built yet

Phase 1 is the data model and the server. Still to come:

- **Phase 2** My Work, task creation, the task workspace, stage moves,
  blocking, due changes, work sessions on screen.
- **Phase 3** the Operations queue, the video board, Calendar, capacity,
  notifications.
- **Phase 4** the report functions and the Reports views, the client record's
  Operations tab, Content Review integration, recurring generation on screen.
- **Phase 5** the spreadsheet import, described in `OPERATIONS-MIGRATION.md`.

Each phase is deployable on its own and none of them breaks an existing part
of the portal.
