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
- The check-in: Body, Mind, Sleep, Energy, Workload, 1 to 5 each (5 is well,
  a word for every step; each scale's two ends named under it, `hcE_*`,
  2026-10-27, MINE-7) as segments, and an optional note of 1,000
  characters, once a half month (the 1st to the 15th, the 16th to the month's
  end, MYT), edited until it ends (`health_checkin_save`: `no-consent`,
  `incomplete`, `bad-score`, `too-long`; the page names the half its sheet
  showed, one ended refused `stale-half`, the answers kept and the sheet
  naming the half open, `2026-10-18-checkin-keeps-its-half.sql`); the sheet opens on There are no
  right or wrong answers. Answer as you truly feel today.
- The view: the half month's card (Checked in on {day} under its title; the
  five answers across it, two across in a narrow pane with the fifth taking
  the row; the note under them), Your check-ins (a half month a row), Talks,
  then Agreed on {day} with Withdraw as one quiet line, never a card; one
  12px step between them. A low answer (2 or under), with no talk asked
  for, opens Talks with a word of care. A low answer is a warn figure with
  its word, never a colour alone; Health's pink marks its glyph and the
  chosen answer, nothing else.
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
  group): the half month's averages as
  bars (warn under 3) with `n of m checked in` (with nobody agreed, the one
  line No colleague has agreed to check-ins.), Colleagues (every active
  colleague: this half's five answers, Checked in, or Not agreed /
  Withdrawn as a chip), each opening their history, and the last 90 days'
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
