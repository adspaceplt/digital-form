# Performance reviews: setup

Six steps, in order. Nothing here needs a deploy beyond the site itself.

## 1. Run the two migrations

In the Supabase SQL editor, **New query**, paste the whole file (open it on
GitHub, press **Raw**, select all), click once so nothing is highlighted, and
**Run**. The editor runs only highlighted text, so a partial selection ends
in `syntax error at end of input`.

1. `supabase/migrations/2026-09-24-performance-reviews.sql`: the record, row
   level security on with no policy on every table, the browser granted only
   the functions.
2. `supabase/migrations/2026-09-24-performance-email-code.sql`: the email-code
   lock a member may put on their own reviews (step 6).

Both are safe to run twice.

## 2. Set the master code

In the same editor, and nowhere else (never in a chat, a ticket or the
repository):

```sql
select public.perf_code_reset('your code here');
```

The code is stored as a bcrypt hash. Changing it later ends every open
unlock. An unlock lasts 15 minutes from its last use; five wrong tries lock
that person out for 15 minutes.

## 3. Grant management access

Team, then the user group, then **Team → Performance reviews**:

| Level | What it allows |
|---|---|
| No access | Nothing (the default; this part is never inherited from Team) |
| View | Read the month's reviews and print them, with the master code |
| Work | Score, log breaches, release, answer disputes, finalise |
| Manage | Also reopen a finalised record as its next version |

An admin has every level and still needs the master code.

## 4. Set each person up

- **Employee ID** on the Team page. The printed reference is
  `ADHR/{Employee ID}/PR{YYMM}`, so a month cannot be released without one.
- **Review profile** from the person's ⋯ on Team → Performance: department,
  role standard, whether they run client ads (budget pacing counts only for
  them), and whether they are reviewed at all.

## 5. Everybody signs in as themselves

A member reads their own released months under **My performance** in the
account menu. That works only when each person signs in with their own
account; a shared login would show one person's record to whoever holds it.

## 6. The email-code lock (each person's own choice)

Under **My performance** a member may tick **Ask for an email code before
showing my reviews**. From then on their reviews open only after they enter a
6-digit code emailed to them, good for 15 minutes; turning it off needs a
code too. The database checks the signed session, so the page cannot be
talked round it.

The code is Supabase's own sign-in email, so its template must print it,
once: **Authentication → Emails → Magic Link**, add a line such as

```
Your code: {{ .Token }}
```

and Save. The link already in that email keeps working for the client portal.
Until the line is added the email arrives with a link and no code.

Supabase's built-in email sender allows only a few emails an hour across the
whole project. If codes stop arriving, set up your own SMTP under
**Authentication → Emails → SMTP Settings** (the same place the client portal's
sign-in emails come from).

## The monthly round

1. Management scores the month and logs any breach (Team → Performance).
2. At the 1-1, management releases it. The member is told on the bell.
3. The member has 3 days to dispute, item by item, with a reason.
4. Management answers each item with a reason; the score updates where upheld.
5. The member acknowledges; management finalises and prints the record.
