<!-- triggers: js/perf.js -->
# Performance (`js/perf.js`, `?s=team&tab=performance`, `?s=mine`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- Grades: Distinction, Strong, Baseline, Needs support, Improvement plan
  (keys A to E never move).
  - C is reward eligible unless the month before was also C.
  - An L3 or L4 breach makes the month not eligible.
  - Pacing counts only for people who run ads.
  - Grade bands, breach points (by level, a repeat, lateness) and their
    cap are settings from a quarter on (`2026-10-05-performance-rule-settings.sql`:
    `grade_a`…`grade_d` 90/80/70/60, `ded_l1`…`ded_l4` 3/7/15/30,
    `ded_repeat` 5, `ded_late` 5, `ded_cap` 35; `perf_grade_at`,
    `perf_deduction_at`), a month graded by its own quarter's, each issue's
    line and the figure its logging answers read with the same month's; `perf_calc`
    returns the `cap` and `points` it used, and the page names them from
    there, never a figure of its own.
  - An issue's points are kept as a number (`perf_points_at`, settings to
    two decimals, the VIC multiplier on the exact sum); the month's total is
    rounded once, to the 0.1 step the scores take, before the cap.
  - L3 caps at B; L4 caps at D.
  - An issue may name the client it concerns (`perf_breaches.client_id`,
    the issue sheet's Client, optional; `bad-client`); on a VIC client's
    work it is stamped `vic` at logging (trigger `perf_breaches_vic`, never
    changed after: `vic-stamped`) and its points are times `ded_vic` (2,
    from Q3 2026, Performance settings' Months part, 1 to 10;
    `perf_deduction_vic_at`), still under `ded_cap`; the review sheet, the
    member's page and the printed record read "VIC client · ×2" on it
    (`2026-10-15-vic-performance.sql`). Never a score in a notification.
- A member sees nothing of a month, breaches included, until it is released.
  - A dispute window from release of the month's `dispute_days` setting
    (7; 3 before 2026-10-01; a month keeps the window it was given), item
    by item. Every Performance figure is edited in Performance settings,
    an admin's: Settings' Performance group (2026-10-29; the gear beside
    the padlock is gone), one row a part (Months, Quarters, Bonus and trip,
    Commission), for `team.performance` at View, each asking the master
    code where no unlock stands (`ADspacePerf.openSettings(view, opener)`;
    an unlock run out asks again) and opening the sheet on that part
    (`#rwSView`), each label the rule in plain words (`RW_SET`). On a phone
    the padlock closes the Performance view row (`placeTools`), so the
    Team tabs stay whole.
  - Date of evaluation (`evaluated_on`, `2026-10-01-performance-date-of-evaluation.sql`):
    the day the numbers were reported to the member. The sheet prefills
    today while none is set; release fills it where empty; management corrects it until final (in or after the month, never
    after today in MYT, `bad-eval-date`). The sheet, the member's page and
    the printed record's head show it beside Queries until.
  - Management answers, then it is acknowledged and finalised.
  - `result` is a snapshot.
  - Reference `ADHR/{staff_code}/PR{YYMM}`; an Employee ID is required.
- Every `perf_` table has RLS on and no policy. Everything is revoked from
  public, anon and authenticated, then only the API functions are granted.
- Management is two locks: `team.performance` (granted) plus the master code
  (bcrypt in `app_secrets`, set only in the SQL editor with
  `perf_code_reset`).
  - An unlock lasts 15 minutes from last use.
  - Five wrong tries lock the person out for 15 minutes.
  - Nobody acts on their own review.
- A member's page always asks for a fresh proof (`perf_guarded()` true;
  `perf_code_fresh()` reads `otp`, `magiclink`, `webauthn` or `passkey` in the
  token's `amr` within 15 minutes): Use passkey first where the
  person holds one of their own, Email a code beside it. The code field takes 6 to 10
  digits. The Magic Link template prints `{{ .Token }}`.
- The review list is chosen (`perf_people.reviewed`, off by default; admins
  off unless added). The month lists the people on it plus anyone whose
  review of that month has begun, a colleague who has left included where
  that review is not a draft (`active` false; 2026-11-15); the Review list
  sheet ticks active colleagues code first, A to Z (`perf_profile_set`, Work).
- The department lives on `team_members`; Performance reads it and draws
  no role standard (the user, 2026-11-24; `role_family` kept, unread);
  `perf_profile_set` sets only its two ticks.
- Departments (`2026-10-23-departments.sql`, its SQL Editor part
  `2026-10-23-departments-editor.sql`; the user, 2026-10-23: "can add more
  departments?"): `departments` (key made once from the name and never
  moved, name, active, in_prize, five `criteria`; RLS on, no policy, no
  grant), seeded with Creative and Marketing in the prize. A colleague's,
  a review profile's and a prize score's department reference it
  (`*_department_fkey`). `departments_list()` (the team) is read once
  beside `me()` (`ADspaceAdmin.depts`, `deptName`; a failed read leaves
  the two of `W.dept`). Settings, Portal: Departments (`team.settings`):
  Add department, Edit (Name, In the department prize, its five criteria,
  each 2 to 60; `department_save`: `bad-name`, `taken`, `criteria-needed`,
  `bad-criteria`), the ⋯ Set inactive / Set active (never asks; offered to
  nobody, out of the prize, its colleagues keep it) and Delete where
  nobody is in it and no record names it (`departments_list` `in_records`:
  a colleague active or not, a review profile, a prize score;
  `2026-10-24-departments-in-records.sql`, TEAM2-15), asked under the title
  Delete (`department_delete`, `in-use`); the sheet is one table
  (`.ind-row.is-dep`: Department · Colleagues · Prize · Status, the pen,
  the ⋯ of Set inactive or Set active and Delete); each filed
  `team.changed` under Departments, from and to. The department prize
  (`perf_quarter_calc`, `perf_quarter_confirm`, `perf_dept_save`) takes
  every active department in the prize in the list's order, each with its
  criteria names (`names`, kept in a confirmed snapshot); Confirm waits
  for each one's scores; with none, `no-departments`. The maxima stay 25,
  25, 20, 15, 15.
- Months start from June 2026. The padlock sits at the right end of the tab
  row, outside the strip (`.tabline`), never inside it as a third tab.
- The print is drawn in the browser on the letterhead and never stored. It
  carries no version and no signature lines: a member acknowledges in the
  portal.
  - Under the letterhead it is the Social Media Report's design
    (`drawRecord`): sizes and spaces on `S(k) = 10·φ^(k/2)`, headings in
    title case, tables of white cells under a #f2f2f2 title row and grid,
    the month's grade shaded in one row of the five, the final score the
    one bold figure; page one the result (who, Result, Scores, What This
    Grade Means), page two the follow-up (Issues, If This Result Repeats,
    Improvement and Follow-up, Queries, Record of This Document); a
    heading keeps its block, a short paragraph never splits; the foot the
    template's row (each page its own record's Document ID · Verify document
    authenticity: go.adspace.me/verify, the page count at the right margin; 2026-11-24),
    the reference and who downloaded it above.
  - The download is filed first (`perf_printed` answers the server's time,
    who, their address and the released / acknowledged / finalised steps); a
    refused filing makes no file, and one's own record asks the fresh proof
    first (`perf_mine_gate`).
  - The file prints Record of this document (step, name, email, time in MYT,
    Document ID, the verify line) and every foot names who downloaded it.
  - A downloaded record is listed under HR Letters (`perf_register`, both
    `register.hr` and `team.performance` at View, own left out; its only act
    is Open review) and `/verify/` answers it as HR Letter, Valid (Replaced
    while reopened).
