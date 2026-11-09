# Creator payments sheet — setup

When a creator's payment details are approved, the portal adds them as a
row of the finance team's Google Sheet. Each value goes under the header
that names it: Creator ID, Reference, Legal name, NRIC / Passport, Bank,
Account number, Payee, Email, WhatsApp, Submitted, Approved, Approved by and
the rest. A header naming none is left empty. The account and ID numbers go
in whole. Until the secret below is set, approved details wait and nothing
is lost; they are added at the first wake after it is set.

## 1. Database

Applied with the release: `supabase/migrations/2026-11-09-creator-payments-sheet.sql`.

## 2. Google Cloud (once, signed in as adspacestudios@gmail.com)

The portal reuses the OAuth client Google Meet uses
(`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`; see `docs/GOOGLE-MEET-SETUP.md`).

1. console.cloud.google.com → the same project → **APIs & Services →
   Library → Google Sheets API → Enable.**
2. Share the payments spreadsheet with adspacestudios@gmail.com as an
   Editor, if that account does not own it.

## 3. The refresh token (once)

1. Open https://developers.google.com/oauthplayground
2. The gear icon → tick **Use your own OAuth credentials** → paste the
   client ID and secret.
3. In the scope box type `https://www.googleapis.com/auth/spreadsheets`,
   then **Authorize APIs**, and sign in as adspacestudios@gmail.com.
4. **Exchange authorization code for tokens** → copy the **Refresh token**.
5. In Supabase → Edge Functions → Secrets, add
   `GOOGLE_SHEETS_REFRESH_TOKEN` with that value. Never paste it in a chat
   or the repository.

## 4. Settings

Settings → Clients → **Creator payments sheet**: the switch, the sheet's
link and its tab (empty: the first tab). Saving reads the sheet's header row
and says how many columns take a value.
