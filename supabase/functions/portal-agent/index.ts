/*
 * portal-agent — the console's Assistant (2026-11-13; the user: "ok approve,
 * all colleagues, build all phases").
 *
 * A colleague asks in words from the Ask panel (js/agent.js). The page holds
 * the conversation and posts it whole each time; this function asks Claude
 * with a fixed set of tools and hands back Claude's answer. It runs no tool
 * itself: every tool Claude asks for is run by the page through the
 * colleague's own sign-in (the same reads the screens make, under the same
 * policies), and a tool that would change something only proposes it; the
 * page shows it as a card and nothing is written until the colleague's
 * Confirm, through the function the screen uses.
 *
 * Every question is counted by the database before Claude is asked
 * (`ai_agent_claim`, any active colleague); each later step of the same
 * question names its press (`ai_agent_turn`: the caller's own, under half
 * an hour, twelve steps at most); each step's tokens are added
 * (`ai_agent_tokens`) and the question marked done or failed
 * (`ai_draft_done`).
 *
 * What Claude reads is what the colleague may read. A client's name and its
 * work go to Claude (the user approved it for the assistant, 2026-11-13); a
 * contact's email or number never does: the page's tools leave them out,
 * and an email or number typed into a question is masked here.
 *
 * Secrets: ANTHROPIC_API_KEY, AGENT_MODEL (unset, claude-opus-5-5), plus
 * the platform's SUPABASE_URL and SUPABASE_ANON_KEY. Deploy with Verify JWT
 * off, as every console function.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import Anthropic from 'npm:@anthropic-ai/sdk';
import { cors, json } from '../_shared/cors.ts';

/* The answer once ready, the connection held open by a space every few
   seconds meanwhile (JSON allows leading whitespace). */
function held(work: Promise<unknown>, origin: string | null) {
  const enc = new TextEncoder();
  const stream = new ReadableStream({
    start(ctl) {
      const tick = setInterval(() => { try { ctl.enqueue(enc.encode(' ')); } catch { /* closed */ } }, 8000);
      work.then((b) => b, (e) => { console.error('portal-agent: failed', String((e as Error)?.message || e)); return { error: 'ai-failed' }; })
        .then((b) => { clearInterval(tick); ctl.enqueue(enc.encode(JSON.stringify(b))); ctl.close(); });
    }
  });
  return new Response(stream, { status: 200, headers: { 'Content-Type': 'application/json', ...cors(origin) } });
}
function secret(name: string): string { return (Deno.env.get(name) ?? '').trim(); }
/* An email or a number typed into a question: a number is nine digits or
   more, or a Singapore number's 4 and 4; a date (8 digits) is left alone. */
const scrub = (s: string) => s
  .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, '[email]')
  .replace(/\+?\d(?:[\s-]?\d){8,14}/g, '[number]')
  .replace(/\b[3689]\d{3}[\s-]?\d{4}\b/g, '[number]');

/* ---- What Claude is told ------------------------------------------------- */
const SYSTEM = `You are the Assistant inside the ADspace Digital Portal, the internal console of ADspace, a digital marketing agency in Johor Bahru serving clients in Malaysia and Singapore. A colleague asks you, in words, about their work and asks you to do small pieces of it. You answer from the portal's own records and prepare changes for the colleague to confirm.

HOW YOU WORK
Read before you answer. Use the tools to find the client, the task, the report or the colleague the question is about; never guess an id, a name, a date or a figure. When a name could match more than one record, say which ones and ask which is meant. A tool answers only what this colleague may see; when it answers no-access, say plainly that the colleague does not have access, and stop.

CHANGES
You never change anything yourself. Every change is a propose_ tool: the colleague sees it as a card and decides. Prepare one change at a time, with every field filled from what you read or what the colleague said; ask for anything you cannot fill. Two changes asked for at once are two cards, each confirmed on its own. After proposing, say nothing more about it: the card speaks for itself. When the conversation says a change was confirmed, it is done; when it says cancelled, it was not made.
What you may propose: a task added, reassigned or given a new Due date, a remark, a call or visit logged, a report marked as sent, a client month's meeting booked (Google Meet by default; read client_months first, a meeting goes on a month the client has), a creator campaign created as a draft, a content set published or unpublished (read list_sets first), a WhatsApp template sent to a client's contact (read find_contacts first; an approval reminder names the set or booking that waits), and any of these scheduled for later with propose_schedule, except a Google Meet booking, which is booked at once. A reminder for later is propose_schedule with kind reminder; it goes to the colleague asking. A schedule may run only if a condition still holds (the set still has posts the client has not decided, the report is not marked as sent, the task is not finished); use one when the colleague says so ("if it is still waiting").
You do not delete anything, send anything to a creator or supplier, write an email, or touch money, billing, invoices, quotations, access or performance records. When asked, say that it is done on its own screen and offer to open it with open_page.

WRITING FOR THE COLLEAGUE
Captions, video scripts, checklists and report commentary are written on their own screens with Write with AI, which follows the house style and asks the colleague to declare they read it: offer open_page to the record instead of writing them here. You may draft a short message the colleague will send themselves (a WhatsApp follow-up to a client, a reminder to a colleague), in formal Malaysian business English, as a letter here is written.

ANSWERS
Short and plain, in the colleague's working words: Client, Lead, Person in charge, Sales by, Due date, Draft due, Post date, Assigned to. Lists as short lines, the most urgent first. Dates as 12 Sept 2026, times as 2:00pm, Malaysia time. Never a database word (row, id, table, payload, status key). No dashes as punctuation. Answer in the language the colleague writes in. Today is given at the end of the conversation's first message.

THE PORTAL
My Work holds tasks (a code like 2611W204 and a number like #WT01008), each Assigned to one colleague, with a Due date, a stage and a priority (Urgent, High, Medium, Normal), and each client's content months (Nov 2026), each with its meeting. Clients move Lead, Contacted, Proposal sent, Active, Paused, Past; each has a Person in charge and Sales by. Calls and visits are logged on the client. Content Review holds a client's content sets, Draft or Published, whose posts the client approves or asks changes to. Creator Campaigns are Draft, Open for selection, In production, Completed. Reports are Accounts Reports and Advertising Reports for a month, Draft, In review, Confirmed, Published, and marked as sent to the client.`;

