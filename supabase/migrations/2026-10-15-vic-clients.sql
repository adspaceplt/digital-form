-- ===========================================================================
-- VIC CLIENTS — a Very Important Client is marked by an admin, and the team
-- sees it wherever the client is named (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15)
--   Some clients need the team's prompt, priority attention. They are marked
--   VIC (Very Important Client; the user: "VIC instead, Very Important Client
--   not Person"), by admins alone, and only inside the console: never on a
--   client page, a link page, a PDF or anything the client reads.
--
-- WHAT CHANGED
--   1. `clients.vic_at` (when the client became VIC; null is not VIC),
--      `vic_by` (the colleague who set it) and `vic_note` (optional, 300
--      characters). Readable to the team as every non-billing column.
--   2. Trigger `clients_vic_guard` refuses any write to the three columns
--      but `client_vic_set`'s (`vic-function`).
--   3. `client_vic_set(p_client, p_on, p_note, p_since)`: the granted part
--      `clients.vic` at Work (an admin's by itself, offered to a group as
--      Manage alone), the client in the caller's scope at View. `p_since`
--      is the day it became VIC (MYT; today where none is given, never after
--      today: `bad-date`), shown and changed in place under the record's
--      Key dates (the user, 2026-10-15). Files `client.edited` from and to
--      (VIC: off → on · since 12 Oct 2026 · note; VIC: on → off; VIC since:
--      from → to; VIC note: from → to). Answers `{ok, since, by_name,
--      note}`, else `{error}`: `denied`, `not-found`, `too-long`,
--      `bad-date`.
--   4. `vic_clients()`: every VIC client the caller may see (its stage band
--      and scope, or a task of theirs on it), with its name, since, who set
--      it and the note, read once by the console beside me().
--   5. Trigger `ops_notifications_vic`: a notice about a VIC client's work
--      (its task, report, script or client) is titled "VIC · …", so the bell
--      and the push say so. A colleague's notice is left as written. A fault
--      never fails the notice.
--
-- ORDER
--   The pages first: they ask `vic_clients` and leave the map empty while it
--   is missing, and draw Mark as VIC only for the part. Then this file. An
--   old open tab never writes the columns.
--
-- Safe to run twice. Holds no drop or delete. Rollback: the columns may stay
-- unread; in the SQL Editor, drop trigger clients_vic_guard on
-- public.clients, drop trigger ops_notifications_vic on
-- public.ops_notifications, then drop the functions client_vic_set(uuid,
-- boolean, text, date), vic_day(date), vic_clients(), clients_vic_guard()
-- and ops_notifications_vic().
-- ===========================================================================

alter table public.clients add column if not exists vic_at timestamptz;
alter table public.clients add column if not exists vic_by uuid references public.team_members(id);
alter table public.clients add column if not exists vic_note text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'clients_vic_shape') then
    alter table public.clients add constraint clients_vic_shape
      check ((vic_at is not null or (vic_by is null and vic_note is null))
         and (vic_note is null or char_length(vic_note) <= 300));
  end if;
end $$;
grant select (vic_at, vic_by, vic_note) on table public.clients to authenticated;

/* Only `client_vic_set` writes the three columns: it says so for its own
   transaction (`adspace.vic`). A write made by another trigger passes. */
create or replace function public.clients_vic_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if pg_trigger_depth() > 1 or coalesce(current_setting('adspace.vic', true), '') = 'on' then
    return new;
  end if;
  if (tg_op = 'INSERT' and (new.vic_at is not null or new.vic_by is not null or new.vic_note is not null))
     or (tg_op = 'UPDATE' and (new.vic_at is distinct from old.vic_at or new.vic_by is distinct from old.vic_by
                               or new.vic_note is distinct from old.vic_note)) then
    raise exception 'vic-function'
      using hint = 'A client is marked VIC or cleared only from its record, by an admin.';
  end if;
  return new;
end $$;
revoke all on function public.clients_vic_guard() from public, anon, authenticated;
create or replace trigger clients_vic_guard
  before insert or update of vic_at, vic_by, vic_note on public.clients
  for each row execute function public.clients_vic_guard();

