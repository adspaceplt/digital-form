#!/bin/bash
# Readies a cloud session for the gate (CLAUDE.md §1): the private suites
# cloned beside the portal and linked as tests/, and the PDF libraries the
# suites draw with installed. Safe to run again: an existing clone is only
# fast-forwarded while it is clean on main, and the PDF libraries are
# installed again only when their lock file changed.
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

REPO="${CLAUDE_PROJECT_DIR:-/home/user/digital-form}"
TESTS="$(dirname "$REPO")/digital-form-tests"
URL="https://github.com/adspaceplt/digital-form-tests"
warn() { echo "session-start: $*" >&2; }

# 1. The suites (a private repository: the session needs GitHub access to it).
if [ ! -d "$TESTS/.git" ]; then
  if ! git clone -q "$URL" "$TESTS"; then
    warn "could not clone $URL. Check the GitHub connector's access to adspaceplt/digital-form-tests."
    exit 0
  fi
elif [ -z "$(git -C "$TESTS" status --porcelain)" ] && [ "$(git -C "$TESTS" branch --show-current)" = "main" ]; then
  git -C "$TESTS" pull -q --ff-only origin main || warn "could not update $TESTS; it keeps its current commit."
fi

# 2. tests/ is a link to the clone, never a folder of its own (.gitignore).
if [ -e "$REPO/tests" ] && [ ! -L "$REPO/tests" ]; then
  warn "$REPO/tests is a real folder, not a link; left alone."
else
  ln -sfn "$TESTS" "$REPO/tests"
fi

# 3. pdf-lib, fontkit and pdfjs-dist, exactly as the lock file names them.
PDFX="$TESTS/pdfx"
STAMP="$PDFX/node_modules/.lock-sha256"
SHA="$(sha256sum "$PDFX/package-lock.json" | cut -d' ' -f1)"
if [ "$(cat "$STAMP" 2>/dev/null)" != "$SHA" ]; then
  if npm ci --prefix "$PDFX" --no-audit --no-fund --loglevel=silent >/dev/null; then
    echo "$SHA" > "$STAMP"
  else
    # A lock out of step with package.json (an older commit of the suites):
    # install from package.json without writing the lock, and say so.
    warn "npm ci refused tests/pdfx/package-lock.json; installed from package.json instead. Commit a lock that matches it."
    npm install --prefix "$PDFX" --no-package-lock --no-audit --no-fund --loglevel=error >/dev/null
  fi
fi

# 4. What the suites expect the image to hold.
[ -x /usr/lib/postgresql/16/bin/initdb ] || warn "Postgres 16 is not at /usr/lib/postgresql/16/bin: the database suites will skip."
[ -d /opt/node22/lib/node_modules/playwright ] || warn "Playwright is not at /opt/node22/lib/node_modules/playwright: the browser suites cannot start."

echo "Tests ready: digital-form-tests $(git -C "$TESTS" rev-parse --short HEAD) linked as tests/, PDF libraries installed."
