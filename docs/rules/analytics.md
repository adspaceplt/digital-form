<!-- triggers: js/analytics.js supabase/functions/analytics-read -->
# Analytics (`js/analytics.js`, `?s=analytics`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Trends over months, apart from the Dashboard's period (the user,
  2026-10-25; mockup `digital-form-tests` `mockups/analytics`): the rail
  row after the Dashboard. Each chart follows its own section's access
  (phase 3, 2026-11-13; the user: "Analytics follows each chart's section
  access"): a tab is drawn where any of its cards is readable, the trends
  at Full Access on Clients (and Leads) as before; Sales then holds Team
  detail's Sales charts and the committed value tile, and Operations
  (`tab=ops`) the Operations charts, each card at its own access and on
  Analytics' period (`ADspaceOverview.forAnalytics(name, spec, clients)`,
  a kit answering `can`, `tile`, `card` and `row`, so Analytics places
  every card itself; New leads by source drawn once).
- By when it is acted on (2026-11-22, the user approving the Analytics
  review with all its recommendations): each tab reads Act now, then This
  week (bands, `.anl-band` under `.ovw-group-h`), then Monthly review and
  Reference as folds (`details.anl-fold`), shut until opened and kept open
  in this browser (`adspace-anl-fold:{tab}:{band}`); a shut fold names
  what it holds on one line, the AI analysis's headline first where one is
  written; a band with nothing drawn leaves. Sales: Act now the tiles (new
  leads, win rate, clients lost, committed value), What changed beside
  Pipeline now; This week Sales moves, Sales by colleague, Clients who
  moved, each across its row (tables of different lengths side by side
  left a gap); Monthly review the AI analysis, the trend (Lead to client a
  line under its directions, `.anl-dir.is-fact`), sources beside lost
  reasons, value by client; Reference Leads to clients, then the busiest
  months. Clients: Act now its four tiles, Active clients by month beside
  What changed; Monthly review the AI analysis, joined and left beside why
  clients paused or left; Reference by industry beside by market, then
  length of stay. Operations: Act now Where work waits (its views
  `WAIT_VIEWS`, a segment once two are drawn: Time in stage joins there,
  never as a card), Reports for the month (its line `n of N published ·
  n owed · next due`) beside Creator bookings, drawn only while a booking
  is in production (`hideEmpty`); This week On time by person; Monthly
  review On time by month (from the Dashboard's Team tab) beside On time
  or early by month (`tlmonth`), then Delivery by kind of work (`tlkind`).
  Gone as said elsewhere: Won, Churned, the Sales copy of Reasons paused or
  left, and the On time, Delivered and Reports published tiles. Only the AI analysis asks the granted part
  `team.analytics` (an admin's by itself; `2026-10-25-analytics-admin-tool.sql`
  adds it to `team_roles_admin_guard`, so only an admin grants it), with
  both trends readable. Never the start page, never a tab of the phone's bar (under More). The data is
  read under each table's own policies; only an AI analysis is stored.
- Tabs (`tab=`, Sales left out; the view strip, a swipe, the arrows), each
  drawn where its section is at Full Access: Sales (Clients and Leads),
  Clients (Clients); no tab for a section until it holds a trend's history
  (2026-10-25, review 7). The period (`p=`: Last 12 months by default; Today,
  Yesterday, Last 7 days, Last 14 days, This month, Last month, This
  quarter and Last quarter, the Dashboard's own spans and words through
  `ADspaceOverview.span`, each on the one before it as the Dashboard reads
  it; then Last 6, 12 and 24 months, This year, Last year: the menu runs
  from the shortest span to the longest, the user, 2026-11-20) is
  measured on the same span before it, ending
  at the same moment of its month, and a month a figure is divided by is
  the share of it passed (`prevOf`, `monthsIn`; review 2). Over days
  every figure reads the days against as many before (a count, never a
  month's rate: New leads, not per month; no churn rate a quarter), while
  the charts by month keep the last 12 months under any period shorter
  than a year's months (the days, a month, a quarter) and no tile draws a
  month's trend there (the user, 2026-11-19: the days for the Dashboard and Analytics
  both). A group at Own
  clients only reads one line, Your clients only., under the bar
  (`.anl-own`; review 4).
- Sales and Clients read every client once a visit (`readPages`, the stage
  log) through `ADspaceSales.figures`, one figure call for the whole
  history (a source named as Clients names it, `ADspaceCRM.sourceWord`;
  a card's span takes its own line under its title at every width, so
  cards side by side read alike; 2026-10-27):
  Sales' tiles (new leads a month, win rate, lead to client,
  clients lost), its trend of leads and new clients by month, What
  changed (rules worked out on the page, never written), the busiest
  months, sources and lost reasons; Clients' tiles (active, joined, left,
  time as a client), active by month beside its own What changed, joined
  and left, by industry, by market, why paused or left, and how long
  active clients have stayed.
