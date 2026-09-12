# Test suite

Playwright headless suites against a local static server with a Supabase
stand-in (`stub2.js`). Run from the repo root. See CLAUDE.md, section 1,
for the order that has to run before a push.

    setsid nohup npx --yes http-server -p 8899 -s . >/dev/null 2>&1 &
    for s in run camp client cprod bar newbadge prod qr regress backup keyin state race chrome crm sgd team; do node tests/$s.js tests; done
    node tests/uxaudit.js tests
    SHOTS=1 node tests/uxaudit.js tests       # screenshots only, into tests/walk/
    node tests/newshot.js tests               # client record, billing fold, rate card at 1280 and 390
    (cd tests/pdfx && npm i) && node tests/pdfreal.js tests   # a real PDF with pdf-lib

Playwright and Chromium paths are the sandbox's (`/opt/node22/lib/node_modules/playwright`,
`/opt/pw-browsers/chromium-1194/chrome-linux/chrome`); change the two constants at the
top of each file elsewhere.
