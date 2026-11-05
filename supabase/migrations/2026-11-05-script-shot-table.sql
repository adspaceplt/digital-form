-- SCRIPT SHOT TABLE — a video script as the crew films it: each scene's
-- timing, shot size, angle, camera move, on-screen text and sound; the
-- script's brief and production limits; what it stands on (core message,
-- hook, cast, locations, props, music); and the AI review read with it.
-- 2026-11-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/vssql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-11-05: the Video Script Generator spec, "Full
-- shot table"; the crew's limits "vary … we have multiple scenarios and
-- different projects", so they are the script's own)
--   1. `video_script_scenes` gains `t_from` and `t_to` (seconds into the
--      video, 0 to 600, the end after the start), `shot_size`, `angle`,
--      `camera_move` (60 each), `on_screen` (120) and `sound` (200).
--   2. `video_scripts` gains `aspect` (9:16, 1:1, 16:9), `length_seconds`
--      (5 to 600), `brief` (the brief the script is written to: offer,
--      objective, audience, key message, call to action, must include,
--      must avoid, tone, format, and the shoot's limits: locations, cast,
--      shoot hours), `plan` (core message, concept, hook, cast, locations,
--      props, music, call to action) and `review` with `review_version`
--      (the AI reviewer's last reading, kept as the colleague saved it,
--      and the version it was saved at).
--   3. `video_script_save` takes them (`p_head` aspect, length_seconds,
--      brief, plan, review; each scene its shot fields), refusing a value
--      out of shape (`bad-aspect`, `bad-length`, `bad-brief`, `bad-plan`,
--      `bad-review`, `bad-time`, `too-long`), and files them: aspect and
--      length from and to, the brief, plan and scenes by name, the review
--      by its verdict.
--   4. `video_script_new` copies the aspect, length and brief with the
--      header (Add script).
--   5. `get_scripts` sends the aspect, length, plan and each scene's shot
--      fields; never the brief or the review, which are the team's.
--
-- ROLLBACK
--   Pages first, then restate video_script_new, video_script_save and
--   get_scripts from the SCRIPTS BY MONTH band and get_scripts from the
--   SCRIPT SHOTS INTERNAL band. The columns may stay.
-- ===========================================================================

alter table public.video_script_scenes add column if not exists t_from integer;
alter table public.video_script_scenes add column if not exists t_to integer;
alter table public.video_script_scenes add column if not exists shot_size text;
alter table public.video_script_scenes add column if not exists angle text;
alter table public.video_script_scenes add column if not exists camera_move text;
alter table public.video_script_scenes add column if not exists on_screen text;
alter table public.video_script_scenes add column if not exists sound text;
alter table public.video_scripts add column if not exists aspect text;
alter table public.video_scripts add column if not exists length_seconds integer;
alter table public.video_scripts add column if not exists brief jsonb not null default '{}'::jsonb;
alter table public.video_scripts add column if not exists plan jsonb not null default '{}'::jsonb;
alter table public.video_scripts add column if not exists review jsonb;
alter table public.video_scripts add column if not exists review_version integer;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'video_script_scenes_time_shape') then
    alter table public.video_script_scenes add constraint video_script_scenes_time_shape
      check ((t_from is null or t_from between 0 and 600) and (t_to is null or t_to between 1 and 600)
             and (t_from is null or t_to is null or t_to > t_from));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'video_scripts_aspect_shape') then
    alter table public.video_scripts add constraint video_scripts_aspect_shape
      check ((aspect is null or aspect in ('9:16', '1:1', '16:9'))
             and (length_seconds is null or length_seconds between 5 and 600));
  end if;
end $$;

/* The brief a script is written to, held to its keys: words of 500 at most,
   the objective and the format from their lists, the limits whole numbers.
   Answers the brief as kept, or null where any part is out of shape. */
