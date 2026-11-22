<!-- triggers: js/health.js -->
# Health (`js/health.js`, `?s=mine&view=health`, `?s=team&tab=health`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- A colleague's own check-in every half month (`2026-10-07-health-check-ins.sql`;
  `health_consents`, `health_log`, `health_checkins`, `health_talks`, RLS on,
  no policy, no grant). Health is sensitive personal data (PDPA 2010):
  nothing is asked before the colleague agrees, and every agreement and
  withdrawal is kept (`health_log`).
- Before agreeing, the card speaks as the company, the one place the console
  says "we" (the user, 2026-10-07): Your health matters to us; work and home
  both shape body and mind; answer honestly, there are no right or wrong
  answers; if something feels heavy, ask for a talk, reaching out early is a
  strength. Beside it, shaded, What you agree to (five questions every two
  weeks; ADspace management reads the answers by name, only to understand
  and support; never part of a performance review; withdraw at any time);
  then I agree, which never asks (`health_consent`). The words are the
  database's (`health_wordings`, each version whole, a new version a
  migration; `2026-10-18-health-terms-are-versioned.sql`): `health_mine()`
  sends the latest, an agreement names the version shown (`stale-wording`)
  and stands only on the latest (`health_agreed`), so a new version pauses
  the check-ins, the talks, the reminders and Team: Health (Terms changed)
  until the colleague agrees again. Withdraw asks (warn),
  stops the check-ins and takes the answers out of Team: Health; Agree again
  is the way back.
- The check-in (`2026-11-22-health-check-ins-by-workload.sql`; the user,
  2026-11-22, approving the redesign): `health_moods` (RLS on, no policy, no
  grant), a mood of seven steps (Very unpleasant to Very pleasant, discs
  larger towards either end, the chosen one Health's pink with its word
  under the row), Feelings and Influences from fixed lists (optional, tonal
  toggles in Health's tint), Workload (Overwhelming, Heavy, Busy,
  Manageable, Comfortable) and a note of 1,000; one sheet at a desk, three
  steps on a phone (Step n of 3 over a 4px track; Next the blue, Save
  tonal, Cancel turning Back, a choice kept moving back). Saved by
  `health_mood_save(p_start, …)` into the period the sheet showed
  (`stale-period` with the period open, the answers kept), edited until it
  ends; `no-mood`, `no-workload`, `bad-tag`, `too-long`. The half-month
  `health_checkins` are no longer asked and stay readable under Earlier
  check-ins (shut, Show), and in a colleague's sheet on Team: Health.
- How often (`health_period`, `health_load`): the week (Monday to Sunday,
  MYT) while the colleague's planned work this week is at or over
  `health_near_pct` (90) of their weekly capacity (Team's
  `capacity_minutes_week`, else `health_cap_default` 45 hours), else the
  month. The load is every open task they own whose day falls in the week
  or has passed (late work counts, shown apart), the day its draft due
  while the draft is not in, else its final due; a task with no estimate
  counts `health_task_hours` (2). An admin, a system account and a
  capacity of 0 are not measured (monthly). A check-in saved inside the
  period, of either kind, answers it. Each check-in keeps the load, late
  work and capacity as they stood when saved.
- Each morning (`health_daily`, pg_cron `health-daily`, 08:10 MYT): a
  colleague agreed with a check-in due is reminded `health_remind_days` (2;
  0 none) after the period opens, never on a public holiday
  (`health.remind`, Check in on your health by {day} ({weekday}).); while a
  colleague's week is heavy, every active admin but them is told once that
  week (`health.load`, Check in with {name}. / Their work this week is
  near their weekly capacity., opening Team: Health), agreed or not, never
  an answer; `health_alert` (1) turns it off. `my_hr_remind` no longer
  reminds of health. The five figures are Settings, Portal: Health
  check-ins (`team.settings`).
- Terms version 2 (the same migration) says what is asked and how often;
  everyone agrees again.
- The view: the period's card (This week's or This month's check-in;
  Checked in on {day}, else Open until {day} ({weekday}); a weekly period
  says why in one mute line; Mood, Workload, Feelings, Influences across
  it, two across when narrow, the note under them), Your check-ins (newest
  first: the day over its feelings and influences, Mood, Workload,
  Period), Earlier check-ins, Talks, then Agreed on {day} with Withdraw as
  one quiet line, never a card; one 12px step between them. A low mood or
  workload (2 or under), with no talk asked for, opens Talks with a word
  of care. A low answer is a warn word, never a colour alone; Health's
  pink marks its glyph and the chosen answer, nothing else.
- Ask for a talk (`health_talk_ask`: a colleague, an optional note;
  `already-asked`, `bad-colleague`) tells the colleague asked (`health.talk`,
  the asker's name, never the note); the asker withdraws it and asks again,
  the colleague asked marks it done and reopens it (`health_talk_set`); a
  withdrawn talk, which the colleague asked and Team: Health no longer
  read, is its asker's to delete from its ⋯ (`health_talk_delete`, asked,
  no restore, `bad-status` for an open or done talk;
  `2026-10-24-health-talk-delete.sql`, the SQL Editor's).
- Team: Health (`tab=health`) is an admin's alone, behind the Performance
  master code with its 15-minute unlock (`health_check(p_token)`,
  `health_team(p_token)`, `2026-10-18-team-health-is-an-admins.sql`; the
  same unlock either page takes; never a granted part, never offered to a
  group): four figures (Average mood, 4 weeks; Check-ins this period, n of
  m; Weekly check-ins; Open talks), Mood over time (the 12 weeks' average,
  a line) beside Workload against mood (the average mood under 50%, to the
  near figure, and at it or over, bars), a week or band of fewer than 3
  check-ins sent without its average and not drawn (no colleague read
  from an average), Colleagues (every active colleague: this period's
  mood, this week's planned work as a share of capacity or Not measured,
  Checked in, or Not agreed / Withdrawn as a chip; Due amber), each opening
  their check-ins and the week's load, and the last 90 days'
  talks. `health_team(p_token)` sends a colleague's answers only while their
  agreement stands and only those saved since it was made
  (`2026-10-18-health-answers-follow-the-agreement.sql`), and a talk's names, state and dates, only while its asker's agreement
  stands (2026-11-15), never its note,
  which only the two colleagues in it read
  (`2026-10-18-health-talk-notes-stay-private.sql`). The
  answers never reach a review, the Activity record or a notification.
- Health data is kept for a time (`2026-10-18-health-data-kept-for-a-time.sql`,
  PDPA 2010): `privacy_retention` removes a check-in for a half month that
  began more than `health_keep_months` (24) ago, and the check-ins,
  agreement, log and talks of a colleague no longer active who was removed
  or whose access expired more than `health_leaver_months` (6) ago; both
  Business settings (Settings, Portal: Health data kept, `team.settings`;
  6 to 120 and 1 to 60 months).

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| A colleague's health check-in | `#mineHealthBox` (`js/health.js`): before agreeing one card, the company's words beside the shaded terms on 1.618 : 1 (stacked when narrow); after, the half month's card with the five answers across as `dl.facts.health-facts` (two across when narrow, the fifth taking the row), the history table, Talks, and the agreement as one quiet `.health-agree` line; a word of care is a shaded `.health-care` box; the grid's gap is the only step between blocks |
