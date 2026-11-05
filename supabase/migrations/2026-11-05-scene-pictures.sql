-- SCENE PICTURES — a picture for every scene of a video script: the team's
-- photo or sketch, else a picture Write with AI drew (Gemini), else the
-- frame the page draws from the shot; the team's alone.
-- 2026-11-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/vssql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-11-05: all three, "C would be a section for
-- team to click to capture upload; B would be together with A combined AI
-- usages"; Gemini Flash, team only, 30 a day)
--   1. `video_script_scenes` gains `photo_url`, `photo_by`, `photo_at` (a
--      colleague's picture) and `ai_url`, `ai_at` (a picture drawn by AI),
--      each an address in the client's own folder on the CDN, and
--      `photo_thumb`, `ai_thumb`: the picture as a small JPEG data URL (the
--      crew PDF draws it; the CDN serves no read across origins).
--   2. `video_script_picture(p_script, p_scene, p_kind, p_url, p_press,
--      p_thumb)`:
--      Video Scripts at Work, the client in scope; `photo` sets or (null)
--      removes the colleague's picture, `ai` sets the drawn one and names
--      the press it was counted under (`bad-press`); `bad-url` for an
--      address outside the client's folder. Filed `script.saved`.
--   3. Scene pictures are an AI use of their own (`ai_drafts.purpose`
--      `picture`, one row a picture): `ai_picture_claim(p_script, p_count)`
--      counts them before Gemini is asked, `ai_picture_left()`; 30 a person
--      a day by default (`ai_cap_default`), set on AI usage
--      (`ai_draft_set_limit` `picture`), each priced at the Business setting
--      `ai_price_image` (US$ 0.07 from 5 Nov 2026) in `ai_draft_usage`.
--   4. `get_scripts` is unchanged: the client link reads no picture.
--
-- ROLLBACK
--   Pages first, then restate ai_draft_usage from BILLING AUDIT FIXES,
--   ai_draft_set_limit and ai_cap_default from AI LIMITS EACH USE, and drop
--   video_script_picture, ai_picture_claim and ai_picture_left in the SQL
--   Editor. The columns and the purpose may stay.
-- ===========================================================================

alter table public.video_script_scenes add column if not exists photo_url text;
alter table public.video_script_scenes add column if not exists photo_by text;
alter table public.video_script_scenes add column if not exists photo_at timestamptz;
alter table public.video_script_scenes add column if not exists ai_url text;
alter table public.video_script_scenes add column if not exists ai_at timestamptz;
alter table public.video_script_scenes add column if not exists photo_thumb text;
alter table public.video_script_scenes add column if not exists ai_thumb text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'ai_drafts_purpose' and pg_get_constraintdef(oid) like '%picture%') then
    alter table public.ai_drafts drop constraint if exists ai_drafts_purpose;
    alter table public.ai_drafts add constraint ai_drafts_purpose
      check (purpose in ('draft', 'check', 'caption', 'script', 'analysis', 'checklist', 'analytics', 'picture'));
  end if;
end $$;

insert into public.app_settings (key, from_date, value)
select 'ai_price_image', date '2026-11-05', 0.07
 where not exists (select 1 from public.app_settings s where s.key = 'ai_price_image');

create or replace function public.ai_cap_default(p_use text)
returns integer language sql immutable set search_path = public as $$
  select case p_use when 'drafts' then 10 when 'checks' then 10 when 'caption' then 20 when 'script' then 10 when 'picture' then 30
                    when 'analysis' then 3 when 'checklist' then 10 when 'analytics' then 3 when 'per_report' then 1 else 0 end
$$;
revoke all on function public.ai_cap_default(text) from public, anon, authenticated;

/* Scene pictures: counted a picture each before Gemini is asked, apart from
   every other use, under the same lock as the drafts. */
