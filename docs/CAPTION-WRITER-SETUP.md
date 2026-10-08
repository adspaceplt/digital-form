# Write caption — setup

Write caption, under a post's caption fields in Content Review (Add assets and
a saved post's Edit), asks the `caption-draft` edge function to write the
post's caption, and its Chinese where asked. The words go into the fields;
nothing is saved until the post's own Save (Add to set for a new asset), and
Undo puts the earlier words back.

## What leaves the portal

The platform and format, the set's title and the post's title, the Notes for
the caption the colleague typed, the client's industry and market (Malaysia or
Singapore), and the languages asked for. The client's name is replaced by
`{brand}` and each handle by `{handle}`; the page fills them back in. No
image, file, contact or billing detail is sent. The function stores nothing
but the count and the call's tokens; the notes stay in the colleague's
browser.

## XHS Safe Mode

Offered only on a rednote post and off until the colleague ticks it. Ticked,
the caption keeps to rednote's content rules: no absolute claims, authority
endorsements, clickbait, panic urgency, medical or beauty claims, superstition,
diversion to other platforms, vulgarity, flaunting wealth, cyberbullying or
over-retouching language.

## Limits and cost

The database counts every press before Claude is asked: 20 captions a
colleague and 40 an admin a day, reset at midnight Malaysia time, apart from
the reports' AI uses. Both are settings on Reports → ⋯ → AI usage → Edit
limits. Every call's tokens are kept, and the same page shows this month's
estimated cost in US$ at the prices set under Edit prices (Business settings:
4 in and 20 out a million tokens from 8 Oct 2026). For a hard ceiling, also
set a monthly spend limit in the Claude Console (Settings, Limits).

## One-time setup (the account owner)

1. The key is the one Draft with AI uses: `ANTHROPIC_API_KEY` in Supabase,
   project `hwwuigvdfubuymchsvyx`, **Edge Functions → Secrets**
   (`docs/REPORT-DRAFT-SETUP.md`). Nothing new to create.
2. Optional: add `CAPTION_MODEL` in the same place to choose the model. Unset,
   the function uses `claude-opus-5-5`. If you change the model, change the
   prices under AI usage → Edit prices to match its price list.

Until the key is set, Write caption answers "AI needs its key in Supabase."

## Deploy

`caption-draft` is deployed from `supabase/functions/caption-draft/` with
**Verify JWT off**, like `report-draft`: the browser's preflight carries no
Authorization header, and the function checks the caller itself (Content
Review: Sets at Work, a set on a client they see) under the caller's own
access.