- History reads Downloaded for a print, and a save names each scorecard and
  rate it changed, from and to (`perf_save` files `changed`; a save that
  changed nothing files nothing).
- Both locks (the master code and the email code) are one centred `.lockcard`.
- The review sheet reads Rates behind the scores above Scores (the user,
  2026-10-11: the rates suggest the points): each rate a percentage
  management types, and Save works out each category's suggested points
  from them (`perf_calc` `suggested`), never the score. Two carry what My
  Work knows (`perf_ops_rate`, `2026-10-11-review-my-work-figures.sql`), a
  press making it the rate: On-time posting, the content tasks the
  colleague owns whose post date fell in the month (MYT) and has passed, and
  how many went live by its day; Timeline adherence, the tasks they own
  that reached their review in the month, and how many by every deadline
  they had (My Work's late rule).
- A category is scored by the letter ladder (the user, 2026-11-24), on the
  review sheet and in Rate yourself alike (`ladderHtml`, `ladderWire`): the
  letter (A Exceptional, B Strong, C Meets, D Below, E Poor; a select of
  five), then its steps, each a fifth of the maximum a point apart from the
  top (25: A1 25 to E5 1; 20: four a letter; 15: three; 10: two) and E0 for
  none (a segment while four or fewer, else the select); the readout
  `A2 · 24 / 25` and the total of 100 follow each choice; a suggestion from
  the rates is its nearest step. Points are stored as before and the grade
  bands stand; a figure stored off a step shows its nearest step, written
  once the form is saved, and reads as its figure alone where only read.
- Notifications never carry a score.
- Release carries Notify {name}, ticked by default on every month
  (`perf_release(p_token, p_review, p_rev, p_notify default true)`, filed
  `notified`); unticked, the member is not told and the sheet says so.
  A draft month's Notify, Save (tonal) and Share (the one blue) sit at the
  review sheet's foot (`#pvFoot`, `.qfoot`), where the scores end; never a
  `.sheet-foot`, whose primary Enter presses: Enter in a score never shares
  the month.
- Self-rating (`2026-10-07-performance-self-rating.sql`, `perf_self_ratings`,
  RLS on, no policy, no grant): a colleague on the review list rates
  themselves on the six scorecard categories in My records, Reviews (one
  Rate yourself card, a row a month newest first, the newest still to rate
  tagged Due and its button the one blue, a rated month its total and Edit;
  MINE-1, 2026-10-22), for each month from June 2026 to last month while its
  review is not shared (`perf_self_open`: `bad-month`, `shared`,
  `not-reviewed`; `perf_self_mine`); `perf_self_save` refuses a missing
  score (`incomplete`) or one outside its category's maximum or off a step
  of 0.1 (`bad-score`), filed `self.saved`. Management reads it beside its
  own scores (Self-rated n under each category, the total in one line); it
  never moves the grade.
- A month whose query window has closed with no query open is acknowledged
  and finalised by itself, earlier months too (`perf_close_windows()`,
  pg_cron `perf-close-windows` at minute 7 of every hour, `finalised_by`
  null); History and the printed record read Automatic, queries closed, and
  the review card says while the window runs that it becomes final then.
- A member's first open of a shared month is stamped (`perf_seen`,
  `perf_reviews.opened_at`, filed `opened`) and listed as Opened in History
  and the printed record.
