-- ===========================================================================
-- CREATOR AND CAMPAIGN IDS — every creator a Creator ID (ADC0001), every
-- campaign a Campaign ID (CC001), and a booking's Job reference made of the
-- two (ADC0001/CC001), each prefix, width, next number and the reference's
-- shape a setting. 2026-11-08. Safe to run twice. Rollback at the foot.
-- Mirrored byte for byte in supabase/schema.sql under the same banner;
-- tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-11-08: "USE ADCXXXX for adspace creator, ACC
-- for each creator campaign"; "dont hardcode anything")
-- * `id_formats` (RLS on, no policy, no grant): a row a kind, `creator` and
--   `campaign` a prefix (capital letters, 1 to 6), a width (2 to 6 digits)
--   and the next number; `job` a pattern of {creator} and {campaign}.
-- * `creators.creator_code` and `campaigns.campaign_code`, unique, given by
--   trigger on insert from the next number under a row lock (`id_take`),
--   never changed after (`code-fixed`). The ones standing are given theirs
--   in the order they were made.
-- * `id_formats_list()` (the team) reads them; `id_format_set(p_kind,
--   p_prefix, p_width, p_next, p_pattern)` (`team.settings`) changes them:
--   `bad-prefix`, `bad-width`, `bad-next` (at or below a number in use under
--   that prefix), `bad-pattern` (a job pattern without both parts); filed
--   `team.changed` under Creator and campaign IDs. A change applies to the next one made.
-- * `campaign_job_ref(p_option)`: a booking's Job reference as the pattern
--   in force writes it, for the team.
-- ===========================================================================

create table if not exists public.id_formats (
  kind       text primary key check (kind in ('creator', 'campaign', 'job')),
  prefix     text,
  width      int,
  next_no    bigint,
  pattern    text,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  check ((kind = 'job' and pattern is not null)
      or (kind <> 'job' and prefix ~ '^[A-Z]{1,6}$' and width between 2 and 6 and next_no >= 1))
);
alter table public.id_formats enable row level security;
revoke all on public.id_formats from public, anon, authenticated;
insert into public.id_formats (kind, prefix, width, next_no, pattern) values
  ('creator', 'ADC', 4, 1, null), ('campaign', 'CC', 3, 1, null), ('job', null, null, null, '{creator}/{campaign}')
on conflict (kind) do nothing;

alter table public.creators add column if not exists creator_code text;
create unique index if not exists creators_creator_code_idx on public.creators (creator_code);
alter table public.campaigns add column if not exists campaign_code text;
create unique index if not exists campaigns_campaign_code_idx on public.campaigns (campaign_code);

/* The next code of a kind, taken under the row's lock so two inserts at once
   take two numbers; a code already held (typed in the SQL editor) is passed
   over. Two digits short of the width widen, never wrap. */
create or replace function public.id_take(p_kind text)
returns text language plpgsql volatile security definer set search_path = public as $$
declare
  f public.id_formats;
  v text;
begin
  select * into f from public.id_formats where kind = p_kind for update;
  if f.kind is null or f.prefix is null then return null; end if;
  loop
    v := f.prefix || lpad(f.next_no::text, greatest(f.width, length(f.next_no::text)), '0');
    f.next_no := f.next_no + 1;
    exit when not exists (select 1 from public.creators c where c.creator_code = v)
          and not exists (select 1 from public.campaigns m where m.campaign_code = v);
  end loop;
  update public.id_formats set next_no = f.next_no where kind = p_kind;
  return v;
end $$;
revoke all on function public.id_take(text) from public, anon, authenticated;

create or replace function public.creators_creator_code()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.creator_code := public.id_take('creator');
  elsif new.creator_code is distinct from old.creator_code and old.creator_code is not null then
    raise exception 'code-fixed';
  end if;
  return new;
end $$;
revoke all on function public.creators_creator_code() from public, anon, authenticated;
create or replace trigger creators_creator_code before insert or update of creator_code on public.creators
  for each row execute function public.creators_creator_code();

create or replace function public.campaigns_campaign_code()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.campaign_code := public.id_take('campaign');
  elsif new.campaign_code is distinct from old.campaign_code and old.campaign_code is not null then
    raise exception 'code-fixed';
  end if;
  return new;
end $$;
revoke all on function public.campaigns_campaign_code() from public, anon, authenticated;
create or replace trigger campaigns_campaign_code before insert or update of campaign_code on public.campaigns
  for each row execute function public.campaigns_campaign_code();

/* The ones standing take theirs in the order they were made. */
do $$
declare r record;
begin
  for r in select id from public.creators where creator_code is null order by created_at, id loop
    update public.creators set creator_code = public.id_take('creator') where id = r.id;
  end loop;
  for r in select id from public.campaigns where campaign_code is null order by created_at, id loop
    update public.campaigns set campaign_code = public.id_take('campaign') where id = r.id;
  end loop;