/* ---- The tools: the page runs every one ----------------------------------- */
const str = { type: 'string' };
const opt = { type: ['string', 'null'] };
const day = { type: 'string', description: 'A date as YYYY-MM-DD, Malaysia time.' };
const optDay = { type: ['string', 'null'], description: 'A date as YYYY-MM-DD, Malaysia time, or null.' };
function tool(name: string, description: string, props: Record<string, unknown>) {
  return { name, description, strict: true,
    input_schema: { type: 'object', additionalProperties: false, required: Object.keys(props), properties: props } };
}
const TOOLS = [
  tool('find_clients', 'Find clients and leads by name or Client ID. Returns each with its stage, Person in charge and Sales by.',
    { query: str }),
  tool('client_summary', 'One client: its stage and since when, Person in charge, Sales by, industry, market, next action, open tasks, the last calls and visits, and reports this quarter.',
    { client_id: str }),
  tool('list_tasks', 'Tasks in My Work. whose: me, everyone (needs the whole team view), or person (with person_id). show: open, past_due (open with a due date passed), due_this_week, done_this_month.',
    { whose: { type: 'string', enum: ['me', 'everyone', 'person'] }, person_id: opt, client_id: opt,
      show: { type: 'string', enum: ['open', 'past_due', 'due_this_week', 'done_this_month'] } }),
  tool('waiting_on_me', 'What waits on this colleague\'s decision: extension requests asked of them, reports they review.', {}),
  tool('list_reports', 'Reports, newest month first. status any, draft, review, confirmed or published; period a month as YYYY-MM or null.',
    { client_id: opt, status: { type: 'string', enum: ['any', 'draft', 'review', 'confirmed', 'published'] }, period: opt }),
  tool('find_colleagues', 'Colleagues who take tasks, by name or Employee ID. Use it to fill an owner.', { query: str }),
  tool('propose_add_task', 'Propose an everyday task (not a content post). The colleague confirms it on a card. client_id null for internal work; owner_id null for the colleague asking.',
    { title: str, client_id: opt, owner_id: opt, due_date: day,
      priority: { type: 'string', enum: ['normal', 'medium', 'high', 'urgent'] }, description: opt }),
  tool('propose_reassign_task', 'Propose giving a task to another colleague.', { task_id: str, owner_id: str }),
  tool('propose_due_date', 'Propose moving a task\'s Due date. Where the colleague may not move it, it is asked of the person who set it.',
    { task_id: str, due_date: day,
      reason: { type: 'string', enum: ['client_request', 'scope_change', 'capacity', 'pending_assets', 'pending_confirmation', 'correction'] },
      note: opt }),
  tool('propose_log_call', 'Propose logging a call, visit, meeting, WhatsApp, email or note with a client.',
    { client_id: str, kind: { type: 'string', enum: ['call', 'visit', 'meeting', 'whatsapp', 'email', 'note'] },
      happened_on: day, with: opt, summary: str, next_action: opt, next_on: optDay }),
  tool('propose_remark', 'Propose adding a remark to a task.', { task_id: str, text: str }),
  tool('propose_mark_sent', 'Propose marking a published report as sent to the client on a day.', { report_id: str, sent_on: day }),
  tool('client_months', 'A client\'s content months in My Work, newest first: each month as YYYY-MM, whether it is open, and its meeting.', { client_id: str }),
  tool('list_sets', 'A client\'s content sets in Content Review, newest first: Draft or Published, and how many posts are approved, have changes requested or are not decided.', { client_id: str }),
  tool('list_campaigns', 'Creator campaigns, newest first, of one client or all.', { client_id: opt }),
  tool('find_contacts', 'A client\'s contacts: name, role, the primary contact, and whether WhatsApp can reach them.', { client_id: str }),
  tool('propose_meeting', 'Propose booking a client month\'s meeting. month as YYYY-MM, a month the client has; time as HH:MM, Malaysia time; minutes 15 to 240; channel google_meet (the shared calendar makes the link) or onsite; led_by a person_id or null for the colleague asking.',
    { client_id: str, month: str, date: day, time: str, minutes: { type: 'integer' },
      channel: { type: 'string', enum: ['google_meet', 'onsite'] }, led_by: opt }),
  tool('propose_campaign', 'Propose creating a creator campaign as a draft for an Active client. creators is how many creators it books. person_in_charge a person_id or null for the colleague asking. format and deliverable null for Site visit and Video.',
    { client_id: str, title: str, creators: { type: 'integer' }, person_in_charge: opt,
      format: { type: ['string', 'null'], enum: ['site_visit', 'event', 'seeding', 'tenant_trail', null] },
      deliverable: { type: ['string', 'null'], enum: ['video', 'graphic', null] } }),
  tool('propose_publish_set', 'Propose publishing a content set, so the client sees it on their review link.', { set_id: str }),
  tool('propose_unpublish_set', 'Propose unpublishing a content set, so the client no longer sees it.', { set_id: str }),
  tool('propose_whatsapp', 'Propose sending a WhatsApp template to a client\'s contact. purpose approval (a reminder that a set or a creator\'s draft waits; ref the set_id or the booking), feedback (asks an Active client for feedback), representative (introduces a lead\'s Sales by colleague) or message (template names the approved template). The card shows the message as it will read.',
    { contact_id: str, purpose: { type: 'string', enum: ['approval', 'feedback', 'representative', 'message'] }, ref: opt, template: opt }),
  tool('propose_schedule', 'Propose doing something later, at a date and time (Malaysia time). kind reminder (message is what to be reminded of; client_id, task_id or report_id what it opens), mark_sent (report_id), add_task (task_title, client_id, owner_id, due_date, priority, message as the brief), publish_set or unpublish_set (set_id), whatsapp (contact_id, purpose approval, feedback or representative, ref). title is a short name for the list. condition null, or set_undecided (set_id or ref), report_not_sent (report_id) or task_open (task_id). Fields a kind does not use are null.',
    { kind: { type: 'string', enum: ['reminder', 'mark_sent', 'add_task', 'publish_set', 'unpublish_set', 'whatsapp'] },
      date: day, time: str, title: str, message: opt, client_id: opt, task_id: opt, report_id: opt, set_id: opt,
      contact_id: opt, purpose: { type: ['string', 'null'], enum: ['approval', 'feedback', 'representative', null] }, ref: opt,
      task_title: opt, owner_id: opt, due_date: optDay,
      priority: { type: ['string', 'null'], enum: ['normal', 'medium', 'high', 'urgent', null] },
      condition: { type: ['string', 'null'], enum: ['set_undecided', 'report_not_sent', 'task_open', null] } }),
  tool('open_page', 'Offer the colleague a button that opens a record on its own screen: a client (pane overview, calls, services, billing, brand, engagements), a client\'s months in My Work (client_month, id the client_id), a task, a report, a content set, a video script, a campaign, My Work or the Dashboard.',
    { kind: { type: 'string', enum: ['client', 'client_month', 'task', 'report', 'set', 'script', 'campaign', 'my_work', 'dashboard'] },
      id: opt, pane: opt, label: str })
];
// The tools never change, so they and the instructions are cached.
// deno-lint-ignore no-explicit-any
(TOOLS[TOOLS.length - 1] as any).cache_control = { type: 'ephemeral' };

