# Performance reviews: setup

Five steps, in order. Nothing here needs a deploy beyond the site itself.

## 1. Run the migration

In the Supabase SQL editor, run
`supabase/migrations/2026-09-24-performance-reviews.sql`. It is safe to run
twice. It creates the record, turns row level security on with no policy on
every table, and grants the browser only the functions.

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

## The monthly round

1. Management scores the month and logs any breach (Team → Performance).
2. At the 1-1, management releases it. The member is told on the bell.
3. The member has 3 days to dispute, item by item, with a reason.
4. Management answers each item with a reason; the score updates where upheld.
5. The member acknowledges; management finalises and prints the record.
