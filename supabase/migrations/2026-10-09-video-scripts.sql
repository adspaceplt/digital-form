-- ===========================================================================
-- VIDEO SCRIPTS — a shoot's scripts, one a video, read and approved by the
-- client online and ticked by the crew on the day.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/vssql.js compares the
-- two.
--
-- WHAT CHANGED
--   The user (2026-10-09): "a script table covers one video, hence there is
--   a # … three different types of script, detailed scenes / products +
--   scenes / story + VO. VC# is the video clip number on camera … one
--   digital similar as content review able to view online, another is export
--   pdf for on-site use."
--   1. `video_scripts`: one video's script. Its kind (`scenes` Detailed
--      scenes, `products` Products and scenes, `story` Story and voice-over),
--      its number in its shoot (`series_id`, `video_no`: V1, V2…), the
--      header (title, reference link, platform, language, shooting date and
--      time, venue, estimated duration, cast), the context a products or
--      story script opens on, the voice-over a story script is read from
--      (`vo`, with its own clip number and tick), and the notes. A draft
--      until shared; `round` counts what the client decided on (kind, title,
--      reference, context, script, scenes): a change to one of those after
--      the client decided on the round is the next round, and a change
--      before any decision is a correction.
--   2. `video_script_scenes`: the scenes in order, each what is seen
--      (`visual`) and, on a detailed script, what is said (`line`), with the
--      crew's clip number (`vc`) and tick (`shot_at`, `shot_by`). A scene
--      moved or reworded keeps its clip number and its tick.
--   3. `video_script_reviews`: the client's decision on a round (Approved,
--      Changes requested with a note) under the name they typed, never
--      removed.
--   4. Video Scripts is a section of its own on the ladder (`scripts`), every
--      group starting at its Content Review level, once. The tables read at
--      View under the client scope rule; every write is a function:
--      `video_script_create(p_client, p_kind, p_from, p_idem)` (`p_from` a
--      video of the shoot: the next number, its header copied, the script
--      empty; the same press twice the same video),
--      `video_script_save(p_id, p_head, p_scenes, p_version)` (one save for
--      the whole script, filed from and to, `stale` with the row as it
--      stands), `video_script_share(p_ids, p_on)`,
--      `video_script_shot(p_script, p_scene, p_on, p_vc)` (on the day; never
--      a round), `video_script_delete(p_id, p_typed)` (Full Access, the title
--      typed back, else V and the number) and `script_link(p_client,
--      p_reset)` (the client's own key, `clients.script_key`, made on first
--      asking; a reset retires the old one). Each is filed under the client
--      (`script.*`, the Video Scripts tab).
--   5. The client's page (`/script/?k=`) reads only through
--      `get_scripts(p_token)` (the shared videos, their scenes, the decision
--      on the round on show and the request it answers; never a colleague's
--      name, a clip number, a tick or the version) and decides through
--      `script_decide(p_token, p_script, p_decision, p_name, p_note)`, which
--      tells the colleague who made the video
--      (`ops_notifications.script_id`, kind `script`, opening the script).
--      Both join `open_to_anon` (FUNCTION HYGIENE): run
--      2026-10-07-function-hygiene.sql again BEFORE this file, so the tidy
--      at its foot keeps them open.
--
-- ROLLBACK
--   Pages first (the section reads "This needs a database update."), then:
--     drop function if exists public.script_decide(text, uuid, text, text, text);
--     drop function if exists public.get_scripts(text);
--     drop function if exists public.video_script_delete(uuid, text);
--     drop function if exists public.video_script_shot(uuid, uuid, boolean, text);
--     drop function if exists public.video_script_share(uuid[], boolean);
--     drop function if exists public.script_link(uuid, boolean);
--     drop function if exists public.video_script_save(uuid, jsonb, jsonb, integer);
--     drop function if exists public.video_script_create(uuid, text, uuid, text);
--     drop function if exists public.video_script_label(public.video_scripts);
--     drop table if exists public.video_script_reviews, public.video_script_scenes, public.video_scripts;
--     alter table public.clients drop column if exists script_key;
--     alter table public.ops_notifications drop column if exists script_id;
--   and re-run ops_notifications_push and activity_section from the band
--   before this one.
-- ===========================================================================

