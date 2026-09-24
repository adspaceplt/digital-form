# Google Meet on the content meeting — setup

The portal books a month's content meeting on the shared ADspace Google
calendar (adspacestudios@gmail.com) and records the Google Meet link on the
month. A slot that already holds an event on that calendar is refused and
named, so two meetings cannot be booked into the same time.

Until the three secrets below are set, **Create Google Meet** answers
"Google Meet is not connected yet. Paste a link instead." and everything
else works: the meeting saves, a pasted link is recorded, and the message to
the client is filled and copied as normal.

Cost: nothing. The Calendar API has no charge at this volume.

## 1. Database

Run in the Supabase SQL editor, after `2026-09-24-the-month-in-two-ticks.sql`:

```
supabase/migrations/2026-09-24-google-meet.sql
```

Safe to run twice.

## 2. Google Cloud (once, signed in as adspacestudios@gmail.com)

1. console.cloud.google.com → the project that holds the OAuth client
   `476859264094-…apps.googleusercontent.com`.
2. **APIs & Services → Library → Google Calendar API → Enable.**
3. **OAuth consent screen**: User type External, app name `ADspace Digital
   Portal`, support email adspacestudios@gmail.com. Add the scope
   `https://www.googleapis.com/auth/calendar.events`. Add
   adspacestudios@gmail.com as a test user, then **Publish app** (a token
   for an app left in Testing expires after 7 days).
4. **Credentials → the OAuth client** (type Web application). Under
   Authorised redirect URIs add `https://developers.google.com/oauthplayground`.
   Copy the **Client secret**.

## 3. The refresh token (once)

1. Open https://developers.google.com/oauthplayground
2. Gear icon (top right) → tick **Use your own OAuth credentials** → paste the
   Client ID and Client secret.
3. Step 1: type `https://www.googleapis.com/auth/calendar.events` in the box →
   **Authorize APIs** → sign in as **adspacestudios@gmail.com** → Allow.
4. Step 2: **Exchange authorization code for tokens** → copy the
   **Refresh token**.

Do not paste the secret or the token into a chat, an email or the repository.

## 4. Supabase secrets and the function

```
supabase secrets set GOOGLE_CLIENT_ID=476859264094-3q0eo2u6ve2s4vl19bv8877co0hg30v0.apps.googleusercontent.com
supabase secrets set GOOGLE_CLIENT_SECRET=<client secret>
supabase secrets set GOOGLE_REFRESH_TOKEN=<refresh token>
supabase functions deploy meet-create
```

Then in the Supabase dashboard: **Edge Functions → meet-create → turn OFF
"Verify JWT"**, as for `sign-upload`. The function asks the database about
the caller itself, and a person who may not work My Work is refused before
Google is asked anything.

## 5. Check

Open a client → Work → a month → **Set meeting**, Where = Google Meet, leave
the calendar tick on, Save. The card shows the `meet.google.com` link and the
event appears on the shared calendar as `{Client} · {Mon YYYY} Content
Discussion`. **Show** under Message to client shows the text to send.

## What it does, and does not do

- Booked from the portal: the event is created on the shared calendar with a
  Meet link. Changing the meeting's date, time or length moves the event.
  Marking the month as having no meeting, or changing Where away from Google
  Meet, takes the event off the calendar.
- Anything already on the shared calendar in that slot refuses the booking,
  whoever put it there. The meeting stays saved in the portal; change the time
  and save again.
- The client is not invited by the calendar. The team sends the message from
  the card, which is what the team does today.
- Rotating the token: set the new `GOOGLE_REFRESH_TOKEN`, confirm a booking,
  then revoke the old grant at myaccount.google.com → Security → Third-party
  access.
