-- SCENE FRAMES DRAWN BY CLAUDE — Draw with AI draws each scene of a video
-- script as a line drawing written by Claude, in place of Gemini's picture.
-- 2026-11-06. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/vssql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-11-06: "Claude couldnt draw but able to
-- generate motions n clips right why not do that replace gemini", the
-- sample approved as a draft, then the animatic, "1 yes")
--   1. `video_script_scenes.ai_frame` (jsonb): the frame Claude drew, kept
--      as data and never as markup (`v`, `shot_size`, `angle`, `move` and
--      `shapes`, each a path `d` of path commands and numbers alone and a
--      `t` of ink, light, fill or paper); the page builds the drawing from
--      it, so nothing Claude writes is ever drawn as markup.
--   2. `video_script_frame(p_script, p_scene, p_frame, p_press)`: Video
--      Scripts at Work, the client in scope, the press the caller's own
--      picture use on this script within a day (`bad-press`); `bad-frame`
--      for anything else. The script-pictures function keeps each frame
--      as it is drawn. Filed `script.saved` (Scene n picture drawn with AI).
--   3. `ai_draft_usage`: a scene picture is priced by its tokens as every
--      Claude use is; the flat `ai_price_image` stays for a picture drawn
--      by Gemini before (a row whose model names gemini).
--   4. `get_scripts` is unchanged: the client link reads no picture.
--
-- ROLLBACK
--   Pages first, then restate ai_draft_usage from SCENE PICTURES and drop
--   video_script_frame in the SQL Editor. The column may stay.
-- ===========================================================================

alter table public.video_script_scenes add column if not exists ai_frame jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'video_script_scenes_ai_frame_size') then
    alter table public.video_script_scenes add constraint video_script_scenes_ai_frame_size
      check (ai_frame is null or (jsonb_typeof(ai_frame) = 'object' and length(ai_frame::text) <= 80000));
  end if;
end $$;

