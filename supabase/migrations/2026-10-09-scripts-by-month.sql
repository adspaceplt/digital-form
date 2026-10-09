-- ===========================================================================
-- SCRIPTS BY MONTH — a video script belongs to a client's content month and
-- is numbered in it (YYMMVSNN), the client link is for reading the script
-- and recording the clip numbers on site, and the client no longer decides
-- on it.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/vssql.js compares the
-- two.
--
-- WHAT CHANGED
--   The user (2026-10-09): "we are working on content month, monthly basis
--   … the default for video script can be YYMMVSNN (VS is video script
--   meaning) NN is the number of script … one script is for one full video
--   … no need show the approve or changes at client side, the public link …
--   is for us and or client to view how the video script is like digitally;
--   and on the spot digital use for entering VC#." The user's answers: VC#
--   in the console and on the link; a month picked, linked where My Work
--   holds it; the link shows shared scripts only; NN counted per client a
--   month.
--   1. `video_scripts.period` (YYYY-MM), `seq` (1 to 99) and `code`
--      (`2610VS01`, kept from the two), unique a client a month;
--      `engagement_id` names the client's My Work month for the period
--      where one exists (set on create and on a move, never required).
--      Every script before this file takes the month of its shooting date,
--      else of the day it was made, numbered in the order it was made.
--      `series_id` and `video_no` stay unread.
--   2. `video_script_new(p_client, p_period, p_kind, p_from, p_idem)` makes
--      a script in a month at the lowest free number; with `p_from` (Add next
--      script) the client and month are its, the header copied, the script
--      empty. `video_script_create` (the pages before this file) makes it in
--      its first video's month, else this month (MYT).
--   3. `video_script_save` takes `period` in the head: the script moves to
--      that month at its lowest free number, filed with both codes.
--      Deleting asks for the title typed back, else the code.
--   4. `script_shot_link(p_token, p_script, p_scene, p_on, p_vc)` (anon,
--      joins `open_to_anon`): the client link records a shared script's clip
--      numbers and Shot ticks on site, filed under the client by `Client
--      link`, as the console's `video_script_shot` does.
--   5. `get_scripts` sends each shared script's code, its scenes with their
--      ids, clip numbers and Shot ticks (never who ticked), the voice-over's,
--      and no decision. `script_decide` answers `closed` and writes nothing.
--
-- ROLLBACK
--   Pages first, then re-run VIDEO SCRIPTS (2026-10-09-video-scripts.sql) for
--   video_script_label, video_script_create, video_script_save,
--   video_script_delete, get_scripts and script_decide, and in the SQL
--   Editor drop script_shot_link and video_script_new. The columns may stay.
-- ===========================================================================

alter table public.video_scripts add column if not exists period text;
alter table public.video_scripts add column if not exists seq integer;
alter table public.video_scripts add column if not exists engagement_id uuid references public.ops_engagements(id) on delete set null;

update public.video_scripts s
   set period = to_char(coalesce(s.shoot_on, (s.created_at at time zone 'Asia/Kuala_Lumpur')::date), 'YYYY-MM')
 where s.period is null;
with n as (
  select s.id, row_number() over (partition by s.client_id, s.period order by s.created_at, s.video_no)
         + coalesce((select max(t.seq) from public.video_scripts t
                      where t.client_id = s.client_id and t.period = s.period and t.seq is not null), 0) as k
    from public.video_scripts s where s.seq is null)
update public.video_scripts s set seq = n.k from n where s.id = n.id;
update public.video_scripts s set engagement_id = e.id
  from public.ops_engagements e
 where s.engagement_id is null and e.client_id = s.client_id and e.period = s.period;

alter table public.video_scripts alter column period set not null;
alter table public.video_scripts alter column seq set not null;
alter table public.video_scripts add column if not exists code text
  generated always as (substr(period, 3, 2) || substr(period, 6, 2) || 'VS' || lpad(seq::text, 2, '0')) stored;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'video_scripts_period_shape') then
    alter table public.video_scripts add constraint video_scripts_period_shape
      check (period ~ '^\d{4}-(0[1-9]|1[0-2])$' and seq between 1 and 99);
  end if;
end $$;
create unique index if not exists video_scripts_month_seq_idx on public.video_scripts(client_id, period, seq);

-- 2610VS01 · Title, as every screen and the activity record name a script.
create or replace function public.video_script_label(p public.video_scripts)
returns text language sql immutable set search_path = public as $$
  select substr(p.period, 3, 2) || substr(p.period, 6, 2) || 'VS' || lpad(p.seq::text, 2, '0')
         || coalesce(' · ' || nullif(btrim(p.title), ''), '')
