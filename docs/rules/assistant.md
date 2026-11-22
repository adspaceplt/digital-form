<!-- triggers: js/agent.js supabase/functions/portal-agent -->
# The Assistant (`js/agent.js`, `portal-agent`, `2026-11-13-portal-assistant.sql`, `2026-11-13-assistant-actions.sql`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Ask in the console's head (`#agentOpen`, Ctrl + J; the user, 2026-11-13:
  "ok approve, all colleagues, build all phases") opens `#agentSheet`: beside
  the page at a desk, a card above the tab bar on a phone. Every active
  colleague is offered it; the conversation stays until Clear or a reload.
- The page holds the conversation and posts it whole to `portal-agent`, which
  asks Claude (`AGENT_MODEL`, unset `claude-opus-5-5`; server-side fallback
  on) with a fixed list of tools and runs none of them: every tool runs on the
  page as the colleague. A read (`find_clients`, `client_summary`,
  `list_tasks`, `waiting_on_me`, `list_reports`, `find_colleagues`,
  `client_months`, `list_sets`, `list_campaigns`, `find_contacts`, and
  every other section since 2026-11-19, the user: "some questions it doesnt
  answer"): `overdue_invoices` (bukku-sync `invoices`, `clients.billing`),
  `client_billing` (`client_billing()`, complete or the fields missing,
  never its numbers or addresses; `clients.billing`), `list_quotations`
  (`ADspaceQuotes.stateOf`; `clients.quotes`), `creator_payments`
  (`creator_payments_queue`), `find_creators`, `creator_bookings`
  (`creator_bills_list`; the three at `campaigns.creators`, an amount only
  where the function answers one and `campaigns.pay` is held),
  `find_suppliers` (`suppliers_list`, never bank details, an NRIC, a number
  or an email; `suppliers`), `dashboard_figures` (the Dashboard's own
  periods, rules and counts: `ADspaceOverview.span`, `.can`, `ops_reports`,
  `ADspaceSales.figures`), `find_documents` (`register.documents` or
  `register.hr`, HR Letters only at `register.hr`; Letters of Offer at
  `clients.documents`), `list_scripts` (`scripts`), `find_links` (`links`),
  `activity_record` (`sectionAllowed('activity')`, its policy answering the
  rest), `message_log` (`wa_messages`, `mail_log`; `whatsapp`), `handbook`
  (every colleague) and `search_portal` (console search's own reads,
  `ADspaceSearch.find`, each result opened as search opens it). Each makes
  the screens' own reads under their policies, asks `may()` first (refused,
  it answers `no-access` with `what` it would have read and the section
  as the rail names it, which Claude says as "You do not have permission
  to view {what}. Please ask an admin.", never a key or a level), and
  never sends a contact's email or number, bank details, an NRIC, a salary
  or a code; an email or number in a name, note or summary is masked on
  the page, and one typed into a question by the function. `list_tasks` with a `query` finds a
  task by its words as My Work's search does (every task the colleague may
  see, open, finished or cancelled; title, code, description, brief,
  client or number), every word matching and a platform by any of its
  names (xhs, rednote, 小红书; IG; FB; a short name a whole word), words
  such as the and task left out, task 1008 a number: one search,
  `ADspaceOps.taskSearch`, My Work's own, read whole before it is matched; the prompt tells Claude to search again
  in fewer words before saying a task is not there (the user, 2026-11-13:
  "find the xhs account renewal task" found nothing). A client's name and its work go to
  Claude (approved by the user for the assistant, 2026-11-13).
- No bare "unable to answer" (the user, 2026-11-19): a question no tool
  answers is met by naming the section that holds it and `open_page` to it
  (`kind` section: every route, a section's tab such as Overdue invoices,
  Payments, the Email log or Hiring, and the Activity record's sheet; or a
  record, or a `search_portal` result); a button is drawn only where
  `sectionAllowed` (bridged as `ADspaceAdmin.sectionAllowed`) and the
  tab's key let the colleague open it, else Claude is told no-access.