create table if not exists public.video_scripts (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.clients(id) on delete cascade,
  series_id        uuid not null default gen_random_uuid(),
  video_no         integer not null default 1 check (video_no between 1 and 99),
  kind             text not null default 'scenes' check (kind in ('scenes', 'products', 'story')),
  title            text not null default '',
  reference_url    text check (reference_url is null or reference_url ~ '^https://'),
  platform         text,
  language         text,
  shoot_on         date,
  shoot_time       time,
  venue            text,
  duration_minutes integer check (duration_minutes is null or duration_minutes between 5 and 1440),
  cast_names       text,
  context          text,
  vo               text,
  vo_vc            text,
  vo_shot_at       timestamptz,
  vo_shot_by       text,
  remarks          text,
  status           text not null default 'draft' check (status in ('draft', 'shared')),
  shared_at        timestamptz,
  round            integer not null default 1,
  version          integer not null default 1,
  idem_key         text unique,
  created_by       uuid,
  created_by_name  text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by_name  text,
  unique (series_id, video_no)
);
create index if not exists video_scripts_client_idx on public.video_scripts(client_id, created_at desc);

create table if not exists public.video_script_scenes (
  id        uuid primary key default gen_random_uuid(),
  script_id uuid not null references public.video_scripts(id) on delete cascade,
  position  integer not null,
  visual    text,
  line      text,
  vc        text,
  shot_at   timestamptz,
  shot_by   text
);
create index if not exists video_script_scenes_script_idx on public.video_script_scenes(script_id, position);

create table if not exists public.video_script_reviews (
  id         uuid primary key default gen_random_uuid(),
  script_id  uuid not null references public.video_scripts(id) on delete cascade,
  round      integer not null,
  decision   text not null check (decision in ('approved', 'changes')),
  note       text,
  reviewer   text not null,
  created_at timestamptz not null default now()
);
create index if not exists video_script_reviews_script_idx on public.video_script_reviews(script_id, round, created_at desc);

alter table public.clients add column if not exists script_key text;
create unique index if not exists clients_script_key_idx on public.clients(script_key) where script_key is not null;
alter table public.ops_notifications add column if not exists script_id uuid;

alter table public.video_scripts enable row level security;
alter table public.video_script_scenes enable row level security;
alter table public.video_script_reviews enable row level security;

drop policy if exists video_scripts_read on public.video_scripts;
create policy video_scripts_read on public.video_scripts for select to authenticated
  using (public.allowed('scripts', 'view'));
drop policy if exists client_scope on public.video_scripts;
create policy client_scope on public.video_scripts as restrictive for select to authenticated
  using ((select public.client_scope_free('view')) or public.client_scope_ok('client', client_id, 'view'));
create or replace trigger client_scope_guard before insert or update on public.video_scripts
  for each row execute function public.client_scope_guard('client', 'client_id');

drop policy if exists video_script_scenes_read on public.video_script_scenes;
create policy video_script_scenes_read on public.video_script_scenes for select to authenticated
  using (public.allowed('scripts', 'view')
         and exists (select 1 from public.video_scripts s where s.id = video_script_scenes.script_id));
drop policy if exists video_script_reviews_read on public.video_script_reviews;
create policy video_script_reviews_read on public.video_script_reviews for select to authenticated
  using (public.allowed('scripts', 'view')
         and exists (select 1 from public.video_scripts s where s.id = video_script_reviews.script_id));

-- Every group starts at its Content Review level, once.
update public.team_roles
   set access = access || jsonb_build_object('scripts', coalesce(access ->> 'review', 'none'))
 where not (access ? 'scripts');
update public.team_members
   set access = access || jsonb_build_object('scripts', coalesce(access ->> 'review', 'none'))
 where not (access ? 'scripts');

-- V1 · Title, as every screen and the activity record name a video.
create or replace function public.video_script_label(p public.video_scripts)
returns text language sql immutable set search_path = public as $$
  select 'V' || p.video_no || coalesce(' · ' || nullif(btrim(p.title), ''), '')
$$;
revoke all on function public.video_script_label(public.video_scripts) from public, anon, authenticated;