$$;
revoke all on function public.video_script_label(public.video_scripts) from public, anon, authenticated;

create or replace function public.video_script_new(p_client uuid, p_period text, p_kind text default null,
                                                   p_from uuid default null, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  f      public.video_scripts;
  v_cl   public.clients;
  v_kind text;
  v_per  text;
  v_seq  integer;
  v_eng  uuid;
  v_id   uuid;
  v_new  public.video_scripts;
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if nullif(btrim(coalesce(p_idem, '')), '') is not null then
    select s.id into v_id from public.video_scripts s where s.idem_key = p_idem;
    if v_id is not null then return jsonb_build_object('ok', true, 'id', v_id, 'again', true); end if;
  end if;
  if p_from is not null then
    select * into f from public.video_scripts s where s.id = p_from;
    if f.id is null or (p_client is not null and p_client <> f.client_id) then
      return jsonb_build_object('error', 'not-found');
    end if;
  end if;
  select * into v_cl from public.clients c where c.id = coalesce(f.client_id, p_client);
  if v_cl.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  v_per := coalesce(nullif(btrim(coalesce(p_period, '')), ''), f.period);
  if v_per is null or v_per !~ '^\d{4}-(0[1-9]|1[0-2])$' or v_per not between '2023-08' and '2099-12' then
    return jsonb_build_object('error', 'bad-period');
  end if;
  v_kind := coalesce(nullif(btrim(coalesce(p_kind, '')), ''), f.kind, 'scenes');
  if v_kind not in ('scenes', 'products', 'story') then return jsonb_build_object('error', 'bad-kind'); end if;
  perform pg_advisory_xact_lock(hashtext('video_script:' || v_cl.id::text || ':' || v_per));
  select min(g) into v_seq from generate_series(1, 99) g
   where not exists (select 1 from public.video_scripts s where s.client_id = v_cl.id and s.period = v_per and s.seq = g);
  if v_seq is null then return jsonb_build_object('error', 'too-many'); end if;
  select e.id into v_eng from public.ops_engagements e where e.client_id = v_cl.id and e.period = v_per limit 1;
  insert into public.video_scripts (client_id, period, seq, engagement_id, kind, platform, language, shoot_on,
                                    shoot_time, venue, duration_minutes, cast_names, idem_key,
                                    created_by, created_by_name, updated_by_name)
  values (v_cl.id, v_per, v_seq, v_eng, v_kind, f.platform, f.language, f.shoot_on, f.shoot_time, f.venue,
          f.duration_minutes, f.cast_names, nullif(btrim(coalesce(p_idem, '')), ''), me.id, me.name, me.name)
  returning * into v_new;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.created', v_cl.name,
          public.video_script_label(v_new) || ' · '
          || case v_kind when 'scenes' then 'Detailed scenes' when 'products' then 'Products and scenes'
                         else 'Story and voice-over' end
          || case when f.id is not null then ' · header from ' || f.code else '' end);
  return jsonb_build_object('ok', true, 'id', v_new.id, 'code', v_new.code, 'period', v_per, 'seq', v_seq);
end $$;
revoke all on function public.video_script_new(uuid, text, text, uuid, text) from public, anon;
grant execute on function public.video_script_new(uuid, text, text, uuid, text) to authenticated;