end $$;

create or replace function public.id_formats_list()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_team() then coalesce(jsonb_agg(jsonb_build_object(
           'kind', f.kind, 'prefix', f.prefix, 'width', f.width, 'next', f.next_no, 'pattern', f.pattern)
           order by array_position(array['creator', 'campaign', 'job'], f.kind)), '[]'::jsonb)
         else '[]'::jsonb end
    from public.id_formats f
$$;
revoke all on function public.id_formats_list() from public, anon;
grant execute on function public.id_formats_list() to authenticated;

create or replace function public.id_format_set(p_kind text, p_prefix text, p_width int, p_next bigint, p_pattern text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  f   public.id_formats;
  v_p text := upper(btrim(coalesce(p_prefix, '')));
  v_t text := btrim(coalesce(p_pattern, ''));
  v_top bigint;
  v_moved text[] := '{}';
  v_word text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into f from public.id_formats where kind = p_kind for update;
  if f.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  v_word := case p_kind when 'creator' then 'Creator ID' when 'campaign' then 'Campaign ID' else 'Job reference' end;
  if p_kind = 'job' then
    if length(v_t) > 40 or position('{creator}' in v_t) = 0 or position('{campaign}' in v_t) = 0 then
      return jsonb_build_object('error', 'bad-pattern');
    end if;
    if v_t is distinct from f.pattern then
      update public.id_formats set pattern = v_t, updated_at = now(), updated_by = me.id where kind = p_kind;
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, 'team.changed', 'Creator and campaign IDs', v_word || ': ' || f.pattern || ' → ' || v_t);
    end if;
    return jsonb_build_object('ok', true);
  end if;
  if v_p !~ '^[A-Z]{1,6}$' then return jsonb_build_object('error', 'bad-prefix'); end if;
  if p_width is null or p_width < 2 or p_width > 6 then return jsonb_build_object('error', 'bad-width'); end if;
  if p_next is null or p_next < 1 then return jsonb_build_object('error', 'bad-next'); end if;
  -- The next number stays above every number in use under that prefix.
  if p_kind = 'creator' then
    select max(substring(c.creator_code from length(v_p) + 1)::bigint) into v_top
      from public.creators c where c.creator_code ~ ('^' || v_p || '[0-9]+$');
  else
    select max(substring(m.campaign_code from length(v_p) + 1)::bigint) into v_top
      from public.campaigns m where m.campaign_code ~ ('^' || v_p || '[0-9]+$');
  end if;
  if v_top is not null and p_next <= v_top then
    return jsonb_build_object('error', 'bad-next', 'top', v_top);
  end if;
  v_moved := array_remove(array[
    case when v_p <> f.prefix then 'prefix ' || f.prefix || ' → ' || v_p end,
    case when p_width <> f.width then 'digits ' || f.width || ' → ' || p_width end,
    case when p_next <> f.next_no then 'next ' || f.next_no || ' → ' || p_next end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.id_formats set prefix = v_p, width = p_width, next_no = p_next, updated_at = now(), updated_by = me.id
   where kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Creator and campaign IDs', v_word || ': ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.id_format_set(text, text, int, bigint, text) from public, anon;
grant execute on function public.id_format_set(text, text, int, bigint, text) to authenticated;

create or replace function public.campaign_job_ref(p_option uuid)
returns text language sql stable security definer set search_path = public as $$
  select replace(replace(f.pattern, '{creator}', coalesce(c.creator_code, '')), '{campaign}', coalesce(m.campaign_code, ''))
    from public.campaign_options o
    join public.creators c on c.id = o.creator_id
    join public.campaigns m on m.id = o.campaign_id
    join public.id_formats f on f.kind = 'job'
   where o.id = p_option and public.is_team()
$$;
revoke all on function public.campaign_job_ref(uuid) from public, anon;
grant execute on function public.campaign_job_ref(uuid) to authenticated;

-- Rollback:
--   drop function if exists public.campaign_job_ref(uuid);
--   drop function if exists public.id_format_set(text, text, int, bigint, text);
--   drop function if exists public.id_formats_list();
--   drop trigger if exists campaigns_campaign_code on public.campaigns;
--   drop trigger if exists creators_creator_code on public.creators;
--   drop function if exists public.campaigns_campaign_code();
--   drop function if exists public.creators_creator_code();
--   drop function if exists public.id_take(text);
--   alter table public.campaigns drop column if exists campaign_code;
--   alter table public.creators drop column if exists creator_code;
--   drop table if exists public.id_formats;

-- END OF CREATOR AND CAMPAIGN IDS --------------------------------------------

select public.functions_tidy();