create or replace function public.video_script_create(p_client uuid, p_kind text, p_from uuid default null,
                                                      p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  f      public.video_scripts;
  v_cl   public.clients;
  v_kind text;
  v_ser  uuid;
  v_no   integer;
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
    v_ser := f.series_id;
  else
    v_ser := gen_random_uuid();
  end if;
  select * into v_cl from public.clients c where c.id = coalesce(f.client_id, p_client);
  if v_cl.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(v_cl.id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  v_kind := coalesce(nullif(btrim(coalesce(p_kind, '')), ''), f.kind, 'scenes');
  if v_kind not in ('scenes', 'products', 'story') then return jsonb_build_object('error', 'bad-kind'); end if;
  perform pg_advisory_xact_lock(hashtext('video_script:' || v_ser::text));
  select coalesce(max(s.video_no), 0) + 1 into v_no from public.video_scripts s where s.series_id = v_ser;
  if v_no > 99 then return jsonb_build_object('error', 'too-many'); end if;
  insert into public.video_scripts (client_id, series_id, video_no, kind, platform, language, shoot_on,
                                    shoot_time, venue, duration_minutes, cast_names, idem_key,
                                    created_by, created_by_name, updated_by_name)
  values (v_cl.id, v_ser, v_no, v_kind, f.platform, f.language, f.shoot_on, f.shoot_time, f.venue,
          f.duration_minutes, f.cast_names, nullif(btrim(coalesce(p_idem, '')), ''), me.id, me.name, me.name)
  returning * into v_new;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.created', v_cl.name,
          public.video_script_label(v_new) || ' · '
          || case v_kind when 'scenes' then 'Detailed scenes' when 'products' then 'Products and scenes'
                         else 'Story and voice-over' end
          || case when f.id is not null then ' · header from V' || f.video_no else '' end);
  return jsonb_build_object('ok', true, 'id', v_new.id, 'series_id', v_ser, 'video_no', v_no);
end $$;
revoke all on function public.video_script_create(uuid, text, uuid, text) from public, anon;
grant execute on function public.video_script_create(uuid, text, uuid, text) to authenticated;

/* One save for the whole script: the header facts named in `p_head` (a key
   left out keeps its value) and, where `p_scenes` is given, the scene rows
   in order ({id, visual, line}; a row named by its id keeps its clip number
   and its tick). A change to what the client decides on, once they have
   decided on this round, starts the next round. Files what changed, from
   and to for a short value, by name for the long ones. */
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

  if n.kind not in ('scenes', 'products', 'story') then return jsonb_build_object('error', 'bad-kind'); end if;
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
  if v_creat and exists (select 1 from public.video_script_reviews r where r.script_id = p_id and r.round = v.round) then
    n.round := v.round + 1;
  end if;
  update public.video_scripts s
     set kind = n.kind, title = n.title, reference_url = n.reference_url, platform = n.platform,
         language = n.language, shoot_on = n.shoot_on, shoot_time = n.shoot_time, venue = n.venue,
         duration_minutes = n.duration_minutes, cast_names = n.cast_names, context = n.context,
         vo = n.vo, remarks = n.remarks, round = n.round, version = v.version + 1,
         updated_at = now(), updated_by_name = me.name
   where s.id = p_id;
  select c.name into v_client from public.clients c where c.id = v.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.saved', v_client,
          public.video_script_label(n) || ' · ' || array_to_string(v_moves, '; ')
          || case when n.round > v.round then ' · round ' || n.round else '' end);
  return jsonb_build_object('ok', true, 'version', v.version + 1, 'round', n.round, 'changed', true);
end $$;
revoke all on function public.video_script_save(uuid, jsonb, jsonb, integer) from public, anon;
grant execute on function public.video_script_save(uuid, jsonb, jsonb, integer) to authenticated;

