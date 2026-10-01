# Draft with AI — setup

Draft with AI, on a report's Commentary step, asks the `report-draft` edge
function to write the four commentary fields from the report's own figures.
The team reads and edits the draft, and nothing is saved until Save.

## What leaves the portal

The report's figures (the period, the account totals, the previous period
and each ad's or post's numbers, ad names without the creator code), the
Notes for the draft the colleague typed, and the commentary of the client's
last finished report so the draft can follow up on it. The client's name is
replaced by "the brand" wherever the team's words carry it. No contact,
handle, billing detail or image is sent. The draft comes back as text and is
not stored by the function; the notes are kept only in the colleague's
browser.

## Notes for the draft

The figures cannot say why spend moved, which ads were paused, that a lead
form changed, what the client's goal is or what next month's budget will be.
Write those in Notes for the draft, one fact a line, before pressing Draft
with AI. The draft states a reason or a plan only when the notes give it.

## Limits

The database counts every press: 5 drafts a report, 20 a colleague and 60 the
whole team in any 24 hours. A draft that failed is not counted. When a limit
is reached the page says which one and when the next draft is free. The
numbers are in `ai_draft_claim` (`supabase/migrations/2026-10-01-draft-with-ai-limits.sql`).
For a hard ceiling on cost, also set a monthly spend limit in the Claude
Console (Settings, Limits).

## One-time setup (the account owner)

1. At console.anthropic.com, open **Billing** and add credits (the API is
   billed separately from a Claude.ai plan). Turn **Auto reload** off or set
   a monthly limit.
2. Open **API keys** and create a key named `adspace-portal-report-draft`.
   Copy it once; never paste it into a chat, an email or the repository.
3. In the Supabase dashboard, project `hwwuigvdfubuymchsvyx`, open **Edge
   Functions → Secrets** and add:
   - `ANTHROPIC_API_KEY`: the key from step 2;
   - `REPORT_DRAFT_MODEL`: the model id given in the setup message.
4. Press **Draft with AI** on any draft report's Commentary step.

Until both secrets are set, the button answers "Draft with AI needs its key
in Supabase." A refused key reads "The AI key was refused. Check it in
Supabase."

## Deploy

`report-draft` is deployed from `supabase/functions/report-draft/` with
**Verify JWT off**, like `meet-create`: the function checks the caller
itself (Reports at Work, the report still a draft) under the caller's own
access.
