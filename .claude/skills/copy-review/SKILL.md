---
name: copy-review
description: Have every new word a change puts in front of a person (a label, button, menu item, message, refusal, empty line, cover, email, WhatsApp template, PDF line) read by a second reader against DESIGN.md §6 before the change merges, then fix what it finds. Run on every release that adds or changes words, before the PR is merged, or when the user types /copy-review.
argument-hint: "[base, default origin/main]"
---

# Copy review before merge

Why it exists (the user, 2026-11-04: "every new build didnt follow your tone
etc. rules and why is it this case"): the session that writes a line reads
it as right, and `tests/words.js` stops only phrases already rejected. A
reader who did not write the words, given the rules and nothing else,
catches what the writer cannot see.

## Steps

1. Commit the change, then list its new words:
   `node tests/copyscan.js [base] > /tmp/copyscan.txt`
   (base defaults to `origin/main`). Nothing listed: say so in the PR's
   Test plan ("Copy review: no new words") and stop.
2. Hand the list to a fresh reviewer with the Agent tool
   (`subagent_type: general-purpose`), never one that saw the change being
   built. Give it this brief and nothing about why the words were chosen:

   > You review the words a web portal shows its users. Read
   > `/home/user/digital-form/DESIGN.md` §6 (Copy, including "How copy is
   > drafted") and `tests/words.js`'s RETIRED and PATTERNS lists. Then read
   > `/tmp/copyscan.txt`: each line is `file:line  text`, the new words of
   > one change. Skip what is plainly code, a log line or a type
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
   > use where a client reads, a missing 中文 for a client line. For each:
   > `file:line`, the words, the rule it breaks, and the words to use.
   > Report only real breaks; say "No findings." when there are none.

3. Fix every finding it reports, or answer it in the PR with why it stays.
   A phrase it rejected joins `tests/words.js` RETIRED, a kind of wording
   joins PATTERNS, and a line two screens say joins `ADspaceWords.line`
   (`js/words.js`), in the same push.
4. Run `node tests/words.js tests` and the suites that read the changed
   words, then merge. The PR's Test plan names the review: "Copy review:
   n strings read, n fixed".
