<!-- triggers: js/feedback.js js/fbform.js feedback/ -->
# Client feedback (`feedback/`, `js/feedback.js`, `js/fbform.js`)

Rules for this area (CLIENT FEEDBACK, 2026-11-24; the user approved the
mockups as version 3, "go feedback"). One place per fact, as CLAUDE.md §0.

- Two forms, fixed in the database (`feedback_questions`, English and
  Chinese): the Service rating (`quick`; never "monthly", the user,
  2026-11-24: "dont make it monthly recurring") and the Performance review
  (`review`, the recommendation 0 to 10 first). Each scale names its own two
  ends. `{name}` is the account manager: the client's Person in charge when
  the request was sent, stored on the request; a client with none is not
  asked about one. No page types a question, a scale or a band.
- A request exists only when a colleague sends one (Clients at Work, the
  client active or paused and in scope), by email to the client's primary
  contact alone; never on a schedule, never by itself, never on WhatsApp
  (the user, 2026-11-24). A new request of the same form closes the open one
  (`replaced`); another form stands beside it.
- Request feedback is the Feedback part's head act, and the client record's
  ⋯ on every other tab (Clients at Work, Send email
  for this colleague, a client never a lead): it asks the form (a segment),
  then `supplier-mail` `{ feedback: true }` makes the request
  (`feedback_mail_begin`, refused `send-off` or `email-off` before anything
  is made), emails its words in the primary contact's language with the link
  as its one button, and closes it (`feedback_mail_done`); a failed send
  withdraws the request. The WhatsApp feedback template is no longer offered
  from the record.
- The record's Feedback part (Interactions' second, under Calls and visits;
  `tab=feedback` opens it there) lists every request newest first:
  Sent, Opened, Answered, Follow-up open (a low score whose task is not done),
  Withdrawn or Closed; a row opens its answers read only, and a low one
  offers Create follow-up task (My Work at Work), linked by
  `feedback_followup`. Its rows are the phone row on a narrow pane.
- Settings, Clients: Client feedback holds `feedback_quiet_months` (1 to
  24), the months since a client was last asked before the Dashboard counts it.
- One answer a request, whoever answers first (the link or a signed-in
  contact); the request then reads Already submitted to everyone. The link
  (`/feedback/?k=`, 16 characters) answers that one request alone and names
  no contact, email or other client. No identity fields: the link is the
  client; a signed-in contact of that client is recorded by the database.
- The public path is counted a caller's address an hour (`feedback_hits`:
  120 calls, 20 unknown keys), answered `busy`, read as Unable to load.
- The lead score's band chooses the note asked (low, mid, high); the page
  shows it once the lead is answered and the database keeps only that one.
- /client/: Rate your experience is the Overview's first card only while a
  request is open (the lead question, the rest under it once a score is
  chosen); the Feedback tab holds past answers, read only, once there is one.
- An account manager's own score is read by the colleague, a colleague of the
  group theirs reports to (`team_roles.reports_to`), Clients at Manage and an
  admin (`feedback_sees_manager`); anyone else reads the answer without it.
- A low score (the lead in its low band) tells the account manager (else the
  sender) on the bell, `client.feedback`, opening the client; its follow-up
  is a My Work task linked by `feedback_followup`, the score open until that
  task is done.
- The figures (`feedback_figures(p_from, p_to)`, one read a span, at
  Clients Full Access; nothing is drawn or read below it): the Dashboard's
  Team tab, Client feedback after Sales (`#ovwFb`, the lead row's tiles,
  three across, one over the other when narrow): Service rating (the mean
  of the Service rating's lead, `4.0 of 10`), Net Promoter Score (promoters
  less detractors over the Performance reviews answered), each with its
  answers and its change on the period before, and Open low scores (red
  with the oldest's date, whatever the period); under them, only while any,
  `N active clients have not been asked for feedback in M months.` (the
  Business setting). Analytics' Clients tab, This week: Client feedback by
  person in charge (the account manager named on each request when sent):
  Requested, Answered, Service rating, NPS and Account manager score (the
  manager's own score, a dash where `feedback_sees_manager` withholds it);
  on a narrow pane the two counts give way.
- `tests/feedbacksql.js` holds the database, `tests/feedbackui.js` the record's tab, Request feedback and the figures; the walk seeds Laman Citra's
  Service rating open (`fbwalkopen234567`), its Performance review answered
  and an earlier low Service rating.

## Components

- A score asked of a client is `.rate` (`js/fbform.js`): a radio group of
  numbered options (`.rate-opt`, tonal, `--tap` high, the small corner, the
  chosen the ink fill), ten across at a desk, two rows of five (six for 0 to
  10) on a phone, the arrows moving along it; its two ends named under it
  (`.rate-ends`, 12.5px mute, `1 · Very poor`). Each question is a `.fbq`
  (16/600, its number mute, Optional mute after an optional one), a
  `--line-soft` hairline and 24px between. A past answer reads as `.fbread`
  (the question 13px mute over the score at 500 and its scale).