/* ---- The conversation the page sends ---------------------------------------
   Only what a conversation can hold: user and assistant turns, text, the
   assistant's own blocks back unchanged, and tool results. */
const BLOCKS = new Set(['text', 'tool_use', 'tool_result', 'thinking', 'redacted_thinking']);
// deno-lint-ignore no-explicit-any
function clean(messages: any): any[] | null {
  if (!Array.isArray(messages) || !messages.length || messages.length > 80) return null;
  // deno-lint-ignore no-explicit-any
  const out: any[] = [];
  for (const m of messages) {
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) return null;
    if (typeof m.content === 'string') {
      out.push({ role: m.role, content: m.role === 'user' ? scrub(m.content.slice(0, 4000)) : m.content.slice(0, 8000) });
      continue;
    }
    if (!Array.isArray(m.content) || !m.content.length) return null;
    // deno-lint-ignore no-explicit-any
    const blocks = m.content.map((b: any) => {
      if (!b || !BLOCKS.has(b.type)) return null;
      if (m.role === 'user' && b.type === 'text') return { type: 'text', text: scrub(String(b.text || '').slice(0, 4000)) };
      if (b.type === 'tool_result') {
        const c = typeof b.content === 'string' ? b.content.slice(0, 30000) : '';
        return { type: 'tool_result', tool_use_id: String(b.tool_use_id || ''), content: c, ...(b.is_error ? { is_error: true } : {}) };
      }
      return b;
    });
    if (blocks.some((b: unknown) => b == null)) return null;
    out.push({ role: m.role, content: blocks });
  }
  if (out[0].role !== 'user' || out[out.length - 1].role !== 'user') return null;
  return out;
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors(origin) });
  if (req.method !== 'POST') return json({ error: 'method' }, 405, origin);
  if (!secret('ANTHROPIC_API_KEY')) return json({ error: 'ai-not-set-up', missing: ['ANTHROPIC_API_KEY'] }, 200, origin);
  const model = secret('AGENT_MODEL') || 'claude-opus-5-5';

  const raw = await req.text().catch(() => '');
  if (!raw || raw.length > 400000) return json({ error: 'bad-request' }, 400, origin);
  let body: Record<string, unknown> = {};
  try { body = JSON.parse(raw); } catch { return json({ error: 'bad-request' }, 400, origin); }
  const messages = clean(body.messages);
  if (!messages) return json({ error: 'bad-request' }, 400, origin);

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });

  /* A new question is counted; a step of one already counted names it. */
  let pressId = typeof body.press === 'string' ? body.press : '';
  let left: unknown = null;
  if (!pressId) {
    const claim = await db.rpc('ai_agent_claim');
    if (claim.error) return json({ error: 'needs-update' }, 200, origin);
    const got = (claim.data || {}) as Record<string, unknown>;
    if (got.error) return json(got, 200, origin);
    pressId = String(got.id || '');
    left = got.left;
  } else {
    const turn = await db.rpc('ai_agent_turn', { p_press: pressId });
    if (turn.error) return json({ error: 'needs-update' }, 200, origin);
    const got = (turn.data || {}) as Record<string, unknown>;
    if (got.error) return json(got, 200, origin);
  }
  const done = (ok: boolean) => db.rpc('ai_draft_done', { p_id: pressId, p_ok: ok }).then(() => null, () => null);

  return held((async () => {
    const client = new Anthropic({ apiKey: secret('ANTHROPIC_API_KEY') });
    let input = 0, output = 0, usedModel = model;
    // deno-lint-ignore no-explicit-any
    let res: any = null;
    try {
      res = await client.beta.messages.create({
        model, max_tokens: 6000, system: SYSTEM, tools: TOOLS, tool_choice: { type: 'auto' },
        // Each step resends the whole conversation: cached, so a step pays for what is new.
        cache_control: { type: 'ephemeral' },
        output_config: { effort: 'medium' },
        betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default',
        messages
      } as unknown as Anthropic.Beta.Messages.MessageCreateParamsNonStreaming, { timeout: 110000 });
      // deno-lint-ignore no-explicit-any
      const u: any = res.usage || {};
      input = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
      output = u.output_tokens || 0;
      usedModel = res.model || usedModel;
    } catch (e) {
      const err = e as { status?: number; message?: string; error?: { error?: { message?: string } } };
      const msg = err.error?.error?.message || err.message || '';
      console.error('portal-agent: Claude API refused', err.status, msg);
      await done(false);
      return { error: err.status === 401 || err.status === 403 ? 'ai-key' : err.status === 429 || err.status === 529 ? 'ai-busy'
        : /credit balance/i.test(msg) ? 'ai-credit' : err.status === 404 ? 'ai-model' : /timed? ?out/i.test(msg) ? 'ai-slow' : 'ai-failed' };
    }
    await db.rpc('ai_agent_tokens', { p_press: pressId, p_in: input, p_out: output, p_model: usedModel }).then(() => null, () => null);
    if (res.stop_reason === 'refusal') { await done(false); return { error: 'ai-refused' }; }
    if (res.stop_reason !== 'tool_use') await done(true);
    return { press: pressId, left, stop: res.stop_reason, content: res.content };
  })(), origin);
});
