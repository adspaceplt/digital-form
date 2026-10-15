-- ===========================================================================
-- ANALYSIS FILLS THE BRIEF — a confirmed Brand analysis writes the Content
-- brief's empty parts (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: the analysis "needs all these Fill in the
-- client's Content brief first … even though the website, facebook page,
-- instagram all filled"; chose "Analysis fills the brief")
--
-- WHAT CHANGED
--   * `brand-analysis` no longer waits for the brief: it needs the website, a
--     handle or a linked Meta account (`no-source`), and answers a brief
--     (audience, pains, pillars, tone) with the analysis.
--   * `brand_analysis_confirm` fills each part of the client's brief left
--     empty (Audience, Pains, Content pillars, Tone of voice, Competitors)
--     from the analysis it confirms, where the colleague holds Clients at
--     Work on the client; a part already written is never replaced. An
--     analysis from before takes its audiences, pillars and competitors.
--     What it filled is answered as `filled` and filed `client.brand`.
--   * Captions and scripts still wait for the brief and a confirmed analysis
--     (`ai_brand_ready`, unchanged): confirming one now gives both.
--
-- ROLLBACK
--   Run BRAND ANALYSIS' brand_analysis_confirm again and deploy
--   brand-analysis as it stood. A brief already filled stays.
--
-- Safe to run twice. Mirrored byte for byte in supabase/schema.sql under the
-- same banner.
-- ===========================================================================

create or replace function public.brand_analysis_confirm(p_id uuid, p_on boolean default true)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  a public.brand_analyses;
  c public.clients;
  v_an jsonb;
  v_was jsonb;
  v_new jsonb;
  v_put text;
  v_k text;
  v_filled text[] := '{}';
  v_word text;
begin
  if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into a from public.brand_analyses x where x.id = p_id for update;
  if a.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(a.client_id, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  select * into c from public.clients x where x.id = a.client_id;
  if coalesce(p_on, true) = (a.confirmed_at is not null) then return public.brand_analysis_row(a); end if;
  update public.brand_analyses x
     set confirmed_at = case when coalesce(p_on, true) then now() end,
         confirmed_by = case when coalesce(p_on, true) then m.id end
   where x.id = p_id returning * into a;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(m.name, m.email), 'client.brand', c.name,
          'Brand analysis: version ' || a.version ||
          case when coalesce(p_on, true) then ' written with AI, read and confirmed' else ' confirmation withdrawn' end);

  /* The brief's empty parts, from what this analysis concluded. */
  if coalesce(p_on, true) and public.allowed('clients', 'work') and public.client_scope_ok('client', c.id, 'work') then
    v_an := coalesce(a.analysis, '{}'::jsonb);
    v_was := case when jsonb_typeof(c.brief) = 'object' then c.brief else '{}'::jsonb end;
    v_new := v_was;
    foreach v_k in array array['audience', 'pains', 'pillars', 'tone', 'competitors'] loop
      if coalesce(btrim(v_was ->> v_k), '') <> '' then continue; end if;
      v_put := case v_k
        when 'audience' then coalesce(nullif(btrim(v_an #>> '{brief,audience}'), ''),
          (select string_agg(btrim(concat_ws(': ', s ->> 'name', s ->> 'who')), E'\n')
             from jsonb_array_elements(case when jsonb_typeof(v_an -> 'audiences') = 'array' then v_an -> 'audiences' else '[]'::jsonb end) s))
        when 'pains' then coalesce(nullif(btrim(v_an #>> '{brief,pains}'), ''),
          (select string_agg(btrim(s ->> 'pains'), E'\n')
             from jsonb_array_elements(case when jsonb_typeof(v_an -> 'audiences') = 'array' then v_an -> 'audiences' else '[]'::jsonb end) s
            where coalesce(btrim(s ->> 'pains'), '') <> ''))
        when 'pillars' then
          (select string_agg(btrim(p #>> '{}'), E'\n')
             from jsonb_array_elements(case when jsonb_typeof(v_an #> '{brief,pillars}') = 'array' and jsonb_array_length(v_an #> '{brief,pillars}') > 0
                                            then v_an #> '{brief,pillars}'
                                            when jsonb_typeof(v_an #> '{content,pillars}') = 'array' then v_an #> '{content,pillars}'
                                            else '[]'::jsonb end) p)
        when 'tone' then nullif(btrim(v_an #>> '{brief,tone}'), '')
        else (select string_agg(btrim(p #>> '{}'), ', ')
                from jsonb_array_elements(case when jsonb_typeof(v_an #> '{positioning,competitors}') = 'array'
                                               then v_an #> '{positioning,competitors}' else '[]'::jsonb end) p)
      end;
      v_put := left(btrim(coalesce(v_put, '')), 1000);
      if v_put = '' then continue; end if;
      v_new := v_new || jsonb_build_object(v_k, v_put);
      v_word := case v_k when 'audience' then 'Audience' when 'pains' then 'Pains' when 'pillars' then 'Content pillars'
                         when 'tone' then 'Tone of voice' else 'Competitors' end;
      v_filled := v_filled || v_word;
    end loop;
    if array_length(v_filled, 1) > 0 and char_length(v_new::text) <= 8000 then
      update public.clients x set brief = v_new where x.id = c.id;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(m.name, m.email), 'client.brand', c.name,
              'Content brief: ' || array_to_string(v_filled, ', ') || ' filled from Brand analysis version ' || a.version);
    else
      v_filled := '{}';
    end if;
  end if;
  return public.brand_analysis_row(a) || jsonb_build_object('filled', to_jsonb(v_filled));
end $$;
revoke all on function public.brand_analysis_confirm(uuid, boolean) from public, anon, authenticated;
grant execute on function public.brand_analysis_confirm(uuid, boolean) to authenticated;

-- END OF ANALYSIS FILLS THE BRIEF -------------------------------------------

select public.functions_tidy();
