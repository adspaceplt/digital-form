-- ===========================================================================
-- PAST CLIENTS LEAVE THE CLIENT PORTAL (2026-11-24)
-- ===========================================================================
-- WHY: the client portal's security review, finding 3 (the user,
-- 2026-11-24). A client moved to Past kept its portal: every contact the
-- team had given access could still sign in and read the services,
-- letters, reports, meetings, review sets, scripts and campaigns of a
-- client the agency no longer serves. A Past client is now refused as a
-- stranger is, unless the team keeps its access on from the record.
--
-- WHAT IT CHANGES
--   * `clients.portal_kept_at`, `clients.portal_kept_by`: the team kept a
--     Past client's portal on, when and who. Granted to read as every
--     other client column the record reads; written only by
--     `client_portal_access_set` (trigger `clients_portal_kept_guard`).
--   * `portal_client_open(p_client)` (closed to every page): the one
--     answer to whether a client's portal is open: the client is not
--     inactive (`active`), and either not Past, or kept on since it last
--     moved (`portal_kept_at` at or after `stage_since`). A client moved
--     back to Active is open again by itself; moved to Past again later,
--     an earlier keep no longer stands. Nothing is written by a move.
--   * `portal_clients()`: a contact's clients are those whose portal is
--     open. Every portal function asks it, directly or through
--     `portal_contact_name`: `get_portal`, `portal_request`,
--     `portal_request_once`, `portal_withdraw`, `portal_work`,
--     `portal_link_pass`, `portal_feedback`, `portal_reports`,
--     `portal_report`, `portal_meetings`, `sm_report_file_key` and
--     `sm_report_thumbs` (sign-download), `doc_code_of`, and the decider
--     stamp; media-pass asks it as the caller from this release.
--   * `portal_login_name(p_email)` (service role alone): portal-login's
--     question, the name of a live contact with access at an open client,
--     else nothing; no login is made for a Past client's contact.
--   * `client_portal_access_set(p_client, p_on)`: Enable access and Revoke
--     access on a Past client's record (Clients: Contacts at Work, the
--     client in the colleague's scope), filed `client.edited` in the
--     Activity record (Client portal: off → on, on → off).
--
-- ORDER: this file, then portal-login and media-pass (main's copy), then
-- the pages. Between this file and the functions, the old portal-login
-- still makes a login for a Past client's contact, who then reads Access
-- denied; the old media-pass still passes that contact's folder for its
-- twelve hours (the files are kept; nothing else reads). An old console
-- tab never draws Enable access and reads no new column.
-- Safe to run twice. Holds no drop or delete.
-- ROLLBACK: run `portal_clients()` as schema.sql defines it before this
-- band, redeploy portal-login and media-pass from the commit before; the
-- columns, the guard and the three new functions may stay unread.
-- ===========================================================================

-- PAST CLIENTS LEAVE THE CLIENT PORTAL --------------------------------------

alter table public.clients add column if not exists portal_kept_at timestamptz;
alter table public.clients add column if not exists portal_kept_by uuid references public.team_members(id) on delete set null;
grant select (portal_kept_at, portal_kept_by) on table public.clients to authenticated;

/* Only `client_portal_access_set` writes the two columns: it says so for its
   own transaction (`adspace.portal_kept`). */
create or replace function public.clients_portal_kept_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if pg_trigger_depth() > 1 or coalesce(current_setting('adspace.portal_kept', true), '') = 'on' then
    return new;
  end if;
  if (tg_op = 'INSERT' and (new.portal_kept_at is not null or new.portal_kept_by is not null))
     or (tg_op = 'UPDATE' and (new.portal_kept_at is distinct from old.portal_kept_at
                               or new.portal_kept_by is distinct from old.portal_kept_by)) then
    raise exception 'portal-kept-function'
      using hint = 'A Past client''s portal access is enabled or revoked only from its record.';
  end if;
  return new;
end $$;
revoke all on function public.clients_portal_kept_guard() from public, anon, authenticated;
create or replace trigger clients_portal_kept_guard
  before insert or update of portal_kept_at, portal_kept_by on public.clients
  for each row execute function public.clients_portal_kept_guard();

/* Whether a client's portal is open, derived on every read. */
create or replace function public.portal_client_open(p_client uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.clients c
     where c.id = p_client and c.active
       and (c.stage is distinct from 'past'
            or (c.portal_kept_at is not null
                and c.portal_kept_at >= coalesce(c.stage_since, '-infinity'::timestamptz))))
$$;
revoke all on function public.portal_client_open(uuid) from public, anon, authenticated;

create or replace function public.portal_clients()
returns setof uuid
language sql security definer stable set search_path = public as $$
  select distinct c.client_id from public.client_contacts c
  where c.portal_access and c.archived_at is null and c.email is not null
    and lower(c.email) = lower(auth.jwt() ->> 'email')
    and public.portal_client_open(c.client_id)
    and not exists (
      select 1 from public.team_members t
      where t.active and t.email is not null
        and lower(t.email) = lower(auth.jwt() ->> 'email'))
$$;
revoke all on function public.portal_clients() from public, anon;
grant execute on function public.portal_clients() to authenticated;

/* portal-login's one question: the name of a live contact the team gave
   access at a client whose portal is open ('' where none is written), else
   nothing. An address is matched as itself. */
create or replace function public.portal_login_name(p_email text)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(k.name, '') from public.client_contacts k
   where k.portal_access and k.archived_at is null and k.email is not null
     and lower(btrim(k.email)) = lower(btrim(coalesce(p_email, '')))
     and public.portal_client_open(k.client_id)
   order by k.is_primary desc
   limit 1
$$;
revoke all on function public.portal_login_name(text) from public, anon, authenticated;
grant execute on function public.portal_login_name(text) to service_role;

/* Enable access / Revoke access on a Past client's record. */
create or replace function public.client_portal_access_set(p_client uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  c public.clients;
  v_kept boolean;
  v_by text;
begin
  m := public.ops_me();
  if m.id is null or not public.allowed('clients.contacts', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into c from public.clients where id = p_client;
  if c.id is null or not public.client_seen(p_client, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_kept := c.portal_kept_at is not null
            and c.portal_kept_at >= coalesce(c.stage_since, '-infinity'::timestamptz);
  if coalesce(p_on, false) and c.stage is distinct from 'past' then
    return jsonb_build_object('error', 'not-past');
  end if;
  if v_kept = coalesce(p_on, false) and (v_kept or c.portal_kept_at is null) then
    select t.name into v_by from public.team_members t where t.id = c.portal_kept_by;
    return jsonb_build_object('ok', true, 'on', v_kept, 'at', c.portal_kept_at, 'by_name', v_by);
  end if;
  perform set_config('adspace.portal_kept', 'on', true);
  update public.clients
     set portal_kept_at = case when coalesce(p_on, false) then now() end,
         portal_kept_by = case when coalesce(p_on, false) then m.id end
   where id = p_client
  returning * into c;
  perform set_config('adspace.portal_kept', '', true);
  if v_kept is distinct from coalesce(p_on, false) then
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(nullif(m.name, ''), m.email), 'client.edited', c.name,
            case when coalesce(p_on, false) then 'Client portal: off → on' else 'Client portal: on → off' end);
  end if;
  return jsonb_build_object('ok', true, 'on', coalesce(p_on, false), 'at', c.portal_kept_at,
    'by_name', case when coalesce(p_on, false) then m.name end);
end $$;
revoke all on function public.client_portal_access_set(uuid, boolean) from public, anon;
grant execute on function public.client_portal_access_set(uuid, boolean) to authenticated;

-- END OF PAST CLIENTS LEAVE THE CLIENT PORTAL -------------------------------

select public.functions_tidy();
