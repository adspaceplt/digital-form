<!-- triggers: js/analytics.js supabase/functions/analytics-read -->
# Analytics (`js/analytics.js`, `?s=analytics`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Trends over months, apart from the Dashboard's period (the user,
  2026-10-25; mockup `digital-form-tests` `mockups/analytics`): the rail
  row after the Dashboard. Each chart follows its own section's access
  (phase 3, 2026-11-13; the user: "Analytics follows each chart's section
  access"): a tab is drawn where any of its cards is readable, the trends
  at Full Access on Clients (and Leads) as before; Sales then holds Team
  detail's Sales charts and the Won, Churned and committed value tiles
  (`ADspaceOverview.forAnalytics`, New leads by source drawn once), and
  Operations (`tab=ops`) Open tasks, On time, Delivered, Reports
  published and the Operations charts, each card at its own access and on
  Analytics' period. Only the AI analysis asks the granted part
  `team.analytics` (an admin's by itself; `2026-10-25-analytics-admin-tool.sql`
  adds it to `team_roles_admin_guard`, so only an admin grants it), with
  both trends readable. Never the start page, never a tab of the phone's bar (under More). The data is
  read under each table's own policies; only an AI analysis is stored.
- Tabs (`tab=`, Sales left out; the view strip, a swipe, the arrows), each
  drawn where its section is at Full Access: Sales (Clients and Leads),
  Clients (Clients); no tab for a section until it holds a trend's history
  (2026-10-25, review 7). The period (`p=`: Last 12 months by default, 6,
  24, This year, Last year) is measured on the same span before it, ending
  at the same moment of its month, and a month a figure is divided by is
  the share of it passed (`prevOf`, `monthsIn`; review 2). A group at Own
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
  reporting"): the AI analysis card heads both tabs (`.anl-ai`), the
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
  Download (asks the AI declaration; drawn in the browser, FOR INTERNAL
  USE, never stored) and Delete (asked, no restore,
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
  once 24 are; until then each card says how many are held and when it
  opens.
- A refused read is `failLine` with Try again (`tests/analytics.js`, the
  forecast's arithmetic included through `ADspaceAnalytics._forecast`).
