-- 2026-10-12 · Write with AI waits for the client's brand.
-- Safe to run twice. Rollback is in the band's head.

-- AI NEEDS THE BRAND — Write with AI on a caption or a script, and a Brand
-- analysis, are asked only once the client's brand is written down (the user,
-- 2026-10-12: "when the brand analysis or brand details are empty; do not
-- allow the content copywriting and those needed the AI to write or analysis
-- to write anything"). Reports are left as they are: their words come from
-- the report's own figures.
--   1. `ai_brand_ready(p_client)`: for a colleague who sees the client, what
--      it still lacks: `missing`, the Content brief's parts left empty of
--      Audience, Content pillars and Tone of voice (`audience`, `pillars`,
--      `tone`), and `analysis`, whether a Brand analysis is confirmed.
--      `caption-draft` and `script-draft` refuse `no-brief` while a part is
--      missing and `no-analysis` while none is confirmed; `brand-analysis`
--      refuses `no-brief`. Each asks before it claims a use, so a refusal
--      counts nothing.
-- Rollback: deploy the three functions as they stood, then
--   drop function if exists public.ai_brand_ready(uuid);
create or replace function public.ai_brand_ready(p_client uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_team() or not public.client_seen(p_client, 'view')
    then jsonb_build_object('error', 'denied')
    else (select jsonb_build_object(
      'missing', coalesce((select jsonb_agg(x.k order by x.o)
                             from unnest(array['audience', 'pillars', 'tone']) with ordinality as x(k, o)
                            where coalesce(btrim(case when jsonb_typeof(c.brief) = 'object' then c.brief ->> x.k end), '') = ''),
                          '[]'::jsonb),
      'analysis', exists (select 1 from public.brand_analyses a
                           where a.client_id = c.id and a.confirmed_at is not null))
      from public.clients c where c.id = p_client) end
$$;
revoke all on function public.ai_brand_ready(uuid) from public, anon, authenticated;
grant execute on function public.ai_brand_ready(uuid) to authenticated;
-- END OF AI NEEDS THE BRAND -------------------------------------------------

select public.functions_tidy();