create or replace function public.ai_picture_claim(p_script uuid, p_count integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  v public.video_scripts;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  ids uuid[] := '{}';
  new_id uuid;
begin
  if not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_count is null or p_count < 1 or p_count > 60 then return jsonb_build_object('error', 'bad-count'); end if;
  select * into v from public.video_scripts x where x.id = p_script;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(v.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := public.ai_cap(m.id, 'picture');
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'picture' and d.created_at >= since and d.outcome <> 'failed';
  if n_used + p_count > lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'picture', 'limit', lim, 'left', greatest(0, lim - n_used),
                              'next', since + interval '1 day');
  end if;
  for i in 1 .. p_count loop
    insert into public.ai_drafts (team_member_id, client_id, script_id, purpose)
    values (m.id, v.client_id, v.id, 'picture') returning id into new_id;
    ids := ids || new_id;
  end loop;
  return jsonb_build_object('ids', to_jsonb(ids), 'left', lim - n_used - p_count, 'limit', lim);
end $$;
revoke all on function public.ai_picture_claim(uuid, integer) from public, anon;
grant execute on function public.ai_picture_claim(uuid, integer) to authenticated;

create or replace function public.ai_picture_left()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
  l_left integer;
begin
  if not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := public.ai_cap(m.id, 'picture');
  l_left := greatest(0, lim - (select count(*) from public.ai_drafts d
    where d.team_member_id = m.id and d.purpose = 'picture' and d.created_at >= since and d.outcome <> 'failed')::integer);
  return jsonb_build_object('left', l_left, 'limit', lim, 'scope', case when lim = 0 then 'stopped' else 'picture' end,
    'next', case when l_left > 0 or lim = 0 then null else since + interval '1 day' end);
end $$;
revoke all on function public.ai_picture_left() from public, anon;
grant execute on function public.ai_picture_left() to authenticated;

/* A scene's picture: the colleague's (`photo`, null removes it) or the one
   AI drew (`ai`, named by the press it was counted under). Only an https
   address in the script's client's own folder is kept. */
create or replace function public.video_script_picture(p_script uuid, p_scene uuid, p_kind text, p_url text,
                                                       p_press uuid default null, p_thumb text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.video_scripts;
  sc    public.video_script_scenes;
  v_cl  text;
  v_url text := nullif(btrim(coalesce(p_url, '')), '');
  v_det text;
  v_th  text := nullif(btrim(coalesce(p_thumb, '')), '');
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.video_scripts x where x.id = p_script for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(s.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  select * into sc from public.video_script_scenes y where y.id = p_scene and y.script_id = p_script;
  if sc.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(p_kind, '') not in ('photo', 'ai') then return jsonb_build_object('error', 'bad-kind'); end if;
  if v_url is not null and (v_url !~ '^https://[a-z0-9.-]+/[A-Za-z0-9/._-]+$' or length(v_url) > 1000
                            or position('/' || s.client_id::text || '/' in v_url) = 0) then
    return jsonb_build_object('error', 'bad-url');
  end if;
  if v_th is not null and (v_th !~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$' or length(v_th) > 200000) then
    return jsonb_build_object('error', 'bad-thumb');
  end if;
  if p_kind = 'ai' then
    if v_url is null then return jsonb_build_object('error', 'bad-url'); end if;
    if not exists (select 1 from public.ai_drafts d where d.id = p_press and d.team_member_id = me.id
                    and d.purpose = 'picture' and d.script_id = p_script and d.created_at > now() - interval '1 day') then
      return jsonb_build_object('error', 'bad-press');
    end if;
    update public.video_script_scenes y set ai_url = v_url, ai_at = now(), ai_thumb = v_th where y.id = p_scene;
    v_det := 'Scene ' || sc.position || ' picture drawn with AI';
  elsif v_url is null then
    if sc.photo_url is null then return jsonb_build_object('ok', true, 'changed', false); end if;
    update public.video_script_scenes y set photo_url = null, photo_by = null, photo_at = null, photo_thumb = null where y.id = p_scene;
    v_det := 'Scene ' || sc.position || ' photo removed';
  else
    update public.video_script_scenes y set photo_url = v_url, photo_by = me.name, photo_at = now(), photo_thumb = v_th where y.id = p_scene;
    v_det := 'Scene ' || sc.position || ' photo ' || case when sc.photo_url is null then 'added' else 'replaced' end;
  end if;
  select c.name into v_cl from public.clients c where c.id = s.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.saved', v_cl, public.video_script_label(s) || ' · ' || v_det);
  return jsonb_build_object('ok', true, 'changed', true);
end $$;
revoke all on function public.video_script_picture(uuid, uuid, text, text, uuid, text) from public, anon;
grant execute on function public.video_script_picture(uuid, uuid, text, text, uuid, text) to authenticated;

create or replace function public.ai_draft_set_limit(p_scope text, p_daily integer)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_name text;
  v_was integer;
  v_def integer;
  v_scope text := btrim(coalesce(p_scope, ''));
  v_use text;
  t public.team_members;
  v_words constant jsonb := '{"drafts":"Report drafts","checks":"Commentary checks","caption":"Captions","script":"Scripts","picture":"Scene pictures",
    "analysis":"Brand analyses","checklist":"Checklists","analytics":"Analytics analyses"}';
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'per_report' then
    if p_daily is not null and p_daily > 1 then return jsonb_build_object('error', 'bad-limit'); end if;
    v_name := 'One draft and one check a report a day';
  elsif v_words ? v_scope then
    v_name := v_words ->> v_scope;
    v_def := public.ai_cap_default(v_scope);
  elsif v_scope ~ '^[0-9a-f-]{36}:[a-z]+$' and v_words ? split_part(v_scope, ':', 2) then
    v_use := split_part(v_scope, ':', 2);
    select * into t from public.team_members x where x.id::text = split_part(v_scope, ':', 1);
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_name := (v_words ->> v_use) || ', ' || t.name;
    select l.daily into v_def from public.ai_draft_limits l where l.scope = v_use;
    v_def := coalesce(v_def, public.ai_cap(null, v_use));
  else
    return jsonb_build_object('error', 'bad-scope');
  end if;
  select l.daily into v_was from public.ai_draft_limits l where l.scope = v_scope;
  if v_was is not distinct from p_daily then return jsonb_build_object('ok', true, 'same', true); end if;
  select coalesce(x.name, x.email) into v_who from public.team_members x
   where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active limit 1;
  insert into public.ai_draft_limits (scope, daily, set_by, set_at)
  values (v_scope, p_daily, v_who, now())
  on conflict (scope) do update set daily = excluded.daily, set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'AI',
          v_name || ': ' ||
          case when v_scope = 'per_report' then case when coalesce(v_was, 1) = 0 then 'off' else 'on' end || ' → ' ||
                                                case when coalesce(p_daily, 1) = 0 then 'off' else 'on' end
               else case when v_was is null then 'standard, ' || v_def || ' a day' when v_was = 0 then 'stopped' else v_was || ' a day' end ||
                    ' → ' ||
                    case when p_daily is null then 'standard, ' || v_def || ' a day' when p_daily = 0 then 'stopped' else p_daily || ' a day' end
          end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ai_draft_set_limit(text, integer) from public, anon, authenticated;
grant execute on function public.ai_draft_set_limit(text, integer) to authenticated;

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
                          + case when d.purpose = 'picture' then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens, d.web_searches,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                  + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0
                  + case when d.purpose = 'picture' then coalesce(public.app_setting('ai_price_image', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 0.07) else 0 end as usd
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

-- END OF SCENE PICTURES -------------------------------------------------------

select public.functions_tidy();