- A change is a `propose_*` tool, drawn as a card of what will be written,
  from and to (`.ag-confirm`, its act Confirm, else the screen's own word:
  Book, Create, Publish, Unpublish, Send); nothing is written until it is
  pressed, through the function the screen uses (`ops_create_task`,
  `ops_assign_task`, `ops_request_due_change`, `ops_add_comment`, a Calls
  and visits row with the lead moved to Contacted, `sm_report_sent`); Undo
  where the screen offers one (Reassign, the call, Mark as sent); filed
  `assistant.task`, `assistant.call` or `assistant.report` (… confirmed
  through the Assistant) beside the section's own line; what was confirmed,
  cancelled or undone is told to Claude with the next question. `open_page`
  draws a button to the record on its own screen (`client_month` the
  client's Months). The assistant never deletes, sends to a creator or
  supplier, writes an email, or changes money, billing, quotations, access
  or performance: no change among its tools does (it reads them where the
  reads above allow). Captions, scripts, checklists
  and commentary stay their own screens' Write with AI.
- Actions behind their card (the user, 2026-11-13: "approve build both",
  the mockups "Assistant · actions with Confirm" and "Assistant · phone"):
  - `propose_meeting` books a client month's meeting as its Meeting sheet
    does (`ops_engagement_set_meeting`, then `meet-create` for a Google Meet,
    the default; On site takes a Google Meet off): the month must be the
    client's and open, a Google Meet from the next half hour; the card reads
    Client, Month, When (to when, MYT), Channel, Led by; done, the link joins
    it with Copy message (`ADspaceOps.meetingMessage`) and Open month; a slot
    the calendar holds (`slot-taken`) is refused in the card and the month
    put back; Undo moves an earlier event back or takes this one off;
    filed `assistant.meeting`.
  - `propose_campaign` makes a creator campaign as New campaign does (a
    draft, its creators, its person in charge, a link key; Active clients;
    Creator Campaigns: Campaigns at Work), filed `campaign.created` and
    `assistant.campaign`; no Undo (its way out is Delete, never the
    Assistant's).
  - `propose_publish_set` / `propose_unpublish_set` as the set's head does
    (Content Review: Sets at Work, an empty set never published), Undo the
    other way, filed `set.published` / `set.withdrawn` and `assistant.set`.
  - `propose_whatsapp` sends an approved template to a client's contact
    through the composer's path (`wa_compose_prepare`, the purpose's own
    template read afresh, else one named for a plain message; never a
    Document header; `wa-send`, which files it before Meta is asked;
    `ADspaceWhatsApp.may`): the card reads To (greeting and number),
    Template and its category, Sent recently, and the message as it will
    read; sent within `wa_repeat_hours`, it says so in warn and its act
    reads Send again (`again`); filed `assistant.whatsapp`.
  - `propose_schedule` keeps any of a reminder, Mark as sent, Add task,
    Publish or Unpublish set and a WhatsApp approval reminder, feedback
    request or representative for later (`agent_schedules`, RLS on, no
    policy, no grant; `agent_schedule_add` with `bad-time` (a minute to 92
    days ahead), `bad-kind`, `bad-condition`, `too-many` past 50 waiting,
    and the kind's own refusals at the colleague's access now;
    `agent_schedule_cancel`, `agent_schedule_list`), with an optional
    condition (`set_undecided`, `report_not_sent`, `task_open`); Undo
    cancels it; filed `assistant.schedule`. A Google Meet is never
    scheduled. pg_cron `agent-schedules` runs `agent_schedules_run()` every
    five minutes: each row due as the colleague who confirmed it
    (`request.jwt.claims`, as `ops_recurring_daily`), their access asked
    again, a condition no longer holding Skipped, a refusal or a fault
    Failed and told to them (`assistant.failed`); a reminder is a notice to
    the bell and the phone (`assistant.reminder`, opening its task, report
    or client); a WhatsApp is queued through `wa_enqueue` under the
    colleague's name after Sent recently is asked; `jobs_watch` counts the
    failed runs for the admins' morning notice.
  - The sheet's head holds Scheduled n (`#agentSched`, drawn while the
    colleague has any, n those waiting) opening the list (`#agentSchedBox`:
    each run's name, when and kind, Cancel while it waits, else its state
    and what happened); the empty conversation lists what the Assistant can
    do, Find and Do, after you confirm, then what waits (`#agentSchedHome`).
    The stand-in runs due rows through `window.__agentRun()`.
- A question is an AI use of its own (`ai_drafts.purpose` `agent`, 30 a
  person a day, AI usage's Assistant column): counted before Claude is asked
  (`ai_agent_claim`), each later step naming it (`ai_agent_turn`, the
  caller's own, under 30 minutes, twelve steps at most), its tokens added
  (`ai_agent_tokens`). The stand-in answers `portal-agent` from
  `window.__agentReplies` (`tests/agent.js`).
- A strict tool's field that may be one of a list or null is `anyOf` a
  string enum and null (`optEnum`), never an enum on a type list; strict is
  kept to the change cards and `open_page` but `propose_schedule`; every
  read is `LOOSE`, since Claude's
  API takes 20 strict tools, 24 optional and 16 nullable fields a request
  and refuses every question past them (2026-11-13; `tests/agent.js` reads
  the function's tool list and counts them). The stand-in never sends the
  schemas to Claude, so only a live question proves them.
- What a read answers is decided by the colleague's group access alone
  (the user, 2026-11-19: "team group permissions is the master control
  access"): a creator's default rate at Creators List access, as the list
  shows it; Dashboard figures only by the Dashboard's own rules (no work
  figures, their own included, without `ops.reports`). How many rows a
  read lists (25 to 40) and the Activity record's days (14, up to 90) are
  display bounds in `js/agent.js`, not settings (the user, 2026-11-19).

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| Asking the portal in words (the Assistant) | `#agentSheet` (`js/agent.js`): the task card's side sheet, 420px, at a desk; a card above the tab bar on a phone; a head (the AI mark in the action ink, Assistant at 600, Clear, the close mark), the conversation (`.ag-log`: the colleague's words right on the field's ground, the Assistant's left in ink, a list as a list, a word in weight, an Open button `.btn-sm` with the chevron), a change as `.ag-confirm` on `--raised` (its title 13/600, `.ag-facts` label beside value, from → to, Confirm the one blue at the right, Cancel quiet; then the green dot and its word with Open and Undo, the card on `--sunk`), a refusal led by the amber rule, the writing as three dots; the foot: three starting questions as tonal pills while empty, the box on the field's ground with the round blue send, the count left in 12px mute |
