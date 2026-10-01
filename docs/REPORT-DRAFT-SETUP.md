# Draft with AI — setup

Draft with AI, on a report's Commentary step, asks the `report-draft` edge
function to write the four commentary fields from the report's own figures.
The team reads and edits the draft, and nothing is saved until Save.

## What leaves the portal

Only the report's figures: the period, the account totals, the previous
period and each ad's or post's numbers (ad names without the creator code).
No client name, contact, note, handle or image is sent. The draft comes back
as text and is not stored by the function.

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
