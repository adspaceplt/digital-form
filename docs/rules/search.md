<!-- triggers: js/search.js -->
# Console search (`js/search.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- One control in the console head (`#searchOpen`, before the bell and the
  account);
  Cmd/Ctrl + K opens it anywhere, `/` only when no field has the caret.
  Neither takes over another open sheet or the confirm bar.
- The panel is a sheet through `js/sheet.js` (`#searchSheet`): under the head
  at a desk, a card above the tab bar the screen's height on a phone. The field is a
  combobox: the arrows move `aria-activedescendant`, Enter opens, Escape
  closes and focus returns to what opened it. Typing marks the sheet clean.
- It asks only the sections `may()` grants, each its own table through
  `js/api.js` under RLS; no schema. `ilike` inside `or()` with the value
  double quoted; `"`, `\`, `%` and `*` are dropped from what is typed.
- Five rows a section, 200ms after the last key, two characters at least; a
  sequence number throws away a late answer to an older query.
- A refused read drops its section only. Every read refused is `failLine`
  with Try again, never No matches.
- Groups run in the rail's order (Creators List after Creator Campaigns; Suppliers by name or Supplier ID from `suppliers_list`, opening `supplier=`; the Handbook's live files by title, opening it filtered; a colleague opens their record, `member=`; `_` is escaped, never a wildcard; 2026-10-22; Settings last, a row by its name or its group's from the page's own list (`ADspaceSettings.rows`), opening its group with its control focused, no read; 2026-10-27, SET-9);
  Video Scripts by code or title, opening its record (`script=`); Reports
  by title or white-label brand, opening the report (`report=`). Content
  Review, Video Scripts, Creator Campaigns and Reports also find a record
  by its client's name or code (the user, 2026-10-14: "AC182 … only shows
  me client directory"): the clients matching the query are read once a
  query (`clientRows`, which the Clients group draws from too) and join
  each section's filter as `client_id.eq` terms. What was
  said is found too (2026-10-11): a task by its brief (`Brief: …`) or a
  remark as it reads now (`Remark: …`; an edited one by its latest words, a
  removed one never), and Calls and visits (`clients.calls`) by its notes,
  next action or who it was with, under its client, opening `tab=calls`.
  Each group's label leads with its rail glyph (`ADspaceAdmin.glyph`).
  A row is the name, its code in the token face, one mute line; the match
  in weight, never colour. No recent searches, no explanatory copy.
- A result writes the record's address first, then `show()` (a content set
  through `ADspaceAdmin.restore()`). Letters of Offer open the client's
  Documents tab. The Creators List, Documents, Short Links, Services and
  Team open filtered by their own search field, its bar opened.
- A task number is read from `#WT01008`, `WT1008` or `1008` (`task_no.eq`),
  since `ilike` cannot compare a number.
