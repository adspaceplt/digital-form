/*
 * The AI prompts, the edge functions' one read of them (restructure release
 * 17, 2026-11-28): every prompt a function sends Claude is a template in
 * the store (`templates`, kind ai-prompt, English, versioned), keyed
 * `ai.{function}.{part}`, rendered by the database's one engine
 * (`template_render`) as the colleague who pressed. A prompt names another
 * by its key in braces (`{ai.report-draft.avoid}`), filled here from the
 * same read. Never typed in a function.
 *
 *   prompts(db, keys)  each key's words, or throws PromptMissing where one
 *                      is not live, blank or not read
 *   promptRefusal(e)   the answer a function gives for that: denied where
 *                      the caller is no colleague, else ai-not-set-up,
 *                      which every page words as not set up yet (the key is
 *                      logged, never shown); null for any other error
 *
 * A function asks before it claims a press, so a missing prompt costs the
 * colleague nothing and Claude is never sent an empty prompt.
 */
type Rpc = { rpc: (name: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }> };

export class PromptMissing extends Error {
  keys: string[];
  denied: boolean;
  constructor(keys: string[], denied = false) { super('prompt-missing: ' + keys.join(', ')); this.keys = keys; this.denied = denied; }
}

export async function prompts(db: Rpc, keys: string[]): Promise<Record<string, string>> {
  let denied = false;
  const read = await Promise.all(keys.map(async (k) => {
    try {
      const r = await db.rpc('template_render', { p_key: k, p_lang: 'en' });
      const d = r && !r.error ? r.data as Record<string, unknown> | null : null;
      if (d && d.error === 'denied') denied = true;
      return d && d.ok === true && typeof d.text === 'string' && d.text.trim() ? d.text : null;
    } catch (_e) { return null; }
  }));
  const missing = keys.filter((_k, i) => read[i] === null);
  if (missing.length) throw new PromptMissing(missing, denied);
  const raw: Record<string, string> = {}, out: Record<string, string> = {};
  keys.forEach((k, i) => { raw[k] = read[i] as string; });
  for (const k of keys) {
    out[k] = raw[k].replace(/\{(ai\.[a-z0-9.-]+)\}/g, (m, inc) => {
      if (inc === k) return m;
      if (!(inc in raw)) throw new PromptMissing([inc]);
      return raw[inc];
    });
  }
  return out;
}

export function promptRefusal(e: unknown): { error: string; missing: string[] } | null {
  if (!(e instanceof PromptMissing)) return null;
  if (e.denied) return { error: 'denied', missing: [] };
  console.error('ai prompt not live: ' + e.keys.join(', '));
  return { error: 'ai-not-set-up', missing: ['prompt'] };
}