- Better or worse (`2026-10-25-analytics-alerts.sql`; the user,
  2026-10-25: "i dont see whether this analytics trend is good or bad"):
  every tile that compares and every What changed finding says Better,
  Worse or Steady (`judge`: each figure's own good direction, leads up,
  churn, days to win and clients lost down; a move under the Business
  setting `analytics_change_pct`, 10, or of under 2 in a count, is
  Steady), the dot and its word in ink (`.anl-verdict`), a finding's arrow
  in `--ok` / `--err`. Churn a quarter (clients churned over those active at
  the start, `churnOf`, Completed never among them) above `analytics_churn_pct` (10) reads Above alert
  on Clients lost and leads What changed (Churn above the alert; More
  clients left than joined; an industry most leavers came from), Sales'
  What changed taking the client findings that are Worse. Each trend
  says where the last six full months head (`direction`, a least squares
  slope: Rising, Falling or Steady, judged the same way). Both settings
  are Settings, Clients: Analytics.
- Write with AI (`analytics-read`, `2026-10-25-analytics-read-with-ai.sql`;
  the user, 2026-10-25: "use AI to do analytics deep analysis and
  reporting"): the AI analysis card opens Sales' and Clients' Monthly
  review (`.anl-ai`; 2026-11-22), the
  latest version read first: Health (good, mixed, poor), a headline, a
  summary, then a fold of risks (by severity, each level High risk, Medium
  risk or Low risk in one column at the right, `.anl-ai-risk`; 2026-10-26),
  what is working, the
  forecast's credibility, three to five actions and caveats, and Version n
  · period · Written by AI for {name}. Read before using. Write with AI
  asks first (what it reads, n left today, notes kept in this browser
  under `adspace-analytics-notes:{colleague id}`) and sends the figures this page worked
  out for the period on show (`figuresOf`: both tabs, the period before,
  the verdicts, the months, the forecast, `leads_complete_from` the setting
  `analytics_from`)
  and never a client's name; every number Claude quotes is checked against
  them (a point quoting another is left out, a headline or summary refused
  `ai-incomplete`). Its own count (`ai_analytics_claim`, `analytics` 3,
  team.analytics at Work; AI usage lists it), kept
  as the next version (`analytics_reads`, RLS on, no policy, no grant;
  `analytics_read_save`, `analytics_reads_list` the last twenty), filed
  `team.changed` under Analytics. Its ⋯: Versions (one shown at a time),
  Download (asks the AI declaration; drawn in the browser on the plain
  Internal use only page, never stored) and Delete (asked, no restore,
  `analytics_read_delete`, filed). Secret `ANALYTICS_MODEL` (unset,
  `claude-opus-5-5`).
- Full months count from the Business setting `analytics_from` (YYYYMM,
  seeded Sept 2026, Settings, Clients: Analytics, a month chosen from a
  list; `2026-10-25-analytics-counts-from.sql`, the SQL Editor's): before
  it the portal held won clients typed in later, never the leads lost
  (review 1), so a span before it judges no leads or win rate and the
  Sales tab says Leads are counted from {month}. (`leadsComparable`); an
  unrecorded source, or one holding every lead, is never a finding
  (2026-10-27, ANL-1, ANL-2). A forecast (dashed, over its likely range: the mean of the
  last six full months times the month's usual share, ± the last twelve's
  spread) is drawn only once 12 full months are held, from the month still
  running (its count so far in its name, the line of what happened ending
  at the last full month; review 8) to three ahead; the busiest months only
  once 24 are; until then neither is drawn nor said (2026-11-22).
- A refused read is `failLine` with Try again (`tests/analytics.js`, the
  forecast's arithmetic included through `ADspaceAnalytics._forecast`).
- Time in stage (2026-11-22, `ops_stage_times(p_from, p_to)`, `2026-11-22-time-in-stage.sql`,
  My Work: Reports at View): Where work waits' second view, shown from the
  moves already held. Every stay in a stage that ended in the period, from
  the move into it (the task's making for its first stage) to the move
  out, 5 minutes or more (a stage passed through is left out, as the task
  card's timeline folds it), credited to whoever held the task as it began,
  in the caller's client scope; calendar time. The view draws the content
  workflow's working stages (Ready to start to Scheduled) by median, each
  bar Across n tasks, in the card's own span words (`spanOf`); its figures
  a table by colleague over Ready to start, In progress, AQC review and
  Client review with All colleagues last, a cell on fewer than 5 stays a
  dash. On a narrow pane a card's views take their own row under its title
  (`tests/instage.js`).

