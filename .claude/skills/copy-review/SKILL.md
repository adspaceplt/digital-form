---
name: copy-review
description: Have every word on every screen or PDF a change touches (a label, button, menu item, message, refusal, empty line, cover, email, WhatsApp template, PDF line), the standing words as well as the new, read by a second reader against DESIGN.md §6 once, before the change merges, then fix what it finds. Run on every release that touches a screen, before its merge, or when the user types /copy-review. Never a scan of the whole repo.
argument-hint: "[base, default origin/main]"
---

# Copy review before merge

Why it exists (the user, 2026-11-04: "every new build didnt follow your tone
etc. rules and why is it this case"): the session that writes a line reads
it as right, and `tests/words.js` stops only phrases already rejected. A
reader who did not write the words, given the rules and nothing else,
catches what the writer cannot see.

Why it reads the whole screen (the user, 2026-11-25: "Please do not give
me weird naming again. Can you sweep before push or merge?"): Build
quote's "View lines" stood on a screen two releases reworked, and was never
read again, because the review listed only the lines a change added. A
label already standing on a screen the change touches is read again with
the new ones.

## Steps

1. Commit the change, then list every word on the screens it touches:
   `node tests/copyscan.js [base] > /tmp/copyscan.txt`
   (base defaults to `origin/main`): each changed page, script, function
   and migration read whole, `admin/index.html` the region round each
   change, the change's own lines marked `+`. Nothing listed (a change to
   no screen): say so in the PR's Test plan ("Copy review: no screen
   touched") and stop. It runs once a change, before its merge, on the
   screens that change touches; never the whole repo (the user,
   2026-11-25: "stricter tone checks only apply for new build, and do a
   checks before merging right, not every time run the whole repo
   checks").
2. Hand the list to a fresh reviewer with the Agent tool
   (`subagent_type: general-purpose`), never one that saw the change being
   built. Give it this brief and nothing about why the words were chosen:

   > You review the words a web portal shows its users. Read
   > `/home/user/digital-form/docs/rules/copy.md` (DESIGN.md §6: Copy, including "How copy is
   > drafted") and `tests/words.js`'s RETIRED and PATTERNS lists. Then read
   > `/tmp/copyscan.txt`: each line is `file:line  text`, every word on
   > the screens one change touches; a line marked `+` is new, the rest
   > were already standing and are read just as closely. Skip what is plainly code, a log line or a type
   > signature; for each file you may open the line to see whether the
   > reader is a colleague (the console: `js/*.js` other than the client
   > pages' scripts, `admin/`) or a client, prospect, creator or supplier
   > (client pages, `quote/`, `details/`, `supplier/`, emails, PDFs,
   > WhatsApp templates in migrations and edge functions). Report every
   > line that breaks §6: a system word (record, row, held, cleared,
   > payload, scope, log, a key or column), a fragment that is not a fact
   > or a sentence, a refusal that does not say what to do next, the
   > present tense for a step the reader waits on, a long phrase where a
   > familiar app uses one word, a new word for a thing that already has
   > one (grep `js/words.js` and the screen it joins), a line said twice,
   > an explanatory line, wording a Malaysian business letter would not
   > use where a client reads, a missing 中文 for a client line. Ask one
   > more question of every label, button and menu item: would a colleague
   > or client who has never seen this portal understand it at once, as a
   > word a familiar app (Apple, Google, a bank) uses? A term only the
   > builder knows (lines, board, fold, pane, block, basket, row, slot) is
   > a finding. For each:
   > `file:line`, the words, the rule it breaks, and the words to use.
   > Report only real breaks; say "No findings." when there are none.

3. Fix every finding it reports, or answer it in the PR with why it stays.
   A phrase it rejected joins `tests/words.js` RETIRED, a kind of wording
   joins PATTERNS, and a line two screens say joins `ADspaceWords.line`
   (`js/words.js`), in the same push.
4. Run `node tests/words.js tests` and the suites that read the changed
   words, then merge. The PR's Test
   plan names the review: "Copy review: n strings on n touched files read,
   n fixed".