/* A day as the record writes it: 12 Oct 2026. */
create or replace function public.vic_day(p_day date)
returns text language sql immutable set search_path = public as $$
  select case when p_day is null then 'not set'
    else extract(day from p_day)::int || ' ' ||
      (array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sept','Oct','Nov','Dec'])[extract(month from p_day)::int] || ' ' ||
      extract(year from p_day)::int end
$$;
revoke all on function public.vic_day(date) from public, anon, authenticated;

create or replace function public.client_vic_set(p_client uuid, p_on boolean, p_note text default null,
                                                 p_since date default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  c public.clients;
  v_note text := case when coalesce(p_on, false) then nullif(btrim(coalesce(p_note, '')), '') end;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_was date;
  v_day date;
  v_at timestamptz;
  v_detail text;
  v_by text;
begin
  m := public.ops_me();
  if m.id is null or not public.ops_granted('clients.vic', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into c from public.clients where id = p_client;
  if c.id is null or not public.client_seen(p_client, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if char_length(coalesce(v_note, '')) > 300 then
    return jsonb_build_object('error', 'too-long');
  end if;
  if p_since is not null and (p_since > v_today or p_since < date '2023-08-14') then
    return jsonb_build_object('error', 'bad-date');
  end if;
  v_was := (c.vic_at at time zone 'Asia/Kuala_Lumpur')::date;
  v_day := case when coalesce(p_on, false) then coalesce(p_since, v_was, v_today) end;
  v_at := case when v_day is null then null
               when v_day = v_was then c.vic_at
               when v_day = v_today then now()
               else (v_day::timestamp + time '12:00') at time zone 'Asia/Kuala_Lumpur' end;
  if (c.vic_at is not null) = coalesce(p_on, false) and c.vic_note is not distinct from v_note
     and v_at is not distinct from c.vic_at then
    select t.name into v_by from public.team_members t where t.id = c.vic_by;
    return jsonb_build_object('ok', true, 'since', c.vic_at, 'by_name', v_by, 'note', c.vic_note);
  end if;
  v_detail := case
    when coalesce(p_on, false) and c.vic_at is null
      then 'VIC: off → on · since ' || public.vic_day(v_day) || coalesce(' · ' || v_note, '')
    when not coalesce(p_on, false) then 'VIC: on → off'
    else concat_ws(' · ',
      case when v_day is distinct from v_was then 'VIC since: ' || public.vic_day(v_was) || ' → ' || public.vic_day(v_day) end,
      case when c.vic_note is distinct from v_note
           then 'VIC note: ' || coalesce(c.vic_note, 'not set') || ' → ' || coalesce(v_note, 'not set') end) end;
  perform set_config('adspace.vic', 'on', true);
  update public.clients
     set vic_at = v_at,
         vic_by = case when coalesce(p_on, false) then case when c.vic_at is null then m.id else c.vic_by end end,
         vic_note = v_note
   where id = p_client
  returning * into c;
  perform set_config('adspace.vic', '', true);
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(nullif(m.name, ''), m.email), 'client.edited', c.name, v_detail);
  select t.name into v_by from public.team_members t where t.id = c.vic_by;
  return jsonb_build_object('ok', true, 'since', c.vic_at, 'by_name', v_by, 'note', c.vic_note);
end $$;
revoke all on function public.client_vic_set(uuid, boolean, text, date) from public, anon;
grant execute on function public.client_vic_set(uuid, boolean, text, date) to authenticated;

create or replace function public.vic_clients()
returns table (client_id uuid, name text, since timestamptz, by_name text, note text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.vic_at, t.name, c.vic_note
    from public.clients c
    left join public.team_members t on t.id = c.vic_by
   where c.vic_at is not null
     and (public.ops_me()).id is not null
     and (public.client_row_seen(c.stage, c.owner, 'view')
          or exists (select 1 from public.ops_tasks k
                       join public.ops_task_assignees a on a.task_id = k.id and a.ended_at is null
                      where k.client_id = c.id and a.team_member_id = (public.ops_me()).id))
$$;
revoke all on function public.vic_clients() from public, anon;
grant execute on function public.vic_clients() to authenticated;

create or replace function public.ops_notifications_vic()
returns trigger language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if new.kind = 'notice' or coalesce(new.title, '') like 'VIC · %' then return new; end if;
  begin
    cid := new.client_id;
    if cid is null and new.task_id is not null then
      select k.client_id into cid from public.ops_tasks k where k.id = new.task_id;
    end if;
    if cid is null and new.report_id is not null then
      select r.client_id into cid from public.sm_reports r where r.id = new.report_id;
    end if;
    if cid is null and new.script_id is not null then
      select s.client_id into cid from public.video_scripts s where s.id = new.script_id;
    end if;
    if cid is not null and exists (select 1 from public.clients c where c.id = cid and c.vic_at is not null) then
      new.title := 'VIC · ' || coalesce(new.title, '');
    end if;
  exception when others then
    null;
  end;
  return new;
end $$;
revoke all on function public.ops_notifications_vic() from public, anon, authenticated;
create or replace trigger ops_notifications_vic
  before insert on public.ops_notifications
  for each row execute function public.ops_notifications_vic();

-- END OF VIC CLIENTS ----------------------------------------------------------
select public.functions_tidy();