-- The client's own link key, made on first asking; a reset retires the old.
create or replace function public.script_link(p_client uuid, p_reset boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  v_cl  public.clients;
  v_key text;
begin
  if me.id is null or not public.allowed('scripts', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_cl from public.clients c where c.id = p_client for update;
  if v_cl.id is null or not public.client_seen(v_cl.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if v_cl.script_key is not null and not coalesce(p_reset, false) then
    return jsonb_build_object('ok', true, 'key', v_cl.script_key);
  end if;
  if not public.allowed('scripts', 'work') or not public.client_seen(v_cl.id, 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  loop
    v_key := public.new_link_key();
    exit when not exists (select 1 from public.clients c where c.script_key = v_key);
  end loop;
  update public.clients c set script_key = v_key where c.id = p_client;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'script.link', v_cl.name,
          case when v_cl.script_key is null then 'Video Scripts link created' else 'Video Scripts link reset' end);
  return jsonb_build_object('ok', true, 'key', v_key);
end $$;
revoke all on function public.script_link(uuid, boolean) from public, anon;
grant execute on function public.script_link(uuid, boolean) to authenticated;

create or replace function public.video_script_share(p_ids uuid[], p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  s     public.video_scripts;
  v_cl  text;
  n     integer := 0;
  v_key text;
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  for s in select * from public.video_scripts x where x.id = any (coalesce(p_ids, '{}')) order by x.video_no for update loop
    if not public.client_seen(s.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
    if (s.status = 'shared') = coalesce(p_on, false) then continue; end if;
    update public.video_scripts x
       set status = case when p_on then 'shared' else 'draft' end,
           shared_at = case when p_on then now() else null end
     where x.id = s.id;
    select c.name, c.script_key into v_cl, v_key from public.clients c where c.id = s.client_id;
    if p_on and v_key is null then
      loop
        v_key := public.new_link_key();
        exit when not exists (select 1 from public.clients c where c.script_key = v_key);
      end loop;
      update public.clients c set script_key = v_key where c.id = s.client_id;
    end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case when p_on then 'script.shared' else 'script.unshared' end, v_cl,
            public.video_script_label(s));
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;
revoke all on function public.video_script_share(uuid[], boolean) from public, anon;
grant execute on function public.video_script_share(uuid[], boolean) to authenticated;

/* On the day: a scene ticked shot, and its clip number (VC#) as the camera
   names it. With no scene, the voice-over line. Neither starts a round. */
create or replace function public.video_script_shot(p_script uuid, p_scene uuid, p_on boolean, p_vc text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  s      public.video_scripts;
  sc     public.video_script_scenes;
  v_cl   text;
  v_was  boolean;
begin
  if me.id is null or not public.allowed('scripts', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into s from public.video_scripts x where x.id = p_script for update;
  if s.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_seen(s.client_id, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_vc is not null and length(p_vc) > 40 then return jsonb_build_object('error', 'too-long'); end if;
  select c.name into v_cl from public.clients c where c.id = s.client_id;
  if p_scene is null then
    v_was := s.vo_shot_at is not null;
    update public.video_scripts x
       set vo_shot_at = case when p_on is null then x.vo_shot_at when p_on then coalesce(x.vo_shot_at, now()) end,
           vo_shot_by = case when p_on is null then x.vo_shot_by when p_on then coalesce(x.vo_shot_by, me.name) end,
           vo_vc = case when p_vc is null then x.vo_vc else nullif(btrim(p_vc), '') end
     where x.id = p_script;
    if p_on is not null and p_on <> v_was then
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, 'script.shot', v_cl, public.video_script_label(s) || ' · Script (read here) '
              || case when p_on then 'shot' else 'not shot' end);
    end if;
    return jsonb_build_object('ok', true);
  end if;
  select * into sc from public.video_script_scenes y where y.id = p_scene and y.script_id = p_script for update;
  if sc.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_was := sc.shot_at is not null;
  update public.video_script_scenes y
     set shot_at = case when p_on is null then y.shot_at when p_on then coalesce(y.shot_at, now()) end,
         shot_by = case when p_on is null then y.shot_by when p_on then coalesce(y.shot_by, me.name) end,
         vc = case when p_vc is null then y.vc else nullif(btrim(p_vc), '') end
   where y.id = p_scene;
  if p_on is not null and p_on <> v_was then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'script.shot', v_cl, public.video_script_label(s) || ' · Scene ' || sc.position || ' '
            || case when p_on then 'shot' else 'not shot' end);
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.video_script_shot(uuid, uuid, boolean, text) from public, anon;
grant execute on function public.video_script_shot(uuid, uuid, boolean, text) to authenticated;

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
  if lower(btrim(coalesce(p_typed, ''))) <> lower(coalesce(nullif(btrim(s.title), ''), 'V' || s.video_no)) then
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

/* The client's page: the shared scripts, newest shoot first, each with the
   decision on its round and the request the round answers. Never a
   colleague's name, a clip number or a tick. */
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
               'id', s.id, 'series_id', s.series_id, 'video_no', s.video_no, 'kind', s.kind,
               'title', s.title, 'reference_url', s.reference_url, 'platform', s.platform,
               'language', s.language, 'shoot_on', s.shoot_on, 'shoot_time', s.shoot_time,
               'venue', s.venue, 'duration_minutes', s.duration_minutes, 'cast_names', s.cast_names,
               'context', s.context, 'vo', s.vo, 'remarks', s.remarks, 'round', s.round,
               'shared_at', s.shared_at, 'updated_at', s.updated_at,
               'scenes', coalesce((select jsonb_agg(jsonb_build_object('position', sc.position,
                                                     'visual', sc.visual, 'line', sc.line)
                                                     order by sc.position)
                                     from public.video_script_scenes sc where sc.script_id = s.id), '[]'::jsonb),
               'decision', (select jsonb_build_object('decision', r.decision, 'note', r.note,
                                                      'reviewer', r.reviewer, 'at', r.created_at)
                              from public.video_script_reviews r
                             where r.script_id = s.id and r.round = s.round
                             order by r.created_at desc limit 1),
               'asked', (select jsonb_build_object('note', r.note, 'reviewer', r.reviewer, 'at', r.created_at)
                           from public.video_script_reviews r
                          where r.script_id = s.id and r.round = s.round - 1 and r.decision = 'changes'
                          order by r.created_at desc limit 1))
             order by coalesce(s.shoot_on, s.created_at::date) desc, s.series_id, s.video_no)
        from public.video_scripts s
       where s.client_id = v_cl.id and s.status = 'shared'), '[]'::jsonb));