create or replace function public.video_script_frame(p_script uuid, p_scene uuid, p_frame jsonb, p_press uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.video_scripts;
  sc    public.video_script_scenes;
  v_cl  text;
  v_sh  jsonb;
  v_n   integer;
  v_bad integer;
  v_out jsonb;
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.video_scripts x where x.id = p_script for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(s.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  select * into sc from public.video_script_scenes y where y.id = p_scene and y.script_id = p_script;
  if sc.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not exists (select 1 from public.ai_drafts d where d.id = p_press and d.team_member_id = me.id
                  and d.purpose = 'picture' and d.script_id = p_script and d.created_at > now() - interval '1 day') then
    return jsonb_build_object('error', 'bad-press');
  end if;
  if jsonb_typeof(p_frame) is distinct from 'object' or jsonb_typeof(p_frame -> 'shapes') is distinct from 'array'
     or length(p_frame::text) > 80000 then
    return jsonb_build_object('error', 'bad-frame');
  end if;
  v_sh := p_frame -> 'shapes';
  v_n := jsonb_array_length(v_sh);
  if v_n < 1 or v_n > 160 then return jsonb_build_object('error', 'bad-frame'); end if;
  select count(*) into v_bad from jsonb_array_elements(v_sh) e
   where jsonb_typeof(e.value) is distinct from 'object'
      or coalesce(e.value ->> 't', '') not in ('ink', 'light', 'fill', 'paper')
      or coalesce(e.value ->> 'd', '') !~ '^[MmLlHhVvCcSsQqTtAaZz0-9 .,eE+-]+$'
      or length(coalesce(e.value ->> 'd', '')) not between 2 and 4000;
  if v_bad > 0 then return jsonb_build_object('error', 'bad-frame'); end if;
  if coalesce(p_frame ->> 'move', '') not in ('', 'static', 'push in', 'pull out', 'pan left', 'pan right', 'tilt up', 'tilt down') then
    return jsonb_build_object('error', 'bad-frame');
  end if;
  -- Kept as the page draws it: the fields it reads and nothing else.
  v_out := jsonb_build_object('v', 1,
    'shot_size', left(btrim(coalesce(p_frame ->> 'shot_size', '')), 60),
    'angle', left(btrim(coalesce(p_frame ->> 'angle', '')), 60),
    'move', coalesce(nullif(p_frame ->> 'move', ''), 'static'),
    'shapes', (select jsonb_agg(jsonb_build_object('d', e.value ->> 'd', 't', e.value ->> 't') order by e.ord)
                 from jsonb_array_elements(v_sh) with ordinality e(value, ord)));
  update public.video_script_scenes y set ai_frame = v_out, ai_at = now() where y.id = p_scene;
  select c.name into v_cl from public.clients c where c.id = s.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.saved', v_cl, public.video_script_label(s) || ' · Scene ' || sc.position || ' picture drawn with AI');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.video_script_frame(uuid, uuid, jsonb, uuid) from public, anon;
grant execute on function public.video_script_frame(uuid, uuid, jsonb, uuid) to authenticated;

create or replace function public.ai_draft_usage()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  -- This calendar month in Malaysia, for what the calls cost.
  v_cal timestamptz := date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_uses constant text[] := array['drafts', 'checks', 'caption', 'script', 'picture', 'analysis', 'checklist', 'analytics'];
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'limits', (select jsonb_object_agg(u, public.ai_cap(null, u)) from unnest(v_uses || array['per_report']) u),
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'price_search', coalesce(public.app_setting('ai_price_search', v_today), 10),
        'price_image', coalesce(public.app_setting('ai_price_image', v_today), 0.07),
        'uses', count(*),
        'untracked', count(*) filter (where c.input_tokens is null),
        'input', coalesce(sum(c.input_tokens), 0),
        'output', coalesce(sum(c.output_tokens), 0),
        'searches', coalesce(sum(c.web_searches), 0),
        'usd', round(coalesce(sum(c.usd), 0), 2),
        'by', coalesce((select jsonb_object_agg(p.purpose, p.x) from (
            select c2.purpose, jsonb_build_object('uses', count(*), 'input', coalesce(sum(c2.input_tokens), 0),
                     'output', coalesce(sum(c2.output_tokens), 0), 'searches', coalesce(sum(c2.web_searches), 0),
                     'usd', round(coalesce(sum(c2.usd), 0), 2)) as x
              from (select d.purpose, d.input_tokens, d.output_tokens, d.web_searches,
                           (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                          + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                          + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0
                          + case when d.purpose = 'picture' and coalesce(d.model, '') like 'gemini%' then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens, d.web_searches,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                  + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0
                  + case when d.purpose = 'picture' and coalesce(d.model, '') like 'gemini%' then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end as usd
              from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'used', jsonb_build_object('drafts', u.drafts, 'checks', u.checks, 'caption', u.caption, 'script', u.script, 'picture', u.picture,
                                   'analysis', u.analysis, 'checklist', u.checklist, 'analytics', u.analytics),
        'cap', (select jsonb_object_agg(k, public.ai_cap(t.id, k)) from unnest(v_uses) k),
        'own', coalesce((select jsonb_object_agg(split_part(l.scope, ':', 2), l.daily) from public.ai_draft_limits l
                          where l.scope like t.id::text || ':%' and l.daily is not null), '{}'::jsonb),
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed')) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
        cross join lateral (
          select count(*) filter (where d.purpose = 'draft') as drafts, count(*) filter (where d.purpose = 'check') as checks,
                 count(*) filter (where d.purpose = 'caption') as caption, count(*) filter (where d.purpose = 'script') as script,
                 count(*) filter (where d.purpose = 'picture') as picture,
                 count(*) filter (where d.purpose = 'analysis') as analysis, count(*) filter (where d.purpose = 'checklist') as checklist,
                 count(*) filter (where d.purpose = 'analytics') as analytics
            from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed') u
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'review', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'scripts', 'none')) >= public.level_rank('work')
              -- Brand analysis asks Clients: Brand at View, a checklist's
              -- writer Clients: Checklists at Work, Analytics its granted
              -- part: each is offered a limit before its first use (audit
              -- 2026-11-04).
              or public.level_rank(coalesce(t.access ->> 'clients.brand', t.access ->> 'clients', 'none')) >= public.level_rank('view')
              or public.level_rank(coalesce(t.access ->> 'clients.checklists', t.access ->> 'clients', 'none')) >= public.level_rank('work')
              or coalesce(t.access ->> 'team.analytics', 'none') <> 'none'
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

-- END OF SCENE FRAMES DRAWN BY CLAUDE ------------------------------------------

select public.functions_tidy();
