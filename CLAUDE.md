# Working rules for this repository

## Copy
- No explanatory copy. Do not add hints, blurbs, notices or empty states that
  explain what a section is for, how the data model works, or why a rule
  exists. The heading and the controls are the explanation.
- Where a line is unavoidable (a format the person must follow, a destructive
  consequence), one short neutral sentence. Corporate register. No "we", no
  "you should", no examples in placeholders.
- Client-facing pages (creators/, review/) are held to this most strictly, in
  English and Chinese alike.
- Dialogs and messages state the action and its consequence only.

## Design
- Consistent control heights (`--ctl-h`), flat surfaces, Apple/Cloudflare
  register. Mobile first: 44px targets, 16px field text on coarse pointers, no
  horizontal overflow.
- Header and footer come from `js/chrome.js`; new pages use
  `docs/PAGE-TEMPLATE.html`.

## Data
- Currency follows the client (`market` MY/SG); tax is Malaysian SST 8% for
  everyone unless `sst_applies` is false.
- Access is enforced by the database (`team_members`, `me()`, `allowed()`);
  the console only hides what would be refused.
- A policy on `team_members` must not query `team_members` directly; go
  through `allowed()`.