- Reminders (`2026-10-07-my-hr-reminders.sql`, `my_hr_remind()`, pg_cron
  `my-hr-reminders` 09:05 MYT): one notice a colleague a day at most, naming
  only what is owed: on the 1st and `remind_again_days` (3) on, last month's
  self-rating (the review list only); `remind_before_days` (3) before each
  half month ends, the health check-in, only to a colleague whose agreement
  stands, the days held to the half's own (a February's second half is
  reminded on its first day at the latest;
  `2026-10-18-half-month-reminder-always-comes.sql`). Both days are Performance settings (Reminders, 0 to 14, 0 sends
  none). The bell and a push open the view (`perf.remind`, `health.remind`, tag
  `my-hr`); never a score or a note.
- An admin deletes a member's month in any state (`perf_delete`: the
  performance part at Manage, a live unlock and admin; never their own), from
  the row's ⋯ and the review's ⋯, with the name and month typed back
  (`{name} {Month YYYY}`) and a reason. The review, its disputes and scores
  go; its history rows stay (the link set null, which `perf_events_frozen`
  lets through below another write), one `deleted` row says who and why
  (Record deleted), and `perf_deleted` keeps a printed reference so
  `/verify/` answers it Void. There is no restore.
<!-- Performance rewards (2026-09-28) -->
- Recognition (`2026-11-22-recognition.sql`, `perf_recognitions`, RLS on,
  no policy, no grant): My records is Reviews, Recognition, Letters,
  Personnel, Health (`#mineViews`, `view=`), behind the fresh proof
  (`perf_mine_gate()`). Recognise (`perf_recognition_give`: Colleague, any
  active one but oneself and the system account; Category helped, effort,
  praise; Note 3 to 500; ten a day; the same press again answers the first)
  tells the receiver who and the category (`perf.recognition`), never
  points; Received and Given list each newest first, no points; the giver
  withdraws one waiting (`perf_recognition_withdraw`, Undo where it
  happened). Management (`team.performance` Work, a live unlock) confirms
  or declines it on the month's review sheet (`perf_review_recognitions`,
  `perf_recognition_decide`; Revert decision in its ⋯), never one they
  gave or received (`own`). It counts in the month given, else, where that
  month is shared or its quarter or half confirmed, in the month confirmed
  or the next month neither holds (`perf_recognition_month`); a shared
  month keeps what it counted (`month-released`). `perf_calc` adds
  `rec_points` a confirmed one, held to `rec_cap` (0 turns it off), after
  the issues (`recognition`, `recognition_raw`); `rec_confirm` off counts
  one as it is given; all three Performance settings (Months, Recognition).
  The printed record takes a Recognitions column only where they added
  marks. Every step is in the Activity record under Performance
  (`recognition.*`). Initiatives and the reflection are off the pages
  (2026-11-22); `perf_initiatives`, `perf_reflections` and their functions
  are kept, and no reminder asks for a reflection.
