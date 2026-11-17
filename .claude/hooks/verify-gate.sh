#!/bin/bash
# Before a portal PR merges: the suites its diff reaches passed on this commit
# (node tests/affected.js --run writes /tmp/affected-pass/{commit}).
# Mode in .claude/hooks/verify-gate.mode: off, observe (log what would have
# been held), enforce (hold it). A merge whose commit message carries
# "Verify: skipped" and a reason goes through and is logged; after two holds
# in one session the next merge goes through, so a session never sticks.
input=$(cat)
dir="${CLAUDE_PROJECT_DIR:-/home/user/digital-form}"
mode=$(cat "$dir/.claude/hooks/verify-gate.mode" 2>/dev/null || echo observe)
[ "$mode" = off ] && exit 0
repo=$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);process.stdout.write((j.tool_input||{}).repo||"")}catch(e){}})')
[ "$repo" = digital-form ] || exit 0
msg=$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);process.stdout.write((j.tool_input||{}).commit_message||"")}catch(e){}})')
sid=$(printf '%s' "$input" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).session_id||"x")}catch(e){process.stdout.write("x")}})')
head=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
log=/tmp/verify-gate.log
stamp="$(date -u +%FT%TZ) $mode $head"
if [ -n "$head" ] && [ -f "/tmp/affected-pass/$head" ]; then echo "$stamp passed" >> $log; exit 0; fi
if printf '%s' "$msg" | grep -q 'Verify: skipped'; then echo "$stamp skipped: $(printf '%s' "$msg" | grep -o 'Verify: skipped.*' | head -1)" >> $log; exit 0; fi
reason="The suites this change reaches have not passed on ${head:0:7}. Run: node tests/affected.js --run (or put 'Verify: skipped, {reason}' in the merge message)."
if [ "$mode" = enforce ]; then
  held=$(grep -c "^held $sid" /tmp/verify-gate.holds 2>/dev/null || echo 0)
  if [ "$held" -lt 2 ]; then echo "held $sid" >> /tmp/verify-gate.holds; echo "$stamp held" >> $log; echo "$reason" >&2; exit 2; fi
  echo "$stamp let through after two holds" >> $log; exit 0
fi
echo "$stamp would hold" >> $log
printf '{"systemMessage": %s}\n' "$(printf '%s' "Verify gate (observe): $reason" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(s)))')"
exit 0