end $$;
revoke all on function public.get_scripts(text) from public;
grant execute on function public.get_scripts(text) to anon;
grant execute on function public.get_scripts(text) to authenticated;

create or replace function public.script_decide(p_token text, p_script uuid, p_decision text,
                                                p_name text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_cl   public.clients;
  s      public.video_scripts;
  v_name text := btrim(coalesce(p_name, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_who  uuid;
begin
  if p_decision not in ('approved', 'changes') then return jsonb_build_object('error', 'bad-decision'); end if;
  select * into v_cl from public.clients c
   where c.script_key = p_token and p_token is not null and c.active;
  if v_cl.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into s from public.video_scripts x
   where x.id = p_script and x.client_id = v_cl.id and x.status = 'shared';
  if s.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_name = '' or length(v_name) > 80 then return jsonb_build_object('error', 'name-required'); end if;
  if p_decision = 'changes' and v_note is null then return jsonb_build_object('error', 'note-required'); end if;
  if v_note is not null and length(v_note) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  insert into public.video_script_reviews (script_id, round, decision, note, reviewer)
  values (s.id, s.round, p_decision, v_note, v_name);
  insert into public.activity_log (actor, action, subject, detail)
  values (v_name, case when p_decision = 'approved' then 'script.approved' else 'script.changes' end, v_cl.name,
          public.video_script_label(s) || case when s.round > 1 then ' · round ' || s.round else '' end
          || coalesce(' · ' || v_note, ''));
  select m.id into v_who from public.team_members m where m.id = s.created_by and m.active;
  if v_who is not null then
    insert into public.ops_notifications (team_member_id, kind, title, body, script_id)
    values (v_who, 'script',
            v_cl.name || case when p_decision = 'approved' then ' approved ' else ' requested changes on ' end
            || public.video_script_label(s),
            left(v_note, 200), s.id);
  end if;
  return jsonb_build_object('ok', true, 'decision', p_decision, 'round', s.round);
end $$;
revoke all on function public.script_decide(text, uuid, text, text, text) from public;
grant execute on function public.script_decide(text, uuid, text, text, text) to anon;
grant execute on function public.script_decide(text, uuid, text, text, text) to authenticated;

-- A script's notice opens the script.
create or replace function public.ops_notifications_push()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_title text := coalesce(nullif(btrim(new.title), ''), 'My Work');
  v_body  text := coalesce(new.body, '');
begin
  perform public.push_queue('team', new.team_member_id,
    jsonb_build_object('en', jsonb_build_object('title', v_title, 'body', v_body),
                       'zh', jsonb_build_object('title', v_title, 'body', v_body)),
    case when new.link is not null then new.link
         when new.task_id is not null then '/admin/?s=work&open=' || new.task_id::text
         when new.report_id is not null then '/admin/?s=reports&report=' || new.report_id::text
         when new.script_id is not null then '/admin/?s=scripts&script=' || new.script_id::text
         when new.kind in ('client_left', 'tasks.empty') then '/admin/?s=work'
         when new.kind = 'hr.letter' then '/admin/?s=mine&view=letters'
         when new.kind = 'perf.disputed' then '/admin/?s=team&tab=performance'
         when new.kind = 'perf.reflect' then '/admin/?s=mine&view=reflection'
         when new.kind = 'perf.initiative' then '/admin/?s=mine&view=initiatives'
         when new.kind like 'health.%' then '/admin/?s=mine&view=health'
         when new.kind like 'perf.%' then '/admin/?s=mine'
         else '/admin/' end,
    case when new.task_id is not null then 'task-' || new.task_id::text
         when new.report_id is not null then 'report-' || new.report_id::text
         when new.script_id is not null then 'script-' || new.script_id::text
         when new.kind = 'hr.letter' then 'hr-letter'
         when new.kind in ('perf.remind', 'perf.reflect', 'health.remind') then 'my-hr'
         when new.kind = 'tasks.empty' then 'tasks-empty'
         when new.kind = 'outstation' then 'outstation'
         else null end);
  return new;
exception when others then
  return new;
end $$;

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('script.approved', 'script.changes', 'script.created', 'script.deleted',
                    'script.link', 'script.saved', 'script.shared', 'script.shot',
                    'script.unshared') then 'scripts'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- END OF VIDEO SCRIPTS -------------------------------------------------------

select public.functions_tidy();