-- The pages before this file: the first video's month, else this month.
create or replace function public.video_script_create(p_client uuid, p_kind text, p_from uuid default null,
                                                      p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public.video_script_new(p_client,
    coalesce((select s.period from public.video_scripts s where s.id = p_from),
             to_char((now() at time zone 'Asia/Kuala_Lumpur')::date, 'YYYY-MM')),
    p_kind, p_from, p_idem);
end $$;
revoke all on function public.video_script_create(uuid, text, uuid, text) from public, anon;
grant execute on function public.video_script_create(uuid, text, uuid, text) to authenticated;

/* One save for the whole script: the header facts named in `p_head` (a key
   left out keeps its value; `period` moves it to that month at its lowest
   free number) and, where `p_scenes` is given, the scene rows in order ({id,
   visual, line}; a row named by its id keeps its clip number and its tick).
   Files what changed, from and to for a short value, by name for the long
   ones. */
create or replace function public.video_script_save(p_id uuid, p_head jsonb, p_scenes jsonb, p_version integer default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me        public.team_members := public.ops_me();
  v         public.video_scripts;
  n         public.video_scripts;
  v_client  text;
  h         jsonb := coalesce(p_head, '{}'::jsonb);
  v_moves   text[] := '{}';
  v_creat   boolean := false;
  v_old_sc  jsonb;
  v_new_sc  jsonb;
  v_row     jsonb;
  v_pos     integer := 0;
  v_keep    uuid[] := '{}';
  v_sid     uuid;
  v_kindw   text;
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v from public.video_scripts s where s.id = p_id for update;
  if v.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(v.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_version is not null and p_version <> v.version then
    return jsonb_build_object('error', 'stale', 'row', to_jsonb(v));
  end if;
  n := v;
  if h ? 'kind' then n.kind := h ->> 'kind'; end if;
  if h ? 'title' then n.title := btrim(coalesce(h ->> 'title', '')); end if;
  if h ? 'reference_url' then n.reference_url := nullif(btrim(coalesce(h ->> 'reference_url', '')), ''); end if;
  if h ? 'platform' then n.platform := nullif(btrim(coalesce(h ->> 'platform', '')), ''); end if;
  if h ? 'language' then n.language := nullif(btrim(coalesce(h ->> 'language', '')), ''); end if;
  if h ? 'shoot_on' then n.shoot_on := nullif(h ->> 'shoot_on', '')::date; end if;
  if h ? 'shoot_time' then n.shoot_time := nullif(h ->> 'shoot_time', '')::time; end if;
  if h ? 'venue' then n.venue := nullif(btrim(coalesce(h ->> 'venue', '')), ''); end if;
  if h ? 'duration_minutes' then n.duration_minutes := nullif(h ->> 'duration_minutes', '')::integer; end if;
  if h ? 'cast_names' then n.cast_names := nullif(btrim(coalesce(h ->> 'cast_names', '')), ''); end if;
  if h ? 'context' then n.context := nullif(btrim(coalesce(h ->> 'context', '')), ''); end if;
  if h ? 'vo' then n.vo := nullif(btrim(coalesce(h ->> 'vo', '')), ''); end if;
  if h ? 'remarks' then n.remarks := nullif(btrim(coalesce(h ->> 'remarks', '')), ''); end if;
  if h ? 'period' and nullif(btrim(coalesce(h ->> 'period', '')), '') is not null then
    n.period := btrim(h ->> 'period');
  end if;

  if n.kind not in ('scenes', 'products', 'story') then return jsonb_build_object('error', 'bad-kind'); end if;
  if n.period !~ '^\d{4}-(0[1-9]|1[0-2])$' or n.period not between '2023-08' and '2099-12' then
    return jsonb_build_object('error', 'bad-period');
  end if;
  if length(n.title) > 200 then return jsonb_build_object('error', 'bad-title'); end if;
  if n.reference_url is not null and (n.reference_url !~ '^https://' or length(n.reference_url) > 1000) then
    return jsonb_build_object('error', 'bad-link');
  end if;
  if n.duration_minutes is not null and n.duration_minutes not between 5 and 1440 then
    return jsonb_build_object('error', 'bad-duration');
  end if;
  if n.shoot_on is not null and n.shoot_on not between date '2023-08-14' and date '2099-12-31' then
    return jsonb_build_object('error', 'bad-date');
  end if;
  if greatest(length(coalesce(n.platform, '')), length(coalesce(n.language, '')), length(coalesce(n.venue, ''))) > 200
     or greatest(length(coalesce(n.cast_names, '')), length(coalesce(n.context, '')),
                 length(coalesce(n.vo, '')), length(coalesce(n.remarks, ''))) > 4000 then
    return jsonb_build_object('error', 'too-long');
  end if;
  if p_scenes is not null then
    if jsonb_typeof(p_scenes) <> 'array' then return jsonb_build_object('error', 'bad-scenes'); end if;
    if jsonb_array_length(p_scenes) > 60 then return jsonb_build_object('error', 'too-many'); end if;
    if exists (select 1 from jsonb_array_elements(p_scenes) e
                where length(coalesce(e.value ->> 'visual', '')) > 2000
                   or length(coalesce(e.value ->> 'line', '')) > 2000) then
      return jsonb_build_object('error', 'too-long');
    end if;
  end if;

  if n.period is distinct from v.period then
    perform pg_advisory_xact_lock(hashtext('video_script:' || v.client_id::text || ':' || n.period));
    select min(g) into n.seq from generate_series(1, 99) g
     where not exists (select 1 from public.video_scripts s where s.client_id = v.client_id and s.period = n.period and s.seq = g);
    if n.seq is null then return jsonb_build_object('error', 'too-many'); end if;
    select e.id into n.engagement_id from public.ops_engagements e where e.client_id = v.client_id and e.period = n.period limit 1;
    v_moves := v_moves || ('Month: ' || replace(to_char(to_date(v.period, 'YYYY-MM'), 'Mon YYYY'), 'Sep ', 'Sept ')
                           || ' → ' || replace(to_char(to_date(n.period, 'YYYY-MM'), 'Mon YYYY'), 'Sep ', 'Sept ')
                           || ' · ' || v.code || ' → ' || substr(n.period, 3, 2) || substr(n.period, 6, 2) || 'VS' || lpad(n.seq::text, 2, '0'));
  end if;
  v_kindw := case n.kind when 'products' then 'Products and context' when 'story' then 'Hook and story' else 'Context' end;
  if n.kind is distinct from v.kind then
    v_creat := true;
    v_moves := v_moves || ('Kind: ' || case v.kind when 'scenes' then 'Detailed scenes' when 'products' then 'Products and scenes' else 'Story and voice-over' end
                           || ' → ' || case n.kind when 'scenes' then 'Detailed scenes' when 'products' then 'Products and scenes' else 'Story and voice-over' end);
  end if;
  if n.title is distinct from v.title then
    v_creat := true;
    v_moves := v_moves || ('Title: ' || coalesce(nullif(v.title, ''), 'not set') || ' → ' || coalesce(nullif(n.title, ''), 'not set'));
  end if;
  if n.reference_url is distinct from v.reference_url then
    v_creat := true;
    v_moves := v_moves || ('Reference: ' || coalesce(v.reference_url, 'not set') || ' → ' || coalesce(n.reference_url, 'not set'));
  end if;
  if n.platform is distinct from v.platform then
    v_moves := v_moves || ('Platform: ' || coalesce(v.platform, 'not set') || ' → ' || coalesce(n.platform, 'not set'));
  end if;
  if n.language is distinct from v.language then
    v_moves := v_moves || ('Language: ' || coalesce(v.language, 'not set') || ' → ' || coalesce(n.language, 'not set'));
  end if;
  if n.shoot_on is distinct from v.shoot_on then
    v_moves := v_moves || ('Shooting date: '
      || coalesce(replace(to_char(v.shoot_on, 'FMDD Mon YYYY'), 'Sep ', 'Sept '), 'not set') || ' → '
      || coalesce(replace(to_char(n.shoot_on, 'FMDD Mon YYYY'), 'Sep ', 'Sept '), 'not set'));
  end if;
  if n.shoot_time is distinct from v.shoot_time then
    v_moves := v_moves || ('Shooting time: ' || coalesce(to_char(v.shoot_time, 'FMHH12:MI am'), 'not set')
                           || ' → ' || coalesce(to_char(n.shoot_time, 'FMHH12:MI am'), 'not set'));
  end if;
  if n.venue is distinct from v.venue then
    v_moves := v_moves || ('Venue: ' || coalesce(v.venue, 'not set') || ' → ' || coalesce(n.venue, 'not set'));
  end if;
  if n.duration_minutes is distinct from v.duration_minutes then
    v_moves := v_moves || ('Duration: ' || coalesce(v.duration_minutes || ' min', 'not set') || ' → '
                           || coalesce(n.duration_minutes || ' min', 'not set'));
  end if;
  if n.cast_names is distinct from v.cast_names then v_moves := v_moves || 'Cast'::text; end if;
  if n.context is distinct from v.context then v_creat := true; v_moves := v_moves || v_kindw; end if;
  if n.vo is distinct from v.vo then v_creat := true; v_moves := v_moves || 'Script (read here)'::text; end if;
  if n.remarks is distinct from v.remarks then v_moves := v_moves || 'Notes'::text; end if;

  if p_scenes is not null then
    select coalesce(jsonb_agg(jsonb_build_object('visual', coalesce(sc.visual, ''), 'line', coalesce(sc.line, ''))
                              order by sc.position), '[]'::jsonb)
      into v_old_sc from public.video_script_scenes sc where sc.script_id = p_id;
    select coalesce(jsonb_agg(jsonb_build_object('visual', btrim(coalesce(e.value ->> 'visual', '')),
                                                 'line', btrim(coalesce(e.value ->> 'line', '')))
                              order by e.ord), '[]'::jsonb)
      into v_new_sc from jsonb_array_elements(p_scenes) with ordinality as e(value, ord);
    if v_new_sc is distinct from v_old_sc then
      v_creat := true;
      v_moves := v_moves || ('Scenes' || case when jsonb_array_length(v_old_sc) <> jsonb_array_length(v_new_sc)
                                              then ': ' || jsonb_array_length(v_old_sc) || ' → ' || jsonb_array_length(v_new_sc)
                                              else '' end);
      for v_row in select e.value from jsonb_array_elements(p_scenes) e loop
        v_pos := v_pos + 1;
        v_sid := null;
        if coalesce(v_row ->> 'id', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
          select sc.id into v_sid from public.video_script_scenes sc
           where sc.id = (v_row ->> 'id')::uuid and sc.script_id = p_id;
        end if;
        if v_sid is null then
          insert into public.video_script_scenes (script_id, position, visual, line)
          values (p_id, v_pos, nullif(btrim(coalesce(v_row ->> 'visual', '')), ''),
                  nullif(btrim(coalesce(v_row ->> 'line', '')), ''))
          returning id into v_sid;
        else
          update public.video_script_scenes sc
             set position = v_pos,
                 visual = nullif(btrim(coalesce(v_row ->> 'visual', '')), ''),
                 line = nullif(btrim(coalesce(v_row ->> 'line', '')), '')
           where sc.id = v_sid;
        end if;
        v_keep := v_keep || v_sid;
      end loop;
      delete from public.video_script_scenes sc where sc.script_id = p_id and not (sc.id = any (v_keep));
    end if;
  end if;

  if coalesce(array_length(v_moves, 1), 0) = 0 then
    return jsonb_build_object('ok', true, 'version', v.version, 'round', v.round, 'changed', false);
  end if;
  update public.video_scripts s
     set kind = n.kind, title = n.title, reference_url = n.reference_url, platform = n.platform,
         language = n.language, shoot_on = n.shoot_on, shoot_time = n.shoot_time, venue = n.venue,
         duration_minutes = n.duration_minutes, cast_names = n.cast_names, context = n.context,
         vo = n.vo, remarks = n.remarks, period = n.period, seq = n.seq, engagement_id = n.engagement_id,
         version = v.version + 1, updated_at = now(), updated_by_name = me.name
   where s.id = p_id;
  select c.name into v_client from public.clients c where c.id = v.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.saved', v_client,
          public.video_script_label(n) || ' · ' || array_to_string(v_moves, '; '));
  return jsonb_build_object('ok', true, 'version', v.version + 1, 'round', v.round, 'changed', true,
    'code', substr(n.period, 3, 2) || substr(n.period, 6, 2) || 'VS' || lpad(n.seq::text, 2, '0'));
end $$;
revoke all on function public.video_script_save(uuid, jsonb, jsonb, integer) from public, anon;
grant execute on function public.video_script_save(uuid, jsonb, jsonb, integer) to authenticated;

create or replace function public.video_script_delete(p_id uuid, p_typed text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  s    public.video_scripts;
  v_cl text;
begin
  if me.id is null or not public.allowed('scripts', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.video_scripts x where x.id = p_id for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(s.client_id, 'manage') then return jsonb_build_object('error', 'client-scope'); end if;
  if lower(btrim(coalesce(p_typed, ''))) <> lower(coalesce(nullif(btrim(s.title), ''), s.code)) then
    return jsonb_build_object('error', 'name');
  end if;
  select c.name into v_cl from public.clients c where c.id = s.client_id;
  delete from public.video_scripts x where x.id = p_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.deleted', v_cl, public.video_script_label(s));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.video_script_delete(uuid, text) from public, anon;
grant execute on function public.video_script_delete(uuid, text) to authenticated;

/* On site, from the client link: a shared script's scene ticked shot and
   its clip number (VC#); with no scene, the voice-over's. Filed under the
   client by `Client link`. */
create or replace function public.script_shot_link(p_token text, p_script uuid, p_scene uuid, p_on boolean,
                                                   p_vc text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_cl   public.clients;
  s      public.video_scripts;
  sc     public.video_script_scenes;
  v_was  boolean;
begin
  select * into v_cl from public.clients c
   where c.script_key = p_token and p_token is not null and c.active;
  if v_cl.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into s from public.video_scripts x
   where x.id = p_script and x.client_id = v_cl.id and x.status = 'shared' for update;
  if s.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if p_vc is not null and length(p_vc) > 40 then return jsonb_build_object('error', 'too-long'); end if;
  if p_scene is null then
    v_was := s.vo_shot_at is not null;
    update public.video_scripts x
       set vo_shot_at = case when p_on is null then x.vo_shot_at when p_on then coalesce(x.vo_shot_at, now()) end,
           vo_shot_by = case when p_on is null then x.vo_shot_by when p_on then coalesce(x.vo_shot_by, 'Client link') end,
           vo_vc = case when p_vc is null then x.vo_vc else nullif(btrim(p_vc), '') end
     where x.id = p_script;
    if p_on is not null and p_on <> v_was then
      insert into public.activity_log (actor, action, subject, detail)
      values ('Client link', 'script.shot', v_cl.name, public.video_script_label(s) || ' · Script (read here) '
              || case when p_on then 'shot' else 'not shot' end);
    end if;
    return jsonb_build_object('ok', true);
  end if;
  select * into sc from public.video_script_scenes y where y.id = p_scene and y.script_id = p_script for update;
  if sc.id is null then return jsonb_build_object('error', 'not_found'); end if;
  v_was := sc.shot_at is not null;
  update public.video_script_scenes y
     set shot_at = case when p_on is null then y.shot_at when p_on then coalesce(y.shot_at, now()) end,
         shot_by = case when p_on is null then y.shot_by when p_on then coalesce(y.shot_by, 'Client link') end,
         vc = case when p_vc is null then y.vc else nullif(btrim(p_vc), '') end
   where y.id = p_scene;
  if p_on is not null and p_on <> v_was then
    insert into public.activity_log (actor, action, subject, detail)
    values ('Client link', 'script.shot', v_cl.name, public.video_script_label(s) || ' · Scene ' || sc.position || ' '
            || case when p_on then 'shot' else 'not shot' end);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.script_shot_link(text, uuid, uuid, boolean, text) from public;
grant execute on function public.script_shot_link(text, uuid, uuid, boolean, text) to anon;
grant execute on function public.script_shot_link(text, uuid, uuid, boolean, text) to authenticated;

/* The client link: the shared scripts, newest month first, each with its
   code, its scenes, their clip numbers and Shot ticks. Never a colleague's
   name, who ticked, a version or a decision. */
create or replace function public.get_scripts(p_token text)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  v_cl public.clients;
begin
  select * into v_cl from public.clients c
   where c.script_key = p_token and p_token is not null and c.active;
  if v_cl.id is null then return jsonb_build_object('error', 'not_found'); end if;
  return jsonb_build_object(
    'client', jsonb_build_object('name', v_cl.name, 'logo_url', v_cl.logo_url),
    'scripts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'code', s.code, 'period', s.period, 'kind', s.kind,
               'title', s.title, 'reference_url', s.reference_url, 'platform', s.platform,
               'language', s.language, 'shoot_on', s.shoot_on, 'shoot_time', s.shoot_time,
               'venue', s.venue, 'duration_minutes', s.duration_minutes, 'cast_names', s.cast_names,
               'context', s.context, 'vo', s.vo, 'vo_vc', s.vo_vc, 'vo_shot', s.vo_shot_at is not null,
               'remarks', s.remarks, 'shared_at', s.shared_at, 'updated_at', s.updated_at,
               'scenes', coalesce((select jsonb_agg(jsonb_build_object('id', sc.id, 'position', sc.position,
                                                     'visual', sc.visual, 'line', sc.line, 'vc', sc.vc,
                                                     'shot', sc.shot_at is not null)
                                                     order by sc.position)
                                     from public.video_script_scenes sc where sc.script_id = s.id), '[]'::jsonb))
             order by s.period desc, s.seq)
        from public.video_scripts s
       where s.client_id = v_cl.id and s.status = 'shared'), '[]'::jsonb));
end $$;
revoke all on function public.get_scripts(text) from public;
grant execute on function public.get_scripts(text) to anon;
grant execute on function public.get_scripts(text) to authenticated;

-- The client no longer decides on a script (the user, 2026-10-09).
create or replace function public.script_decide(p_token text, p_script uuid, p_decision text,
                                                p_name text, p_note text default null)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('error', 'closed')
$$;
revoke all on function public.script_decide(text, uuid, text, text, text) from public;
grant execute on function public.script_decide(text, uuid, text, text, text) to anon;
grant execute on function public.script_decide(text, uuid, text, text, text) to authenticated;

-- END OF SCRIPTS BY MONTH -----------------------------------------------------

select public.functions_tidy();
