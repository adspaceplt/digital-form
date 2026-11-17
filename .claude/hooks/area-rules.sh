#!/bin/bash
# On the first edit of a path an area names (docs/rules/*.md, its
# "triggers" line), hand the session that area's rules file, once a session.
input=$(cat)
dir="${CLAUDE_PROJECT_DIR:-/home/user/digital-form}"
printf '%s' "$input" | DIR="$dir" node -e '
const fs = require("fs"), path = require("path");
let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
  let j; try { j = JSON.parse(s); } catch (e) { return; }
  const f = (j.tool_input || {}).file_path || "";
  const dir = process.env.DIR, rel = path.relative(dir, f);
  if (!rel || rel.startsWith("..")) return;
  const rules = path.join(dir, "docs/rules");
  let hit = [];
  for (const n of fs.existsSync(rules) ? fs.readdirSync(rules) : []) {
    const m = fs.readFileSync(path.join(rules, n), "utf8").match(/^<!-- triggers: (.*) -->/);
    if (m && m[1].split(" ").some(t => rel === t || rel.startsWith(t.replace(/\/?$/, "/")) || (t.endsWith("/") && rel.startsWith(t)))) hit.push(n);
  }
  const mark = "/tmp/area-rules-" + (j.session_id || "x");
  const seen = fs.existsSync(mark) ? fs.readFileSync(mark, "utf8").split("\n") : [];
  hit = hit.filter(n => !seen.includes(n));
  if (!hit.length) return;
  fs.appendFileSync(mark, hit.join("\n") + "\n");
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PostToolUse",
    additionalContext: rel + " is in an area with its own rules: read " + hit.map(n => "docs/rules/" + n).join(", ") + " whole before going further (CLAUDE.md, Area rules)." } }));
});'
exit 0