- Rewards (`2026-09-28-performance-rewards.sql`) are Performance's views
  Months, Quarters, Bonus and trip, Commission (`view=`, `q=` the quarter or
  the period's first quarter).
  - Worked out on every read (`perf_quarter_calc`, `perf_flex_calc`,
    `perf_period_calc`, `perf_commission_json`) from finalised months, but
    the quarter's ranking, which reads every month released to its member
    (any state but draft; `2026-10-05-performance-quarter-live.sql`; it
    waits on reviews, a person's month each, never called months), so
    management sees the order as it stands: `provisional` while the quarter
    runs or a month is not final or not entered, each row's `finals` said
    under its average (`2 of 3 · Not final`), and whoever is ahead reads
    Leading (the user, 2026-10-05). Confirm
    (Work) keeps a snapshot in `perf_rewards`; Reopen (Manage) removes it,
    files it and never asks. A month inside a confirmed quarter or half is neither
    begun, scored, shared, reopened nor deleted (`period-confirmed`, naming
    it, `perf_period_held`; 2026-11-15) until that period is reopened; a
    review is saved for June 2026 to the month in hand alone (`bad-month`).
    Quarters begin with Q3 2026.
  - The quarter (`2026-10-01-performance-quarter-ranked.sql`) is Ranking and
    rewards: best to worst by average, `rank` shared by equal averages, a
    short quarter's months under its average (`2 of 3`), and the individual
    prize from the average of the final months (a weak month can be made up),
    whole to the highest eligible average with no minimum (a tie shares it;
    the user, 2026-10-05).
    Confirm is drawn only once every review in the quarter is final
    (`months-open` refuses otherwise) and asks first where an ended month
    has no review (`missing_months`). The member's own quarter never carries
    `rank`.
  - The department prize goes to the winning department whole (`share`,
    named "{Department} won"); its team leader decides the split, so no
    member's row carries a figure for it. Tied departments are joint winners
    and one that does not qualify drops out. The department scores are
    `team.perfadmin`'s alone (`perf_dept_save` refuses `admin-only`, the page
    offers Department scores to that part alone; 2026-10-18), never of the
    scorer's own department (`own-department`, by `team_members.department`).
  - Flexible hours: a month decides the next only once every active member on
    the review list has a final review of it.
  - A bonus period is a half of the year (Q1 and Q2, Q3 and Q4; `perf_half`),
    named by its first quarter; any date reads as its half. Like a quarter,
    its Confirm is drawn and accepted only once every review in its six
    months is final (`months-open`, `scope` period; `open_months`), a
    draft of a colleague who has left aside (it can never be released);
    the chip names the reviews it waits on (`open_reviews`). Revenue and profit are
    read and written only by `perf_is_admin()` and filed by name only; the
    rest of management sees the amounts.
  - Every share is rounded down to the cent and the remainder stated, a
    commission too (`perf_commission_json`, 2026-11-15).
  - Every figure the rewards are worked out with is a setting
    (`2026-10-05-performance-reward-settings.sql`, `perf_settings`: both
    prizes, the department total, flexible hours' share and month, the pool
    and trip gates, the pool's share of profit, months at B, units by grade,
    the commission floor), each from a quarter on and read as at the
    quarter, month, half or deal month (`perf_setting`). Reward settings
    (`#rwSetSheet`, from Settings): management reads, `team.perfadmin`
    changes them from a quarter on (`perf_settings_set`), never into a
    quarter or half already confirmed (`confirmed`); each change is filed
    from and to (`settings_set`), and every calculation says the rules it
    used (`rules`), kept in the snapshot on Confirm.
  - Commission is pending until its month is final; the member sees it once
    decided. Nobody enters their own.
  - The caller's own row arrives with its name alone (`perf_hide_own`); the
    member reads theirs through `perf_rewards_mine()` behind the fresh code.
  - `perf_today()` is the one clock the rules ask; `tests/perf.js` replaces
    it, and the stand-in reads `window.__perfToday`.
