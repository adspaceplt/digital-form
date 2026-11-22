# Overseas access (`team_abroad`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-22 and read before the area is changed. One place per fact, as CLAUDE.md §0.

- Overseas access (`2026-10-24-overseas-access.sql`,
  `2026-10-24-admin-notices-system-account.sql`, their SQL Editor parts
  `2026-10-24-overseas-access-days.sql` and
  `2026-10-24-overseas-reminder-setting.sql`; the user, 2026-10-24: "Allowed in
  Malaysia Singapore", "14 days per cycle", "Admins only"): the console
  answers a colleague outside Malaysia and Singapore only once an admin
  approves it. The country is Cloudflare's `cf-ipcountry` header
  (`request_country()`, which a caller cannot set; none, as for pg_cron, is
  never held); `team_place_ok` (an admin, MY or SG, no country, or an
  approved `team_abroad` row whose day (MYT) has not passed) is asked by
  `is_team()`, `allowed(p_section, p_level)`, `ops_granted`, `ops_me()` and
  `me()`, so every policy and function refuses the colleague; client pages
  never ask them. `me()` answering nothing, the console asks `abroad_state()`
  and a held colleague meets the cover (`paintAbroad`, js/admin.js: Access
  from {country} needs approval, Reason and Until, Request access; then
  Request sent with Change request and Check again; a decline, an end or a
  day passed said under it); `abroad_request` (`bad-reason` 3 to 300,
  `bad-until` today to today plus `abroad_days`, a waiting request
  replaced) tells every active admin (kind `abroad.request`, the bell
  opening the colleague's record, the request its `dedupe_key` names
  (`abroad:{id}:…`), never a namesake's), and while it waits, its colleague active and
  its day not passed, `abroad_remind()` (pg_cron `abroad-remind`, every
  fifteen minutes from 08:00 to 22:45 MYT; `team_abroad.reminded_at`, a
  request asked again starting afresh) tells them again every
  `abroad_remind_hours` (2, 0 to 24, 0 sends none; Overseas approval's
  sheet) as Overseas access waiting. The colleague's record decides it
  (the user, 2026-10-24: "Build its from me"): an admin's Team read asks
  `abroad_list()` beside `team_rows()`, the list's state column reads
  Overseas request while one waits, and Overview leads with Overseas
  access while the colleague holds a request of the last 90 days (the one
  waiting or approved as facts, Decline and Approve on the group, Approve
  asking Until, or End access in its ⋯; the rest under Earlier); nobody
  else reads it (`tests/abroadrec.js`); Settings holds no list of
  requests. `abroad_decide` / `abroad_end` filed `team.changed`
  under Overseas access and told to the colleague (`abroad.decided`);
  Overseas approval (`abroad_days`, 14, 1 to 30, and the reminder hours,
  Business settings). An
  approval covers any country until its day. A VPN or roaming data reads as
  where it exits; an edge function reads as where it runs (Singapore for a
  colleague here). The stand-in reads `window.__country` (Malaysia unset).