create or replace function public.video_script_brief(p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  k   text;
  v   jsonb;
  out jsonb := '{}'::jsonb;
  n   integer;
begin
  if p is null or jsonb_typeof(p) = 'null' then return '{}'::jsonb; end if;
  if jsonb_typeof(p) <> 'object' then return null; end if;
  for k, v in select e.key, e.value from jsonb_each(p) e loop
    if jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then continue; end if;
    if k in ('offer', 'audience', 'key_message', 'cta', 'must_include', 'must_avoid', 'tone') then
      if jsonb_typeof(v) <> 'string' or length(v #>> '{}') > 500 then return null; end if;
      out := out || jsonb_build_object(k, btrim(v #>> '{}'));
    elsif k = 'objective' then
      if (v #>> '{}') not in ('awareness', 'traffic', 'leads', 'sales', 'app_install') then return null; end if;
      out := out || jsonb_build_object(k, v #>> '{}');
    elsif k = 'format' then
      if (v #>> '{}') not in ('talking_head', 'skit', 'ugc', 'demo', 'testimonial', 'montage') then return null; end if;
      out := out || jsonb_build_object(k, v #>> '{}');
    elsif k in ('max_locations', 'max_cast', 'max_shoot_hours') then
      if (v #>> '{}') !~ '^\d{1,3}$' then return null; end if;
      n := (v #>> '{}')::integer;
      if n < 1 or n > (case k when 'max_locations' then 10 when 'max_cast' then 50 else 24 end) then return null; end if;
      out := out || jsonb_build_object(k, n);
    else
      return null;
    end if;
  end loop;
  return out;
end $$;
revoke all on function public.video_script_brief(jsonb) from public, anon, authenticated;

/* What a script stands on, held to its keys, words of 2,000 at most. */
create or replace function public.video_script_plan(p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  k   text;
  v   jsonb;
  out jsonb := '{}'::jsonb;
begin
  if p is null or jsonb_typeof(p) = 'null' then return '{}'::jsonb; end if;
  if jsonb_typeof(p) <> 'object' then return null; end if;
  for k, v in select e.key, e.value from jsonb_each(p) e loop
    if jsonb_typeof(v) = 'null' or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then continue; end if;
    if k not in ('core_message', 'concept', 'hook', 'cast', 'locations', 'props', 'music', 'cta')
       or jsonb_typeof(v) <> 'string' or length(v #>> '{}') > 2000 then
      return null;
    end if;
    out := out || jsonb_build_object(k, btrim(v #>> '{}'));
  end loop;
  return out;
end $$;
revoke all on function public.video_script_plan(jsonb) from public, anon, authenticated;

/* The names of a brief's or a plan's parts that changed, in the order
   given (`p_words`: [[key, name], …]). */
create or replace function public.video_script_parts_moved(p_old jsonb, p_new jsonb, p_words jsonb)
returns text language sql immutable set search_path = public as $$
  select string_agg(w.value ->> 1, ', ' order by w.ordinality)
    from jsonb_array_elements(p_words) with ordinality w
   where (coalesce(p_old, '{}'::jsonb) -> (w.value ->> 0)) is distinct from (coalesce(p_new, '{}'::jsonb) -> (w.value ->> 0))
$$;
revoke all on function public.video_script_parts_moved(jsonb, jsonb, jsonb) from public, anon, authenticated;

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
                                    shoot_time, venue, duration_minutes, cast_names, aspect, length_seconds, brief,
                                    idem_key, created_by, created_by_name, updated_by_name)
  values (v_cl.id, v_per, v_seq, v_eng, v_kind, f.platform, f.language, f.shoot_on, f.shoot_time, f.venue,
          f.duration_minutes, f.cast_names, f.aspect, f.length_seconds, coalesce(f.brief, '{}'::jsonb),
          nullif(btrim(coalesce(p_idem, '')), ''), me.id, me.name, me.name)
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

/* One save for the whole script: the header facts named in `p_head` (a key
   left out keeps its value; `period` moves it to that month at its lowest
   free number; `review` is kept with the version it is saved at) and, where
   `p_scenes` is given, the scene rows in order ({id, visual, line, t_from,
   t_to, shot_size, angle, camera_move, on_screen, sound}; a row named by its
   id keeps its clip number and its tick). Files what changed, from and to
   for a short value, by name for the long ones. */
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
  v_old_sc  jsonb;
  v_new_sc  jsonb;
  v_row     jsonb;
  v_pos     integer := 0;
  v_keep    uuid[] := '{}';
  v_sid     uuid;
  v_kindw   text;
  v_parts   text;
  v_rev_set boolean := false;
  v_rev     jsonb;
  v_ver     integer;
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
  if h ? 'aspect' then n.aspect := nullif(btrim(coalesce(h ->> 'aspect', '')), ''); end if;
  if h ? 'length_seconds' then
    if coalesce(h ->> 'length_seconds', '') !~ '^\d{0,3}$' then return jsonb_build_object('error', 'bad-length'); end if;
    n.length_seconds := nullif(h ->> 'length_seconds', '')::integer;
  end if;
  if h ? 'brief' then
    n.brief := public.video_script_brief(h -> 'brief');
    if n.brief is null then return jsonb_build_object('error', 'bad-brief'); end if;
  end if;
  if h ? 'plan' then
    n.plan := public.video_script_plan(h -> 'plan');
    if n.plan is null then return jsonb_build_object('error', 'bad-plan'); end if;
  end if;
  if h ? 'review' then
    v_rev_set := true;
    v_rev := case when jsonb_typeof(h -> 'review') = 'object' then h -> 'review' end;
    if jsonb_typeof(h -> 'review') not in ('object', 'null')
       or (v_rev is not null and (coalesce(v_rev ->> 'verdict', '') not in ('pass', 'fail')
                                  or jsonb_typeof(coalesce(v_rev -> 'issues', '[]'::jsonb)) <> 'array'
                                  or length(v_rev::text) > 40000)) then
      return jsonb_build_object('error', 'bad-review');
    end if;
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
  if n.aspect is not null and n.aspect not in ('9:16', '1:1', '16:9') then return jsonb_build_object('error', 'bad-aspect'); end if;
  if n.length_seconds is not null and n.length_seconds not between 5 and 600 then
    return jsonb_build_object('error', 'bad-length');
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
                   or length(coalesce(e.value ->> 'line', '')) > 2000
                   or greatest(length(coalesce(e.value ->> 'shot_size', '')), length(coalesce(e.value ->> 'angle', '')),
                               length(coalesce(e.value ->> 'camera_move', ''))) > 60
                   or length(coalesce(e.value ->> 'on_screen', '')) > 120
                   or length(coalesce(e.value ->> 'sound', '')) > 200) then
      return jsonb_build_object('error', 'too-long');
    end if;
    if exists (select 1 from jsonb_array_elements(p_scenes) e
                where coalesce(e.value ->> 't_from', '') !~ '^\d{0,3}$'
                   or coalesce(e.value ->> 't_to', '') !~ '^\d{0,3}$'
                   or nullif(e.value ->> 't_from', '')::integer > 600
                   or nullif(e.value ->> 't_to', '')::integer not between 1 and 600
                   or nullif(e.value ->> 't_to', '')::integer <= nullif(e.value ->> 't_from', '')::integer) then
      return jsonb_build_object('error', 'bad-time');
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
    v_moves := v_moves || ('Kind: ' || case v.kind when 'scenes' then 'Detailed scenes' when 'products' then 'Products and scenes' else 'Story and voice-over' end
                           || ' → ' || case n.kind when 'scenes' then 'Detailed scenes' when 'products' then 'Products and scenes' else 'Story and voice-over' end);
  end if;
  if n.title is distinct from v.title then
    v_moves := v_moves || ('Title: ' || coalesce(nullif(v.title, ''), 'not set') || ' → ' || coalesce(nullif(n.title, ''), 'not set'));
  end if;
  if n.reference_url is distinct from v.reference_url then
    v_moves := v_moves || ('Reference: ' || coalesce(v.reference_url, 'not set') || ' → ' || coalesce(n.reference_url, 'not set'));
  end if;
  if n.platform is distinct from v.platform then
    v_moves := v_moves || ('Platform: ' || coalesce(v.platform, 'not set') || ' → ' || coalesce(n.platform, 'not set'));
  end if;
  if n.language is distinct from v.language then
    v_moves := v_moves || ('Language: ' || coalesce(v.language, 'not set') || ' → ' || coalesce(n.language, 'not set'));
  end if;
  if n.aspect is distinct from v.aspect then
    v_moves := v_moves || ('Aspect ratio: ' || coalesce(v.aspect, 'not set') || ' → ' || coalesce(n.aspect, 'not set'));
  end if;
  if n.length_seconds is distinct from v.length_seconds then
    v_moves := v_moves || ('Video length: ' || coalesce(v.length_seconds || 's', 'not set') || ' → '
                           || coalesce(n.length_seconds || 's', 'not set'));
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
  if n.brief is distinct from v.brief then
    v_parts := public.video_script_parts_moved(v.brief, n.brief,
      '[["offer","Product or offer"],["objective","Objective"],["audience","Target audience"],["key_message","Key message"],["cta","Call to action"],["must_include","Must include"],["must_avoid","Must avoid"],["tone","Tone"],["format","Format"],["max_locations","Location limit"],["max_cast","Cast limit"],["max_shoot_hours","Hour limit"]]'::jsonb);
    v_moves := v_moves || ('Brief: ' || coalesce(v_parts, 'changed'));
  end if;
  if n.plan is distinct from v.plan then
    v_parts := public.video_script_parts_moved(v.plan, n.plan,
      '[["core_message","Core message"],["concept","Concept"],["hook","Hook"],["cast","Cast roles"],["locations","Locations"],["props","Props"],["music","Music mood"],["cta","Call to action in the video"]]'::jsonb);
    v_moves := v_moves || ('Plan: ' || coalesce(v_parts, 'changed'));
  end if;
  if n.context is distinct from v.context then v_moves := v_moves || v_kindw; end if;
  if n.vo is distinct from v.vo then v_moves := v_moves || 'Script (read here)'::text; end if;
  if n.remarks is distinct from v.remarks then v_moves := v_moves || 'Notes'::text; end if;

  if p_scenes is not null then
    select coalesce(jsonb_agg(jsonb_build_object('visual', coalesce(sc.visual, ''), 'line', coalesce(sc.line, ''),
                                                 't_from', sc.t_from, 't_to', sc.t_to,
                                                 'shot_size', coalesce(sc.shot_size, ''), 'angle', coalesce(sc.angle, ''),
                                                 'camera_move', coalesce(sc.camera_move, ''), 'on_screen', coalesce(sc.on_screen, ''),
                                                 'sound', coalesce(sc.sound, ''))
                              order by sc.position), '[]'::jsonb)
      into v_old_sc from public.video_script_scenes sc where sc.script_id = p_id;
    select coalesce(jsonb_agg(jsonb_build_object('visual', btrim(coalesce(e.value ->> 'visual', '')),
                                                 'line', btrim(coalesce(e.value ->> 'line', '')),
                                                 't_from', nullif(e.value ->> 't_from', '')::integer,
                                                 't_to', nullif(e.value ->> 't_to', '')::integer,
                                                 'shot_size', btrim(coalesce(e.value ->> 'shot_size', '')),
                                                 'angle', btrim(coalesce(e.value ->> 'angle', '')),
                                                 'camera_move', btrim(coalesce(e.value ->> 'camera_move', '')),
                                                 'on_screen', btrim(coalesce(e.value ->> 'on_screen', '')),
                                                 'sound', btrim(coalesce(e.value ->> 'sound', '')))
                              order by e.ord), '[]'::jsonb)
      into v_new_sc from jsonb_array_elements(p_scenes) with ordinality as e(value, ord);
    if v_new_sc is distinct from v_old_sc then
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
          values (p_id, v_pos, null, null)
          returning id into v_sid;
        end if;
        update public.video_script_scenes sc
           set position = v_pos,
               visual = nullif(btrim(coalesce(v_row ->> 'visual', '')), ''),
               line = nullif(btrim(coalesce(v_row ->> 'line', '')), ''),
               t_from = nullif(v_row ->> 't_from', '')::integer,
               t_to = nullif(v_row ->> 't_to', '')::integer,
               shot_size = nullif(btrim(coalesce(v_row ->> 'shot_size', '')), ''),
               angle = nullif(btrim(coalesce(v_row ->> 'angle', '')), ''),
               camera_move = nullif(btrim(coalesce(v_row ->> 'camera_move', '')), ''),
               on_screen = nullif(btrim(coalesce(v_row ->> 'on_screen', '')), ''),
               sound = nullif(btrim(coalesce(v_row ->> 'sound', '')), '')
         where sc.id = v_sid;
        v_keep := v_keep || v_sid;
      end loop;
      delete from public.video_script_scenes sc where sc.script_id = p_id and not (sc.id = any (v_keep));
    end if;
  end if;
  if v_rev_set and v_rev is distinct from v.review then
    v_moves := v_moves || ('AI review: ' || case when v_rev is null then 'removed'
                                                 when v_rev ->> 'verdict' = 'pass' then 'passed'
                                                 else 'check needed' end);
  end if;

  if coalesce(array_length(v_moves, 1), 0) = 0 then
    return jsonb_build_object('ok', true, 'version', v.version, 'round', v.round, 'changed', false);
  end if;
  v_ver := v.version + 1;
  update public.video_scripts s
     set kind = n.kind, title = n.title, reference_url = n.reference_url, platform = n.platform,
         language = n.language, shoot_on = n.shoot_on, shoot_time = n.shoot_time, venue = n.venue,
         duration_minutes = n.duration_minutes, cast_names = n.cast_names, context = n.context,
         vo = n.vo, remarks = n.remarks, period = n.period, seq = n.seq, engagement_id = n.engagement_id,
         aspect = n.aspect, length_seconds = n.length_seconds, brief = n.brief, plan = n.plan,
         review = case when v_rev_set then v_rev else s.review end,
         review_version = case when v_rev_set then case when v_rev is null then null else v_ver end else s.review_version end,
         version = v_ver, updated_at = now(), updated_by_name = me.name
   where s.id = p_id;
  select c.name into v_client from public.clients c where c.id = v.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.saved', v_client,
          public.video_script_label(n) || ' · ' || array_to_string(v_moves, '; '));
  return jsonb_build_object('ok', true, 'version', v_ver, 'round', v.round, 'changed', true,
    'code', substr(n.period, 3, 2) || substr(n.period, 6, 2) || 'VS' || lpad(n.seq::text, 2, '0'));
end $$;
revoke all on function public.video_script_save(uuid, jsonb, jsonb, integer) from public, anon;
grant execute on function public.video_script_save(uuid, jsonb, jsonb, integer) to authenticated;

/* The client link: each published script's facts, its plan, its context,
   voice-over, scenes with their shot fields, and notes. Never the brief or
   the AI review, a clip number, a tick, a colleague's name or a version. */
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
               'aspect', s.aspect, 'length_seconds', s.length_seconds, 'plan', s.plan,
               'context', s.context, 'vo', s.vo, 'remarks', s.remarks,
               'shared_at', s.shared_at, 'updated_at', s.updated_at,
               'scenes', coalesce((select jsonb_agg(jsonb_build_object('id', sc.id, 'position', sc.position,
                                                     'visual', sc.visual, 'line', sc.line,
                                                     't_from', sc.t_from, 't_to', sc.t_to,
                                                     'shot_size', sc.shot_size, 'angle', sc.angle,
                                                     'camera_move', sc.camera_move, 'on_screen', sc.on_screen,
                                                     'sound', sc.sound)
                                                     order by sc.position)
                                     from public.video_script_scenes sc where sc.script_id = s.id), '[]'::jsonb))
             order by s.period desc, s.seq)
        from public.video_scripts s
       where s.client_id = v_cl.id and s.status = 'shared'), '[]'::jsonb));
end $$;
revoke all on function public.get_scripts(text) from public;
grant execute on function public.get_scripts(text) to anon;
grant execute on function public.get_scripts(text) to authenticated;

-- END OF SCRIPT SHOT TABLE ----------------------------------------------------

select public.functions_tidy();
