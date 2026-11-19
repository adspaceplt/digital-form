<!-- triggers: js/personnel.js js/xlsx.js -->
# Personnel (`js/personnel.js`, `?s=team&member=…&mtab=personnel`, `?s=mine&view=personnel`; `2026-11-16-personnel-records.sql` and its SQL Editor part)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- The employee record form (sections A to H; HR-SPEC decisions 8 to 11 in
  `tests/hr-templates/`): one list of fields, the page's `FIELDS` and the
  database's `personnel_fields()` held equal by `tests/personnel.js`, each
  kept to its kind, length and AutoCount's own lists (Gender, Marital
  Status, Race, Religion, State; no Other; no previous salary). Every list
  opens on Choose: an answer nobody gave is never saved.
- `team.personnel` is a granted part (an admin tool, Manage alone) under
  Team: a colleague's record draws a Personnel tab only there; the
  colleague fills their own in My records, behind `perf_mine_gate()`,
  declared by the consent tick and their typed name (`personnel_save_mine`:
  `incomplete` with `missing`, `no-consent`, `bad-name`). Request employee
  record tells the colleague once a day (`personnel.request`).
- `personnel_records`, `personnel_salaries`, `personnel_settings`: RLS on,
  no policy, no grant. A record's answer never holds a salary or a file's
  key; a save is filed `team.edited` by field labels alone, a salary as
  Salary changed.
- The salary (decision 10) is read and written only through
  `personnel_salary_get` / `_set` and `personnel_export`, each asking the
  part and the master-code unlock (`personnel_check`, `personnel_unlock`:
  the Performance unlock's token, 15 minutes), the page asking first
  Sensitive information follows / Proceed with caution. Never in a list,
  notice, search, the Activity record or AI.
- NRIC front and back and the photograph go to S3 `private/personnel/{colleague}/`
  through sign-upload purpose `personnel` and come back as bytes through
  sign-download `{ personnel: { member, kind } }`, each asking
  `personnel_file_member` / `personnel_file_key` as the caller.
- Download for AutoCount (Team's ⋯) fills `admin/hr/achrms-template.xlsx`
  (`js/xlsx.js`: rows from 3, the template's sheets, lists and validations
  untouched, stored entries) after checking every value against AutoCount's
  lengths, dd/MM/yyyy and lists, naming each problem and making nothing
  until none stands; never stored; each read filed by the database (a count).
  The basic rate is the salary in force today (confirmed once the Confirm
  Date has passed). Company defaults are Settings, Portal: AutoCount HRMS
  (`personnel_settings_set`, `team.settings`, each from its list); a
  department's AutoCount code is `departments.ac_code`
  (`department_ac_code_set`, `taken`, `bad-code`).
- On a Confirm Date (join date plus probation months, MYT) every active
  admin is told once, masked (A probation review is due. Sign in to view.;
  pg_cron `personnel-probation` 08:25 MYT, `personnel_probation_due`); the
  notice's key carries the colleague's id alone and opens their Personnel
  behind the caution and the unlock. A colleague erased empties their
  record and salary (trigger `team_members_erased_personnel`).
- An HR form downloads as a PDF for an admin alone (`js/hrforms.js`,
  `2026-11-19-hr-form-downloads.sql`; the user, 2026-11-19: "admins and
  requires verification code to download"): Download on the employee
  record (the Employee Record Form: the terms, the answers by section, the
  declaration, the photograph and the NRIC copies, never the salary) and on
  Onboarding (the Onboarding Checklist). `hr_form_pass(p_kind, p_name)`
  refuses anyone but an admin (`denied`) and a session with no emailed code
  proved in fifteen minutes (`code-needed` with the sign-in address, the
  page sending the code and asking it back), and files each download
  `team.changed` under whom it is about. Drawn in the browser on the
  letterhead and never stored (`tests/hrforms.js`).
