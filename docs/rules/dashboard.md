<!-- triggers: js/overview.js -->
# Dashboard (`js/overview.js`, `?s=dashboard`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Named the Dashboard on the screen (the rail, the tab bar, the heading,
  its guide; the user, 2026-10-11). Its address is `?s=dashboard` (the
  user, the same day), written by `queryNow()`; an old `?s=overview` opens
  it and reads `s=dashboard`. Inside, the route, `sectionOverview`,
  `ADspaceOverview` and the access key stay `overview`. A
  record's first pane (a client, a campaign, the client portal) stays
  Overview.
- Every colleague's start page (the revamp, 2026-11-13; the user: "the
  Dashboard for everyone", "proceed build fully"): `sectionAllowed('overview')`
  answers any colleague holding a section, and `firstAllowed()` lists it first, No
  access the floor (a colleague holding none) (`?s=noaccess`; 2026-11-11), so `/admin/` with no `?s=`
  lands there, and every other page names itself (the Clients list writes
  `s=clients`; a client's record reads as Clients from `client=` alone).
- The head greets the colleague on the Dashboard alone (`greet()`, the
  user, 2026-11-13): Good morning from 4:00am to 11:59am, Good afternoon
  from noon to 3:59pm, Good evening from 4pm to 8:59pm, Good night from
  9pm to 3:59am, Malaysia's clock, by their whole name, in place of the
  section's name; the date (`Fri, 13 Nov`) where the rail's group stands.
- Me (`pg=` left out; the strip's first tab): the colleague's own work,
  never anyone else's: four figures as v3 tiles (`#ovwMeLead`: My open
  tasks, Late, Due today, Waiting for you, from `ADspaceOps.mine()`, the
  tasks they own read as My Work reads them and Waiting for you's own
  reads; a colleague without My Work who may see leads reads My leads,
  Follow-ups late, Contacted and Won this month of the leads they sell),
  the Assistant as one field (`#ovwAsk`, Ctrl + J, two suggested questions
  from their figures; drawn where Ask is), then Today (`#ovwToday`: one
  list, Late, Waiting on you, Due today, each row its act, Decline and
  Approve on an extension, else Open; chips by kind where there are two
  or more; their leads past follow-up and their published reports not
  sent join it) beside Next 5 days (`#ovwWeek`: five working days, their
  tasks by due date and the client meetings they lead) and My clients this
  month (`#ovwMyClients`: the clients they are person in charge of whose
  month is this month, done and late on one bar). Each of their tasks on
  Today and Next 5 days leads with its ring (phase 4, the user,
  2026-11-13: `ringOf`, the outer line the time used from its owner's
  assignment to the end of its final date, the inner arc its checklist
  done, a tick once all of it is; amber once the time runs more than 20 points ahead of the work, or
  80% gone with no checklist, red once late; none with no final date). No
  period: Me is always now. The page reopens on the tab last used (`adspace-dash-page`), the
  address winning; a tab not offered falls back to Me.
- Team (`pg=team`; an older `pg=detail` opens it): the Summary below,
  offered where the group's Team dashboard is On and one of its cards is
  allowed (`teamOk()`: `teamAny()`), each card
  still asking Full Access on its own section. Team's group panel names
  the row Team dashboard (On / No Access): `overview` in the access map,
  stored only as `none` (On stores nothing), page-side alone; No Access
  hides the Team tabs, never Me. Team (phase 2, after the user's Halo
  references, 2026-11-13) reads the four figures (compact: the figure
  and its trend on one line, phase 4; Oldest late's trend the work
  delivered late each of the last six months), then Work by stage
  (`#ovwStages`, phase 4, the user's Workload strip: a ring a stage
  holding open work, split on track light grey, due within 2 days amber,
  late red, its count in the middle and who holds it under it, opening My
  Work's board), then People (`#ovwPeople`: each colleague's open work as
  a bar on one scale, its late part red, then open, late, delivered and
  on time from `ops_report`, a row opening their record's Work) beside On
  time by month, then Clients this month (`#ovwClientsMonth`: each client
  whose content month is this month, its posts done green, late red and
  open grey on one bar, its report and its meeting) beside Needs
  attention. Delivery against due date (`#ovwTimely`, 2026-11-18; the
  user: "gauge team members … what's done early or late", "highlight
  those slowest and most delays") stands beside Most delayed
  (`#ovwDelays`) after Work by stage, both from one `ops_timeliness`
  read a period (`R.timely`) at My Work: Reports and All tasks: four
  figures two across (On time or early against the On time target,
  Average lateness over all the work due against the Lateness target,
  each red with its dot where it misses; Average days early; Turnaround, the
  median with the slowest 10%), then a row a colleague (the system
  account left out): their work early, on the day and late as one bar
  (ink, the control grey, red; its key under the rows), On time, Lateness,
  Turnaround and Target (Met or Below); whoever is under either target
  first, the figure that misses red, a turnaround past the team's
  slowest 10% red; a row opens their Work. Most delayed lists the six
  pieces of work most days late, still undelivered ones included (Not
  delivered), each opening its task. Video scripts and Content Review
  have no tasks and are not counted. Open tasks and Open work by person are today's figures, so
  Team's alone, never Analytics' (phase 4). Team detail's charts,
  the Sales and Operations tiles and Active clients by month moved to
  Analytics (phase 3, 2026-11-13); a tile with clients behind it (New
  leads) opens Analytics on its card.
- Two pages, from the mockup the user approved (2026-10-12, task 47;
  `digital-form-tests` `mockups/dashboard/`) and then read as the company's
  director would (the user, the same day: "act as the company ceo"; the
  second page "continuous instead of hiding"): the strip `#ovwPages` (the
  view strip, Me · Team since phase 3, 2026-11-13) at the bar's left, a sideways swipe anywhere on the page
  turning it as the strip does (`data-swipe="ovwPages"`; the user,
  2026-10-12); every turn slides (a still copy of the page left moving out
  as the new page comes in from the side moved toward, Detail from the
  right, `--t-slow`, the bar holding still, the copy clipped below it). The bar's right holds
  the period (`#ovwPeriod`, a select of Today, Yesterday, Last 7 days,
  Last 14 days, This month, Last month, This quarter, Last quarter, This
  year, never a segment; `p=`, This month left out; each measured on the
  period before it the same days long, Last quarter on the quarter before,
  This year on last year; Today from its start to now, on the same hours of
  yesterday; Yesterday and a run of days end at today's start, so today is
  never in them (the user, 2026-11-19: "last 7 days (excl today)"), each
  measured on as many days before, said `on the day before` or `on the previous
  7 days`), with the
  span and the time read beside it; both pages read the one period.
  - Summary, in this order (the revamp, 2026-11-12, "go as recommended",
    replacing the order of 2026-10-22): four figures lead (`#ovwLead`:
    Delivered, On time, New leads, Oldest late; On time is met over the
    tasks that first reached client review in the period (a return after a
    revision never counted again; audit 2026-11-15) plus `late_open`, the open work late
    by the late rule (`2026-10-19-on-time-counts-late-open-work.sql`),
    reading a dash where nothing was due; the on-time and posted rings are
    gone, posting read in the trend), then Work by person beside On time
    by month and Clients this month beside Needs attention
    (`#ovwAttention`, `.ovw-pair`; Work by stage left with phase 2,
    2026-11-13): one list of every source (late
    tasks, open work for paused and past clients, reports owed and in
    review, cold leads, restricted accounts, requests, sets waiting, no set
    this month, bookings past their date, the quality check, unsigned
    letters, last month's reviews, overdue invoices at Clients: Billing
    Full Access, a row a client opening its Billing, counted and never an
    amount), its head a strip of the sources
    holding rows (`#ovwSrcs`, the view strip at the card's width: All, then
    each source's short word and count, red where it holds late work; a
    tab narrows the list to it; one source draws no strip and the head
    counts it), What · Section (the section's mark and name, never a
    record's kind; 2026-10-20, OVW-3) · Who ·
    Since, late first by the days late, then what waits, the longest first,
    then what has not started; five rows, then Show N more, a tonal toggle
    with its chevron that reads Show fewer once open and folds the list
    back to five (the user, 2026-10-12: "5 show only"); a row writes the
    record's address and opens it as search does; then Sales (Won,
    Churned, Committed monthly value)
    and Operations (Open tasks, Reports published for last
    month) as tiles (`.ovw-kpi`: the label, the figure, its change on the
    period before (`on Sept`, `on last quarter`) and its trend
    (`ADspaceChart.spark`) where it has a history; every tile keeps the
    trend's room, so a row of tiles stands one height; a label wraps onto a
    second line, never cut, and the lead row's tiles share their rows by
    subgrid so every figure stands on one line, `fit` failing a cut
    label, 2026-11-20); then Active clients
    by month. The trends: On time by month (delivered and posted,
    two lines) and Active
    clients by month (each figure over its column, this month lighter).
  - Detail, under its labels: Sales (Leads to clients, one-line bars, each
    step's share of the one before; Pipeline now, a ring with the whole in
    its middle; Sales moves: lost leads, paused, resumed, win-backs, lead to
    won as a median, conversion of the leads decided, churn of those active
    at the start, and for Services View the monthly value won and lost; Sales
    by colleague, new leads, won and lost by the colleague who sold them (a
    lead is never counted by its Person in charge; the user, 2026-11-17),
    a table of counts, never a ranking; Clients who moved,
    each move's clients (Won, New leads, Lost leads, Churned, Paused,
    Resumed, Win-backs) with their day and, by the move, Sales by (Won, New
    leads, Lost leads) or Person in charge (the rest), five a move
    then Show N more, and Committed monthly value by client, each active
    client's month highest first with its share and a total a currency, for
    Services View, each client opening its record (its Services); the
    Summary's New leads, Won and Churned tiles and Committed monthly value
    are a press opening Detail on their card (the user, 2026-11-12: "it
    has to be somewhere"); New leads by source; Why clients paused or left), then Operations (Open work by
    person, one-line bars, the late share red; Where work waits, each
    stage's median with its slowest 10% the mark and its open work beside
    it; On time by person, the late share red, with the median cycle; Reports
    for last month, its slices in their status dots; Creator bookings). These
    were Clients · Sales and My Work · Report, both removed the same day.
  - Each chart names its way out at its title's right edge (its section);
    side by side, a row's cards share four rows (a subgrid: head, chart,
    key, Figures), so their Figures start on one line, open or shut,
    whatever each table holds; Figures' hairline a step below the chart;
    three in a row run three across. In Sales moves, Churn rate and the two
    monthly values take a row each.
- Each tile, signal, chart and list source asks its own `may()` before any
  read, at Full Access (`manage`) on its section or part; the granted parts
  (`ops.reports`, `ops.all`, `team.performance`) at their grant; the lead
  tiles, chart, signal and rows ask `clients.leads` too. What is not
  allowed is not drawn and nothing of it is read. Reads are shared within
  a visit, one request a source whatever draws from it (`R` in
  `js/overview.js`: one read of the clients serves the sales figures, cold
  leads, the pipeline and restricted accounts; one of the bookings serves
  the chart, those past their date and the quality check), read again on
  every visit and on a period change (a page turn reads nothing again),
  never polled. The work figures (the period, the one before it and, once a
  visit, the last six months) are one `ops_reports(p_ranges)`, ops_report's
  own answer a span; the sets with none this month read a year back.
  Where a set's posts stand is one `review_set_counts(p_sets)`, read a
  thousand at a time (`readPages`; every list a function answers is)
  (invoker; posts, approved, changes, undecided, the oldest change), here
  and in Waiting for you alike, never a read of every post and decision;
  every set named is counted, with no cap
  (`2026-10-18-review-set-counts-every-set.sql`).
  The sales figures are `ADspaceSales.figures`. A refused read is `failLine` with Try again (in the list, that
  source alone; a tile reads Could not load with Try again; a signal Could
  not load), never nothing.
- Needs attention lists a piece of work once: a late report task is its
  owed report's row, and a late task of a paused or past client keeps its
  late row with Urgent delivery in its meta; Reports owed counts every
  report not published, as the tile does (2026-10-22, OVW-3, OVW-4).
- Committed monthly value is its one money figure (the user, 2026-10-12):
  for whoever may open a client's Services (`clients.services` at View),
  a month of each confirmed monthly line started by today (never a one-off
  item) by market, read from `client_services`
  under that part's own policy; anyone else reads Active clients in that
  tile, and the lines are not read. No other value, revenue or fee.
- Reports for last month (`sm_reports_owed(p_period)`,
  `2026-10-07-reports-owed.sql`, Reports Full Access, client scope): the
  reports the months of that period ask for (their Reports ticks), found or
  not started, and every report made for the period no tick asked for (a
  report is the month's whose span holds its last day, else its calendar
  month's); a client with neither is never listed (the user, 2026-10-07:
  not every client is a monthly engagement); a row opens the report, else
  its task.
- `batches.published_at` is stamped by `batches_published_at` on the move to
  published and cleared on Unpublish.
