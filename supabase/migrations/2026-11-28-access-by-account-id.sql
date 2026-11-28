-- ===========================================================================
-- ACCESS BY ACCOUNT ID (2026-11-28)
-- ===========================================================================
-- WHY (the restructure, docs/MAP.md risk 1, §G release 1): a colleague's and
-- a client contact's access was found by the address in the sign-in token
-- (`lower(email) = lower(auth.jwt() ->> 'email')`), so access followed an
-- address, not a person: a login whose address changed lost it, and a new
-- login given an old address took the old person's. Every check now asks
-- the caller's account id (`auth.uid()`) against a link stored on the row;
-- the address is contact data.
--
-- WHAT CHANGES
--   * `team_members.auth_user_id` (unique) and `client_contacts.auth_user_id`
--     (one login may be a contact at several clients), each `references
--     auth.users(id) on delete set null`, each indexed.
--   * `identity_link(uid)`: links a confirmed login to the rows its address
--     names, and only where exactly one login holds that address: the one
--     colleague row (a live row before a removed one; two at the same rank,
--     none), never a second row for a login already linked, and every live
--     contact row not yet linked. A row already linked is never moved.
--   * Trigger `auth_users_identity_link` on `auth.users`: each sign-in asks
--     `identity_link` (the first sign-in of an invited address links it).
--     It never stops a sign-in.
--   * `team_role_defaults`: a write that only links a login, as one that
--     only stamps `last_seen_at`, re-copies nothing and stamps no change.
--   * Trigger `identity_link_guard` on both tables: a signed-in caller never
--     writes the link (`identity-link`); an address changed on the record
--     lets go of the login linked to it, so the old login loses access and
--     the new address links at its own first sign-in, as an invitation.
--   * Backfill: every confirmed login through `identity_link`, once per run.
--   * Restated by the id, each refusal kept: `me`, `is_team`, `ops_me`,
--     `abroad_who`, `allowed` (both), `ops_granted`, `my_access_expired`,
--     `team_super_ok`, `client_row_seen_by`,
--     `client_scope_free`, `clients_owner_guard`, `ai_draft_set_limit`,
--     `page_set`, `build_require`, the two name card functions
--     standing (`namecard_mine`, `namecard_save`; `_save_mine`, `_save_card`
--     and `client_row_seen` were dropped by earlier bands and stay dropped),
--     `team_keep_one_admin`, `team_access_guard`, `team_set_expiry_at`,
--     `team_members_system_guard`, `team_admin_guard`, `issue_letter`,
--     `verify_letter`, `override_service_state`, `issue_document`,
--     `register_add`, `document_reissue`, `campaigns_deleted_log`,
--     `delete_client`; the client portal's `portal_clients`, `get_portal`,
--     `portal_request_once`, `portal_contact_name`, `feedback_submit`; and
--     the login's own: `team_member_seen`, `team_member_sessions`,
--     `team_session_end`, `team_sessions_end_all`, `team_sessions_idle_end`,
--     `team_member_remove`, `team_member_purge` (with `team_login_of`).
--   * The jobs that act as a colleague (`ops_recurring_daily`,
--     `sm_reports_month_tick`, `agent_schedules_run`) set the colleague's
--     account id as the claims' `sub` beside the address.
--   * Left reading the token's address as words only: the actor filed in
--     the Activity record, and "is anybody signed in".
--
-- ORDER: this file (connector), then the edge functions `sign-upload`,
-- `sign-download`, `media-pass`, `invite-member` (each asks the colleague
-- by `auth_user_id`), then the pages (`js/portal.js` tells a change of
-- person by the account id). An open tab keeps its token: a linked login
-- carries on unchanged; an unlinked one is refused as an address the team
-- does not hold is today, until its next sign-in links it. Between this
-- file and the functions' deploy the four functions still ask by address,
-- as before. Safe to run twice.
-- ROLLBACK: run the previous definitions of the restated functions again
-- (their last bands before this one in schema.sql), then
-- `drop trigger if exists auth_users_identity_link on auth.users;`. The
-- columns, the guard and the links may stay: nothing else reads them.
-- ===========================================================================

-- ACCESS BY ACCOUNT ID -------------------------------------------------------

alter table public.team_members add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
alter table public.client_contacts add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'team_members_auth_user_id_key') then
    alter table public.team_members add constraint team_members_auth_user_id_key unique (auth_user_id);
  end if;
end $$;
create index if not exists client_contacts_auth_user_id_idx on public.client_contacts (auth_user_id);

-- A signed-in caller never writes the link; an address changed lets go of it.
create or replace function public.identity_link_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if auth.uid() is not null
     and ((tg_op = 'INSERT' and new.auth_user_id is not null)
          or (tg_op = 'UPDATE' and new.auth_user_id is distinct from old.auth_user_id)) then
    raise exception 'identity-link' using hint = 'A sign-in links itself.';
  end if;
  if tg_op = 'UPDATE' and new.auth_user_id is not null
     and lower(btrim(coalesce(new.email, ''))) is distinct from lower(btrim(coalesce(old.email, ''))) then
    new.auth_user_id := null;
  end if;
  return new;
end $$;
revoke all on function public.identity_link_guard() from public, anon, authenticated;
drop trigger if exists identity_link_guard on public.team_members;
create trigger identity_link_guard before insert or update on public.team_members
  for each row execute function public.identity_link_guard();
drop trigger if exists identity_link_guard on public.client_contacts;
create trigger identity_link_guard before insert or update on public.client_contacts
  for each row execute function public.identity_link_guard();

-- A link alone is no change to a colleague's record.
create or replace function public.team_role_defaults()
returns trigger language plpgsql as $$
declare r public.team_roles;
begin
  /* The console's minute stamps when a colleague was last active, and a
     sign-in links its login (ACCESS BY ACCOUNT ID); either alone is no
     change to their record (A COLLEAGUE'S LAST SIGN-IN). */
  if tg_op = 'UPDATE'
     and (new.last_seen_at is distinct from old.last_seen_at or new.auth_user_id is distinct from old.auth_user_id)
     and (to_jsonb(new) - 'last_seen_at' - 'auth_user_id') = (to_jsonb(old) - 'last_seen_at' - 'auth_user_id') then
    return new;
  end if;
  select * into r from public.team_roles where slug = new.role;
  if r.slug is null then
    select * into r from public.team_roles where slug = 'account';
    new.role := 'account';
  end if;
  new.is_admin      := r.is_admin;
  new.can_clients   := r.can_clients;   new.can_review   := r.can_review;
  new.can_campaigns := r.can_campaigns; new.can_links    := r.can_links;
  new.can_activity  := r.can_activity;  new.can_billing  := r.can_billing;
  new.can_remove    := r.can_remove;    new.can_doc_void := r.can_doc_void;
  new.access        := coalesce(r.access, '{}'::jsonb);
  new.client_scope  := coalesce(r.client_scope, 'all');
  /* The group's switches (GROUP SWITCHES, 2026-11-17); an admin holds all. */
  new.ai_on         := coalesce(r.is_admin, false) or coalesce(r.ai_on, false);
  new.email_on      := coalesce(r.is_admin, false) or coalesce(r.email_on, false);
  new.whatsapp_on   := coalesce(r.is_admin, false) or coalesce(r.whatsapp_on, false);
  new.sensitive_on  := coalesce(r.is_admin, false) or coalesce(r.sensitive_on, false);
  new.updated_at    := now();
  return new;
end $$;

-- The one rule a login is linked by, at a sign-in and in the backfill.
create or replace function public.identity_link(p_uid uuid)
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  v_mail text;
  v_team uuid;
  v_live integer;
  v_all  integer;
  v_n    integer := 0;
  v_k    integer := 0;
begin
  select lower(btrim(u.email)) into v_mail from auth.users u
   where u.id = p_uid and u.email_confirmed_at is not null;
  if coalesce(v_mail, '') = '' then return 0; end if;
  if (select count(*) from auth.users u where lower(btrim(u.email)) = v_mail) <> 1 then return 0; end if;
  if not exists (select 1 from public.team_members t where t.auth_user_id = p_uid) then
    select count(*) filter (where coalesce(t.active, false) and t.removed_at is null), count(*),
           (array_agg(t.id order by (coalesce(t.active, false) and t.removed_at is null) desc))[1]
      into v_live, v_all, v_team
      from public.team_members t
     where t.auth_user_id is null and t.erased_at is null and lower(btrim(t.email)) = v_mail;
    if v_live = 1 or (v_live = 0 and v_all = 1) then
      update public.team_members t set auth_user_id = p_uid where t.id = v_team and t.auth_user_id is null;
      get diagnostics v_n = row_count;
    end if;
  end if;
  update public.client_contacts k set auth_user_id = p_uid
   where k.auth_user_id is null and k.archived_at is null and lower(btrim(k.email)) = v_mail;
  get diagnostics v_k = row_count;
  return v_n + v_k;
end $$;
revoke all on function public.identity_link(uuid) from public, anon, authenticated;

create or replace function public.auth_users_identity_link()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email_confirmed_at is null or new.last_sign_in_at is null then return new; end if;
  if tg_op = 'UPDATE' and new.last_sign_in_at is not distinct from old.last_sign_in_at
     and old.email_confirmed_at is not null then return new; end if;
  perform public.identity_link(new.id);
  return new;
exception when others then
  raise warning 'identity link skipped: %', sqlerrm;
  return new;
end $$;
revoke all on function public.auth_users_identity_link() from public, anon, authenticated;
drop trigger if exists auth_users_identity_link on auth.users;
create trigger auth_users_identity_link after insert or update on auth.users
  for each row execute function public.auth_users_identity_link();

-- The login a colleague's row holds; a row never linked, the address's own
-- login where nothing else holds it (what removing a colleague signs out).
create or replace function public.team_login_of(p_uid uuid, p_email text)
returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce(p_uid, (select u.id from auth.users u
                           where p_email is not null and lower(u.email) = lower(p_email)
                             and not exists (select 1 from public.team_members x where x.auth_user_id = u.id)
                             and not exists (select 1 from public.client_contacts k where k.auth_user_id = u.id)
                           limit 1))
$$;
revoke all on function public.team_login_of(uuid, text) from public, anon, authenticated;

-- Backfill: once per run; a row already linked is never moved.
select count(public.identity_link(u.id)) from auth.users u where u.email_confirmed_at is not null;

-- The checks, by the account id. -------------------------------------------

create or replace function public.allowed(flag text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  if flag = 'admin' then
    select * into t from public.team_members
      where auth_user_id = auth.uid() and active limit 1;
    if t.id is null then return false; end if;
    return t.is_admin or t.role = 'admin';
  end if;
  return public.allowed(flag, 'work');
end $$;

create or replace function public.team_keep_one_admin()
returns trigger language plpgsql as $$
begin
  if old.auth_user_id = auth.uid() and old.is_admin
     and (tg_op = 'DELETE' or new.active = false
          or not coalesce((select is_admin from public.team_roles where slug = new.role), false)) then
    raise exception 'You cannot remove your own admin access. Ask another admin.';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

create or replace function public.override_service_state(p_service uuid, p_state text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cs  public.client_services%rowtype;
  cl  public.clients%rowtype;
  adm boolean;
begin
  select coalesce(t.is_admin, t.role = 'admin', false) into adm
    from public.team_members t where t.auth_user_id = auth.uid() and t.active limit 1;
  if not coalesce(adm, false) then return jsonb_build_object('error', 'not-allowed'); end if;
  if p_state not in ('enquired', 'quoted', 'confirmed') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('error', 'reason-required'); end if;
  select * into cs from public.client_services where id = p_service and archived_at is null;
  if cs.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if cs.state = p_state then return jsonb_build_object('ok', true, 'repeat', true); end if;
  update public.client_services set state = p_state where id = p_service;
  select * into cl from public.clients where id = cs.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'service.override', cl.name,
          cs.label || ' · ' || cs.state || ' to ' || p_state || ' · ' || btrim(p_reason));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.namecard_mine()
returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce((
    select jsonb_build_object('key', t.card_key, 'slug', t.card_slug, 'name', t.name,
                              'designation', t.designation, 'mobile', t.mobile,
                              'email', lower(t.email), 'on', t.card_on,
                              'show_mobile', t.card_mobile)
      from public.team_members t
     where t.auth_user_id = auth.uid() and t.active
     limit 1), jsonb_build_object('error', 'not-team'))
$$;

create or replace function public.namecard_save(p_mobile text, p_slug text, p_show boolean default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me_row public.team_members;
  v_mobile text := nullif(btrim(coalesce(p_mobile, '')), '');
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_show boolean;
  now_slug text;
  said text := '';
begin
  select * into me_row from public.team_members t
   where t.auth_user_id = auth.uid() and t.active limit 1;
  if me_row.id is null then return jsonb_build_object('error', 'not-team'); end if;
  v_show := coalesce(p_show, me_row.card_mobile);
  if v_mobile is not null and length(regexp_replace(v_mobile, '\D', '', 'g')) not between 8 and 15 then
    return jsonb_build_object('error', 'bad-mobile');
  end if;
  if v_slug <> '' and v_slug !~ '^[a-z0-9][a-z0-9._-]{0,79}$' then
    return jsonb_build_object('error', 'slug-shape');
  end if;
  if v_mobile is not distinct from me_row.mobile and v_slug = coalesce(me_row.card_slug, '')
     and v_show = me_row.card_mobile then
    return jsonb_build_object('ok', true, 'slug', me_row.card_slug, 'show_mobile', me_row.card_mobile);
  end if;
  begin
    update public.team_members set mobile = v_mobile, card_slug = nullif(v_slug, ''), card_mobile = v_show
     where id = me_row.id
     returning card_slug into now_slug;
  exception when others then
    if sqlerrm in ('slug-taken', 'slug-shape') then return jsonb_build_object('error', sqlerrm); end if;
    raise;
  end;
  if v_mobile is distinct from me_row.mobile then
    said := 'Mobile: ' || coalesce(me_row.mobile, 'not set') || ' → ' || coalesce(v_mobile, 'not set');
  end if;
  if v_show <> me_row.card_mobile then
    said := said || case when said = '' then '' else '; ' end || 'Mobile on card: '
         || case when me_row.card_mobile then 'Show' else 'Hide' end || ' → '
         || case when v_show then 'Show' else 'Hide' end;
  end if;
  if now_slug is distinct from me_row.card_slug then
    said := said || case when said = '' then '' else '; ' end
         || 'Short link: ' || coalesce(me_row.card_slug, 'not set') || ' → ' || coalesce(now_slug, 'not set');
  end if;
  if said <> '' then
    insert into public.activity_log (actor, action, subject, detail)
    values (lower(me_row.email), 'team.edited', me_row.name, said);
  end if;
  return jsonb_build_object('ok', true, 'slug', now_slug, 'show_mobile', v_show);
end $$;

create or replace function public.client_scope_free(p_level text default 'view')
returns boolean language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where auth_user_id = auth.uid() and active limit 1;
  if t.id is null or t.is_admin or t.role = 'admin' then return true; end if;
  if coalesce(t.client_scope, 'all') = 'own' then return false; end if;
  return public.level_rank(coalesce(t.access ->> 'clients.leads', t.access ->> 'clients')) >= public.level_rank(p_level)
     and public.level_rank(coalesce(t.access ->> 'clients.past', t.access ->> 'clients')) >= public.level_rank(p_level);
end $$;

create or replace function public.team_member_remove(p_member uuid, p_erase boolean, p_name text)
returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  me      public.team_members := public.ops_me();
  v_m     public.team_members;
  v_email text;
  v_uid   uuid;
begin
  if me.id is null or not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_m from public.team_members x where x.id = p_member for update;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(btrim(v_m.name)) then return jsonb_build_object('error', 'bad-name'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  v_email := v_m.email;
  v_uid := public.team_login_of(v_m.auth_user_id, v_email);
  update public.team_members x set active = false, removed_at = coalesce(x.removed_at, now()), card_on = false
   where x.id = p_member;
  if coalesce(p_erase, false) then
    update public.team_members x
       set mobile = null, card_mobile = false, card_email = null, card_slug = null, email = null, erased_at = now()
     where x.id = p_member;
    delete from public.health_checkins h where h.team_member_id = p_member;
    delete from public.health_talks h where h.team_member_id = p_member;
    delete from public.health_consents h where h.team_member_id = p_member;
    delete from public.health_log h where h.team_member_id = p_member;
    delete from public.push_subscriptions s where s.team_member_id = p_member;
    delete from public.guide_seen g where g.team_member_id = p_member;
    delete from public.rail_orders o where o.member_id = p_member;
    if v_uid is not null and not exists (select 1 from public.client_contacts k
                                           where k.archived_at is null
                                             and (k.auth_user_id = v_uid or lower(k.email) = lower(v_email))) then
      delete from auth.users u where u.id = v_uid;
    end if;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', v_m.name,
          'Removed from the portal · ' || case when coalesce(p_erase, false) then 'personal details deleted' else 'their data kept' end);
  return jsonb_build_object('ok', true, 'erased', coalesce(p_erase, false));
end $$;

create or replace function public.team_set_expiry_at(p_until date, p_time time)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  v_time time := case when p_until is null then null else p_time end;
  v_admin boolean := public.allowed('admin');
  n int;
begin
  if not public.allowed('team', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if p_until is not null and public.team_access_ends(p_until, v_time) <= now() then
    return jsonb_build_object('error', 'past-date');
  end if;
  update public.team_members t set access_until = p_until, access_until_time = v_time
   where t.active and t.auth_user_id is distinct from auth.uid() and not t.system
     and (v_admin or not (coalesce(t.is_admin, false) or t.role = 'admin'))
     and (t.access_until is distinct from p_until or t.access_until_time is distinct from v_time);
  get diagnostics n = row_count;
  if n > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'team.changed', 'Team',
            'Access until ' || coalesce(public.team_access_word(p_until, v_time), 'not set')
            || ' for ' || n || case when n = 1 then ' colleague' else ' colleagues' end);
  end if;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

create or replace function public.campaigns_deleted_log()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  who text := auth.jwt() ->> 'email';
  me  public.team_members;
begin
  if who is not null then
    select * into me from public.team_members where auth_user_id = auth.uid() and active limit 1;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, who, 'system'), 'campaign.deleted', old.title, coalesce(old.invoice_no, ''));
  return old;
end $$;

create or replace function public.team_access_guard()
returns trigger language plpgsql as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
  ends timestamptz := public.team_access_ends(new.access_until, new.access_until_time);
  moved boolean := new.access_until is distinct from old.access_until
                   or new.access_until_time is distinct from old.access_until_time;
begin
  /* A removal and an erasure are kept once made (2026-10-18): with a
     sign-in neither is taken back or moved; the removal function only ever
     sets them from empty. */
  if who <> '' and ((old.removed_at is not null and new.removed_at is distinct from old.removed_at)
                 or (old.erased_at is not null and new.erased_at is distinct from old.erased_at)) then
    raise exception 'removed' using hint = 'A removed colleague does not come back; add them again.';
  end if;
  if moved and who <> '' and old.auth_user_id = auth.uid() then
    raise exception 'own-expiry' using hint = 'Another admin sets your access date.';
  end if;
  if new.active and not old.active and new.removed_at is not null then
    raise exception 'removed' using hint = 'A removed colleague does not come back; add them again.';
  end if;
  if new.active and not old.active then
    if ends is not null and ends <= now() then
      raise exception 'expired-date' using hint = 'Move the access date first.';
    end if;
    new.expired_at := null;
  elsif old.expired_at is not null and moved and new.removed_at is null and (ends is null or ends > now()) then
    new.active := true;
    new.expired_at := null;
  end if;
  return new;
end $$;

create or replace function public.my_access_expired()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.team_members t
                  where t.auth_user_id = auth.uid()
                    and ((not t.active and t.expired_at is not null)
                         or (t.active and t.access_until is not null and not (t.is_admin or t.role = 'admin')
                             and public.team_access_ends(t.access_until, t.access_until_time) <= now())))
$$;

create or replace function public.verify_letter(p_doc uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.client_documents%rowtype;
  cl    public.clients%rowtype;
  me    public.team_members%rowtype;
  v_map int;
  v_n   int;
begin
  if not public.allowed('clients.documents') then return jsonb_build_object('error', 'not-allowed'); end if;
  select * into d from public.client_documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  if d.superseded_by is not null then return jsonb_build_object('error', 'superseded'); end if;
  if d.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;

  -- Verifying twice is verifying once.
  if d.verified_at is not null then
    return jsonb_build_object('ok', true, 'repeat', true, 'confirmed', 0);
  end if;

  -- A letter issued before this change has no mappings, so there is nothing
  -- to confirm and no guess is made. It stays history.
  select count(*) into v_map from public.client_document_services where document_id = p_doc;
  if v_map = 0 or v_map <> coalesce(jsonb_array_length(d.lines), -1) then
    return jsonb_build_object('error', 'no-mapping');
  end if;

  /* What the client signed is the letter's snapshot. A line removed since,
     or one whose quantity, rate, term, adjustment or tax code moved since, is not
     what was signed, so nothing is confirmed (audit S4, 2026-10-10): the
     letter is reissued, or the line put back as it was. */
  if exists (select 1 from public.client_document_services m
               join public.client_services cs on cs.id = m.service_id
              where m.document_id = p_doc and cs.archived_at is not null) then
    return jsonb_build_object('error', 'archived-line');
  end if;
  if exists (select 1 from jsonb_array_elements(d.lines) l
               join public.client_services cs on cs.id = (l ->> 'service_id')::uuid
              where l ? 'service_id'
                and ((l ->> 'qty')::numeric is distinct from cs.qty
                  or (l ->> 'rate')::numeric is distinct from cs.rate
                  or (l ->> 'tenure')::int is distinct from greatest(1, coalesce(cs.tenure, 1))
                  or (l ? 'term_adjust' and (l ->> 'term_adjust')::boolean is distinct from coalesce(cs.term_adjust, false))
                  or (l ? 'term_pct' and (l ->> 'term_pct')::numeric is distinct from cs.term_pct)
                  or (l ? 'tax_code' and nullif(l ->> 'tax_code', '') is distinct from cs.tax_code))) then
    return jsonb_build_object('error', 'changed-terms');
  end if;

  update public.client_services cs
     set state = 'confirmed'
    from public.client_document_services m
   where m.document_id = p_doc and cs.id = m.service_id
     and cs.archived_at is null and cs.state <> 'confirmed';
  get diagnostics v_n = row_count;

  select * into me from public.team_members where auth_user_id = auth.uid() and active limit 1;
  update public.client_documents
     set verified_at = now(), verified_by = coalesce(me.name, who)
   where id = p_doc;

  select * into cl from public.clients where id = d.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.verified', cl.name,
          d.number || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end || ' confirmed');
  return jsonb_build_object('ok', true, 'confirmed', v_n);
end $$;

create or replace function public.is_team()
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.team_members t
    where t.active and t.auth_user_id = auth.uid()
      and (t.access_until is null or t.is_admin or t.role = 'admin'
           or public.team_access_ends(t.access_until, t.access_until_time) > now())
      and public.team_place_ok(t.is_admin or t.role = 'admin', t.id))
$$;

create or replace function public.ops_me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
   where t.active and t.auth_user_id = auth.uid()
     and (t.access_until is null or t.is_admin or t.role = 'admin'
          or public.team_access_ends(t.access_until, t.access_until_time) > now())
     and public.team_place_ok(t.is_admin or t.role = 'admin', t.id)
   limit 1
$$;

create or replace function public.me()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
  where t.auth_user_id = auth.uid() and t.active
    and (t.access_until is null or t.is_admin or t.role = 'admin'
         or public.team_access_ends(t.access_until, t.access_until_time) > now())
    and public.team_place_ok(t.is_admin or t.role = 'admin', t.id)
  limit 1
$$;

create or replace function public.abroad_who()
returns public.team_members
language sql security definer stable set search_path = public as $$
  select * from public.team_members t
  where t.auth_user_id = auth.uid() and t.active
    and (t.access_until is null or t.is_admin or t.role = 'admin'
         or public.team_access_ends(t.access_until, t.access_until_time) > now())
  limit 1
$$;

create or replace function public.team_member_seen(p_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'last_sign_in_at', (select u.last_sign_in_at from auth.users u
                                where u.id = t.auth_user_id),
           'last_seen_at', t.last_seen_at,
           'invited_at', (select max(i.created_at) from public.team_invites i
                           where lower(i.email) = lower(t.email) and i.kind = 'team'))
    from public.team_members t
   where t.id = p_id and t.erased_at is null and public.allowed('team', 'manage')
$$;

create or replace function public.page_set(p_pages text[], p_kind text, p_note text default null, p_note_zh text default null,
                                           p_starts timestamptz default null, p_ends timestamptz default null,
                                           p_whatsapp boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_k text;
  v_on boolean := coalesce(p_kind, 'none') <> 'none';
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_zh text := nullif(btrim(coalesce(p_note_zh, '')), '');
  v_was text;
  v_bits text[] := '{}';
  v_word text;
  v_when text := '';
  f public.app_flags;
begin
  if not public.ops_granted('team.upgrade', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(array_length(p_pages, 1), 0) = 0
     or exists (select 1 from unnest(p_pages) k where not (k = any (public.page_keys()))) then
    return jsonb_build_object('error', 'bad-page');
  end if;
  if coalesce(p_kind, 'none') not in ('none', 'upgrade', 'paused') then return jsonb_build_object('error', 'bad-kind'); end if;
  if v_on and p_ends is not null and p_ends <= greatest(coalesce(p_starts, now()), now()) then
    return jsonb_build_object('error', 'bad-window');
  end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where t.auth_user_id = auth.uid() and t.active limit 1;
  v_word := case p_kind when 'upgrade' then 'Upgrade in progress' when 'paused' then 'Temporarily unavailable' else 'Available' end;
  for v_k in select distinct k from unnest(p_pages) k loop
    select * into f from public.app_flags where key = 'page:' || v_k;
    v_was := case when f.key is not null and f.on_now and (f.ends_at is null or f.ends_at > now())
                  then case coalesce(f.kind, 'upgrade') when 'paused' then 'Temporarily unavailable' else 'Upgrade in progress' end
                  else 'Available' end;
    insert into public.app_flags (key, on_now, note, note_zh, starts_at, ends_at, set_by, set_at, kind, whatsapp)
    values ('page:' || v_k, v_on, case when v_on then left(v_note, 300) end, case when v_on then left(v_zh, 300) end,
            case when v_on and p_starts > now() then p_starts end, case when v_on then p_ends end,
            v_who, now(), case when v_on then p_kind end, v_on and coalesce(p_whatsapp, false))
    on conflict (key) do update
      set on_now = excluded.on_now, note = excluded.note, note_zh = excluded.note_zh, starts_at = excluded.starts_at,
          ends_at = excluded.ends_at, set_by = excluded.set_by, set_at = excluded.set_at, kind = excluded.kind,
          whatsapp = excluded.whatsapp;
    v_bits := v_bits || (public.page_name(v_k) || ': ' || v_was || ' → ' || v_word);
  end loop;
  if v_on and p_starts > now() then
    v_when := ' · from ' || public.register_day((p_starts at time zone 'Asia/Kuala_Lumpur')::date) || ' ' ||
              to_char(p_starts at time zone 'Asia/Kuala_Lumpur', 'HH24:MI');
  end if;
  if v_on and p_ends is not null then
    v_when := v_when || ' · until ' || public.register_day((p_ends at time zone 'Asia/Kuala_Lumpur')::date) || ' ' ||
              to_char(p_ends at time zone 'Asia/Kuala_Lumpur', 'HH24:MI');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Portal',
          'Page availability: ' || array_to_string(v_bits, ', ') || v_when ||
          case when v_on then coalesce(' · ' || left(v_note, 300), '') else '' end);
  return jsonb_build_object('ok', true, 'pages', public.page_states_all());
end $$;

create or replace function public.portal_contact_name(p_client uuid)
returns text
language sql stable security definer set search_path = public as $$
  select k.name
    from public.client_contacts k
   where p_client is not null
     and k.client_id = p_client
     and k.portal_access and k.archived_at is null
     and k.auth_user_id = auth.uid()
     and p_client in (select public.portal_clients())
   order by k.is_primary desc
   limit 1
$$;

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
    "analysis":"Brand analyses","checklist":"Checklists","analytics":"Analytics analyses","agent":"Assistant","next":"Next batch"}';
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'per_report' then
    if p_daily is not null and p_daily > 1 then return jsonb_build_object('error', 'bad-limit'); end if;
    v_name := 'One draft and one check per report per day';
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
   where x.auth_user_id = auth.uid() and x.active limit 1;
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

create or replace function public.team_super_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.team_members s
                      where s.system and s.active and s.removed_at is null)
      or exists (select 1 from public.team_members s
                  where s.system and s.active and s.removed_at is null
                    and s.auth_user_id = auth.uid());
$$;

create or replace function public.team_admin_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  who      text := lower(coalesce(auth.jwt() ->> 'email', ''));
  was      boolean;
  will     boolean;
begin
  if who = '' or pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op <> 'INSERT' then was := coalesce(old.is_admin, false) or old.role = 'admin'; end if;
  if tg_op <> 'DELETE' then
    will := new.role = 'admin'
         or exists (select 1 from public.team_roles r where r.slug = new.role and r.is_admin);
  end if;
  /* Making or removing an admin is the super admin's alone; its own row
     is `team_members_system_guard`'s. */
  if not public.team_super_ok() and not (tg_op <> 'INSERT' and coalesce(old.system, false)) then
    if tg_op = 'DELETE' and was then
      raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin removes an admin.';
    end if;
    if tg_op <> 'DELETE' and will and not coalesce(was, false) then
      raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin makes a colleague admin.';
    end if;
    if tg_op = 'UPDATE' and was and (
         new.role is distinct from old.role
      or new.is_admin is distinct from old.is_admin
      or new.active is distinct from old.active
      or new.removed_at is distinct from old.removed_at) then
      raise exception 'super-only' using errcode = '42501', hint = 'Only the super admin changes an admin.';
    end if;
  end if;
  if public.allowed('admin') then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if tg_op = 'DELETE' then
    if was then
      raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin removes an admin.';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and new.role is distinct from old.role and old.auth_user_id = auth.uid() then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes your own group.';
  end if;
  if will and not coalesce(was, false) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin makes a colleague admin.';
  end if;
  if tg_op = 'UPDATE' and was and (
       new.role is distinct from old.role
    or new.is_admin is distinct from old.is_admin
    or new.access is distinct from old.access
    or new.access_until is distinct from old.access_until
    or new.access_until_time is distinct from old.access_until_time
    or new.active is distinct from old.active
    or new.removed_at is distinct from old.removed_at
    or lower(new.email) is distinct from lower(old.email)) then
    raise exception 'admin-only' using errcode = '42501', hint = 'Only an admin changes an admin.';
  end if;
  return new;
end $$;

create or replace function public.client_row_seen_by(p_stage text, p_owner text, p_owner_id uuid, p_sales_by uuid, p_level text)
returns boolean language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  band text;
begin
  select * into t from public.team_members
   where auth_user_id = auth.uid() and active limit 1;
  if t.id is null or t.is_admin or t.role = 'admin' then return true; end if;
  band := case when p_stage in ('lead', 'contacted', 'proposal') then 'clients.leads'
               when p_stage = 'past' then 'clients.past' end;
  if band is not null and public.level_rank(coalesce(t.access ->> band, t.access ->> 'clients'))
                          < public.level_rank(p_level) then
    return false;
  end if;
  if coalesce(t.client_scope, 'all') = 'own' then
    if p_sales_by is not null and p_sales_by = t.id then return true; end if;
    if nullif(btrim(coalesce(p_owner, '')), '') is null then
      return coalesce(band = 'clients.leads', false);
    end if;
    return p_owner_id is not null and p_owner_id = t.id;
  end if;
  return true;
end $$;

create or replace function public.ops_granted(p_key text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare t public.team_members;
begin
  select * into t from public.team_members
   where active and auth_user_id = auth.uid() limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if t.access_until is not null
     and public.team_access_ends(t.access_until, t.access_until_time) <= now() then return false; end if;
  if not public.team_place_ok(false, t.id) then return false; end if;
  /* Creator payments and supplier bank details follow their section where
     Sensitive details is on (GROUP SWITCHES, 2026-11-17). */
  if p_key in ('campaigns.pay', 'suppliers.pay') then
    return t.sensitive_on and public.level_rank(t.access ->> split_part(p_key, '.', 1)) >= public.level_rank(p_level);
  end if;
  return public.level_rank(t.access ->> p_key) >= public.level_rank(p_level);
end $$;

create or replace function public.allowed(p_section text, p_level text)
returns boolean
language plpgsql security definer stable set search_path = public as $$
declare
  t public.team_members;
  k text := lower(coalesce(p_section, ''));
  sv text;
  lv text;
begin
  select * into t from public.team_members x
    where x.auth_user_id = auth.uid() and x.active
      and (x.access_until is null or x.is_admin or x.role = 'admin'
           or public.team_access_ends(x.access_until, x.access_until_time) > now())
    limit 1;
  if t.id is null then return false; end if;
  if t.is_admin or t.role = 'admin' then return true; end if;
  if not public.team_place_ok(false, t.id) then return false; end if;
  /* Sensitive details (GROUP SWITCHES, 2026-11-17). A part that widens its
     section (granted, the access_keys rows of that tier) is never capped. */
  if k in ('clients.billing', 'campaigns.pay', 'suppliers.pay') and not t.sensitive_on then return false; end if;
  lv := t.access ->> k;
  if position('.' in k) > 0 then
    sv := t.access ->> split_part(k, '.', 1);
    if k in ('campaigns.pay', 'suppliers.pay') or lv is null then lv := sv;
    elsif not exists (select 1 from public.access_keys a where a.key = k and a.tier = 'granted')
      and public.level_rank(lv) > public.level_rank(sv) then lv := sv;
    end if;
  end if;
  return public.level_rank(lv) >= public.level_rank(p_level);
end $$;

create or replace function public.clients_owner_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if (old.owner_id is not null or nullif(btrim(coalesce(old.owner, '')), '') is not null)
     and (new.owner_id is distinct from old.owner_id or coalesce(btrim(new.owner), '') is distinct from coalesce(btrim(old.owner), ''))
     and (select t.id from public.team_members t
           where t.auth_user_id = auth.uid() and t.active limit 1) is not null
     and not public.allowed('clients', 'manage') and not public.allowed('team', 'manage') then
    raise exception 'Only a colleague at Clients Full Access can change the Person in charge. Please ask one.' using errcode = '42501', hint = 'owner-change';
  end if;
  return new;
end $$;

create or replace function public.build_require(p_commit text, p_built timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_who text;
  v_was jsonb;
  v_commit text := lower(nullif(btrim(coalesce(p_commit, '')), ''));
begin
  if not public.ops_granted('team.upgrade', 'work') then return jsonb_build_object('error', 'denied'); end if;
  /* A build time ahead of now is no build Pages has served. */
  if v_commit is not null and (v_commit !~ '^[0-9a-f]{7,40}$' or p_built is null
      or p_built < timestamptz '2023-08-14 00:00+08' or p_built > now()) then
    return jsonb_build_object('error', 'bad-build');
  end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where t.auth_user_id = auth.uid() and t.active limit 1;
  v_was := public.build_min();
  insert into public.app_flags (key, on_now, note, starts_at, set_by, set_at)
  values ('build:min', v_commit is not null, v_commit, case when v_commit is not null then p_built end, v_who, now())
  on conflict (key) do update
    set on_now = excluded.on_now, note = excluded.note, starts_at = excluded.starts_at,
        set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Portal',
          'Latest version required: ' || public.build_word(v_was ->> 'commit', (v_was ->> 'built')::timestamptz)
          || ' → ' || public.build_word(v_commit, case when v_commit is not null then p_built end));
  return jsonb_build_object('ok', true, 'min', public.build_min(), 'was', v_was);
end $$;

create or replace function public.team_member_sessions(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
begin
  if not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('sessions', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', x.id, 'device', public.session_device(x.user_agent), 'created_at', x.created_at,
             'last_at', x.last_at, 'mine', x.id::text = coalesce(auth.jwt() ->> 'session_id', ''))
           order by x.last_at desc nulls last)
      from (select s.id, s.user_agent, s.created_at,
                   greatest(s.updated_at, s.refreshed_at at time zone 'UTC', s.created_at) as last_at
              from auth.sessions s
             where s.user_id = m.auth_user_id
               and (s.not_after is null or s.not_after > now())) x), '[]'::jsonb));
end $$;

create or replace function public.team_sessions_idle_end(p_now timestamptz default now())
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  v_days integer := coalesce(public.app_setting('session_idle_days', (p_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::integer;
  v_n    integer := 0;
begin
  if v_days > 0 then
    delete from auth.sessions s
     where greatest(s.updated_at, s.refreshed_at at time zone 'UTC', s.created_at) < p_now - make_interval(days => v_days)
       and exists (select 1 from public.team_members t
                    where t.auth_user_id = s.user_id and t.erased_at is null)
       and not exists (select 1 from public.team_members t
                        where t.auth_user_id = s.user_id and coalesce(t.system, false));
    get diagnostics v_n = row_count;
    if v_n > 0 then
      insert into public.activity_log (actor, action, subject, detail)
      values ('system', 'team.changed', 'Signed-in devices',
              v_n || case when v_n = 1 then ' device was' else ' devices were' end || ' signed out after ' || v_days ||
              case when v_days = 1 then ' day' else ' days' end || ' unused.');
    end if;
  end if;
  perform public.job_beat('session-idle', true,
    case when v_days > 0 then v_n || ' signed out' else 'off' end);
  return v_n;
end $$;

create or replace function public.team_members_system_guard()
returns trigger
language plpgsql set search_path = public as $$
declare
  who text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if who = '' or pg_trigger_depth() > 1 then return new; end if;
  if new.system is distinct from old.system then
    raise exception 'system-account' using hint = 'A system account is set from the database.';
  end if;
  if old.system and old.auth_user_id is distinct from auth.uid() and (
       new.active is distinct from old.active
    or new.access_until is distinct from old.access_until
    or new.access_until_time is distinct from old.access_until_time
    or new.role is distinct from old.role
    or new.is_admin is distinct from old.is_admin
    or new.removed_at is distinct from old.removed_at
    or new.erased_at is distinct from old.erased_at
    or lower(new.email) is distinct from lower(old.email)) then
    raise exception 'system-account' using hint = 'This is a system account.';
  end if;
  return new;
end $$;

create or replace function public.issue_letter(
  p_client    uuid,
  p_services  uuid[],
  p_idem      text,
  p_subtotal  numeric,
  p_tax       numeric,
  p_total     numeric,
  p_deal      jsonb   default '{}'::jsonb,
  p_replaces  uuid    default null,
  p_renewal   boolean default false,
  /* A reference somebody typed. Blank is the ordinary case and the counter
     below makes the number; where one is typed it is checked against every
     document that stands and the counter is not advanced, so filling a gap
     by hand never costs the next letter its place in the sequence. */
  p_serial    text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  ct     public.client_contacts%rowtype;
  me     public.team_members%rowtype;
  v_ym   text;
  v_seq  int;
  v_try  int;
  v_no   text;
  v_id   uuid;
  v_lines jsonb;
  v_n    int;
  v_bad  int;
  v_old  public.client_documents%rowtype;
  v_term int;
  v_each numeric;
  v_etax numeric;
  v_once numeric;
  v_otax numeric;
  v_sub  numeric;
  v_tax  numeric;
  v_tot  numeric;
  v_pct  numeric;
  v_qid  uuid;
  v_q    public.quotations%rowtype;
  v_tp   numeric;
  v_tadj boolean;
  v_qterm int;
  v_msub numeric;
  v_span numeric;
  v_even boolean;
  v_qt   jsonb;
  v_month boolean;
  v_terms jsonb;
  v_ent  public.billing_entities%rowtype;
  v_ect  public.client_contacts%rowtype;
  v_on   date := public.doc_day_of(p_deal ->> 'date');
begin
  if not public.allowed('clients.documents') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  /* The letter's own date (2026-11-12, the user: a letter may be
     backdated): its reference's month, the SST and the rate in force, and
     the quotation still standing on that day; today where none is chosen. */
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  v_on := coalesce(v_on, (timezone('Asia/Kuala_Lumpur', now()))::date);
  if p_client is null or p_services is null or array_length(p_services, 1) is null then
    return jsonb_build_object('error', 'no-lines');
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;

  -- Bill to (2026-10-29): a billing entity of this client other than its
  -- main, named in the deal, is the one the letter bills: its registered
  -- name, numbers, address and finance email stand in for the client's in
  -- the snapshot, and its billing contact is the letter's Attn where one is
  -- set and live. None named is the main entity, the client's own billing.
  if nullif(btrim(coalesce(p_deal ->> 'entity', '')), '') is not null then
    if (p_deal ->> 'entity') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('error', 'bad-entity');
    end if;
    select e.* into v_ent from public.billing_entities e
      join public.client_entities ce on ce.entity_id = e.id and ce.client_id = p_client
     where e.id = (p_deal ->> 'entity')::uuid;
    if v_ent.id is null then return jsonb_build_object('error', 'bad-entity'); end if;
    if coalesce(btrim(v_ent.legal_name), '') = '' or coalesce(btrim(v_ent.company_no), '') = ''
       or coalesce(btrim(v_ent.billing_address), '') = '' then
      return jsonb_build_object('error', 'entity-incomplete');
    end if;
    cl.legal_name := v_ent.legal_name; cl.company_no := v_ent.company_no;
    cl.company_no_old := v_ent.company_no_old; cl.tin := v_ent.tin; cl.sst_no := v_ent.sst_no;
    cl.finance_email := v_ent.finance_email; cl.billing_address := v_ent.billing_address;
  end if;

  -- The letter's own terms, one point a line, kept with what it was issued
  -- with and printed under TERMS after the term and the validity
  -- (2026-10-23): ten at most, each 1 to 400 characters.
  v_terms := coalesce((select jsonb_agg(btrim(t)) from jsonb_array_elements_text(
               case when jsonb_typeof(p_deal -> 'terms') = 'array' then p_deal -> 'terms' else '[]'::jsonb end) t
             where btrim(t) <> ''), '[]'::jsonb);
  if jsonb_array_length(v_terms) > 10
     or exists (select 1 from jsonb_array_elements_text(v_terms) t where length(t) > 400) then
    return jsonb_build_object('error', 'bad-terms');
  end if;

  -- The Client ID is what the serial is built from, so there is no letter
  -- without one. Staff enter it on the record; nothing invents it. A typed
  -- reference needs no code, because nothing is being built.
  v_no := nullif(btrim(coalesce(p_serial, '')), '');
  if v_no is null and coalesce(btrim(cl.client_code), '') = '' then
    return jsonb_build_object('error', 'no-client-code');
  end if;

  -- The same submission, pressed twice, is one letter. Answered before any
  -- number is reserved, so a double click cannot spend a serial either.
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.client_documents
      where client_id = p_client and idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
    end if;
  end if;

  -- A typed reference is checked before anything is written: the same shape
  -- the Register accepts, and refused where a document still holds it.
  if v_no is not null then
    if v_no !~ '^[A-Za-z0-9/._-]{3,40}$' then
      return jsonb_build_object('error', 'serial-shape');
    end if;
    if public.serial_taken(v_no) then
      return jsonb_build_object('error', 'serial-taken');
    end if;
  end if;

  -- Every id must be this client's own live line, and in a state this letter
  -- may carry: To quote always, Confirmed only on a deliberate renewal.
  select count(*) into v_bad from unnest(p_services) s(id)
    left join public.client_services cs
      on cs.id = s.id and cs.client_id = p_client and cs.archived_at is null
    where cs.id is null
       or (cs.state = 'confirmed' and not p_renewal)
       or cs.state not in ('quoted', 'confirmed');
  if v_bad > 0 then return jsonb_build_object('error', 'bad-lines'); end if;

  -- The lines are held while this letter is made (2026-11-07): two
  -- presses on the same lines take them in turn, so the second reads the
  -- first one's letter below and is refused, never a second live letter.
  perform 1 from public.client_services where id = any(p_services) order by id for update;

  -- A line already on a live letter is not offered again by accident. The way
  -- through is to void that letter, or to name it as the one being replaced.
  select count(*) into v_bad
    from public.client_document_services m
    join public.client_documents d on d.id = m.document_id
   where m.service_id = any(p_services)
     and d.voided_at is null
     and d.superseded_by is null
     and d.verified_at is null
     and (p_replaces is null or d.id <> p_replaces);
  if v_bad > 0 then return jsonb_build_object('error', 'already-quoted'); end if;

  if p_replaces is not null then
    -- The letter replaced is held while it is read (2026-11-08, audit 5):
    -- two Replace presses at once on one letter, ticking different lines,
    -- each read it live and both issued. The second now waits and reads it
    -- replaced.
    select * into v_old from public.client_documents
      where id = p_replaces and client_id = p_client
      for update;
    if v_old.id is null then return jsonb_build_object('error', 'no-replaces'); end if;
    if v_old.verified_at is not null then return jsonb_build_object('error', 'replaces-verified'); end if;
    -- A letter already replaced, or void, is no longer the live one: a
    -- second Replace would leave two letters on its lines (2026-11-07).
    if v_old.superseded_by is not null then return jsonb_build_object('error', 'superseded'); end if;
    if v_old.voided_at is not null then return jsonb_build_object('error', 'voided'); end if;
  end if;

  select * into ct from public.client_contacts
    where client_id = p_client and archived_at is null
    order by (id = cl.bill_contact_id) desc, is_primary desc, name limit 1;
  -- The brand's billing contact for the entity billed (the one named, else
  -- its primary): its own choice, else the entity's shared one, else its
  -- live main contact (2026-10-31).
  v_ect := public.entity_contact(coalesce(v_ent.id, public.client_main_entity(p_client)), p_client);
  if v_ect.id is not null then ct := v_ect; end if;
  select * into me from public.team_members where auth_user_id = auth.uid() and active limit 1;

  -- A letter is signed by a person. issued_by is this row's name, so a team
  -- row named "Superadmin" printed that word under the agency's name on a client's
  -- letterhead. Refuse rather than draw a permission as a signatory.
  if not public.issuer_name_ok(me.name) then
    return jsonb_build_object('error', 'issuer-name', 'name', coalesce(me.name, ''));
  end if;

  -- The snapshot is built from the stored rows, never from what the browser
  -- sent: the words on a letter are the words the record held at that moment.
  select jsonb_agg(jsonb_build_object(
           'label', cs.label, 'unit', coalesce(cs.unit, ''), 'note', coalesce(cs.note, ''),
           'detail', coalesce(cs.detail, ''), 'state', cs.state,
           'qty', cs.qty, 'rate', cs.rate,
           'tenure', greatest(1, coalesce(cs.tenure, 1)),
           'start_on', coalesce(cs.start_on, ''),
           -- The line's own answer to whether its term prices it. Written into
           -- the snapshot because the letter is redrawn from it, and a letter
           -- must print the same figure every time it is drawn. A snapshot
           -- taken before this key existed carries none, which money.js reads
           -- as on, so those letters redraw as they were issued.
           'term_adjust', coalesce(cs.term_adjust, false),
           -- And the percentage that tick applies, so a later rate card can
           -- never move a figure this letter printed. Null on a line quoted
           -- before the column existed, which money.js reads as that card.
           'term_pct', cs.term_pct,
           'tax', cl.sst_applies is not false,
           -- The line's own tax code and its rate as issued (2026-10-22);
           -- none is the client's SST, as before.
           'tax_code', cs.tax_code,
           'tax_pct', (select t.rate from public.tax_codes t where t.code = cs.tax_code),
           'service_id', cs.id)
           order by cs.created_at)
    into v_lines
    from public.client_services cs
   where cs.id = any(p_services);
  if v_lines is null then return jsonb_build_object('error', 'no-lines'); end if;
  /* A line's tax code is one the team holds and offers (2026-10-22). */
  if exists (select 1 from public.client_services cs
              where cs.id = any(p_services) and cs.tax_code is not null
                and not exists (select 1 from public.tax_codes t where t.code = cs.tax_code and t.active)) then
    return jsonb_build_object('error', 'bad-tax');
  end if;

  /* The price is the database's (audit S4, 2026-10-10), worked as the
     letter draws it (js/documents.js priceOf, js/money.js rateFor): each
     line's rate with its term on it, rounded to the cent. Where every line
     of more than a month shares one term, those lines are priced by the
     month and times the term, and a line of one month is a one-off item
     with its own SST (2026-10-15: a one-off item beside them no longer
     turns the letter into one whole total); otherwise every line is its
     whole amount. SST at the rate in force today unless the client is
     exempt. The page's figures are kept only where they agree to the sen,
     so a line changed since the sheet opened, or a figure typed in a
     browser, is refused (`stale`) and the sheet reads the lines again. */
  select case when count(distinct greatest(1, coalesce(cs.tenure, 1)))
                     filter (where greatest(1, coalesce(cs.tenure, 1)) > 1) = 1
              then max(greatest(1, coalesce(cs.tenure, 1))) else 0 end
    into v_term
    from public.client_services cs where cs.id = any(p_services);
  /* A letter whose every line came from one quotation is priced as that
     quotation was (audit F, 2026-10-17), exactly as `quote_price` and
     `quote_adjust` total it (2026-10-17, the review's finding 7): a line
     the quotation bills by the month (`quotation_offer` ticks its term) is
     a monthly line whatever months Build quote gave it, its percentage
     taken once on their subtotal; a line with no term is one-off; SST at
     the quotation's rate. The page's figures are held to the same price
     (js/documents.js priceOf). */
  select case when count(*) filter (where cs.quotation_id is null) = 0
                   and count(distinct cs.quotation_id) = 1 then min(cs.quotation_id::text)::uuid end,
         coalesce(bool_and(greatest(1, coalesce(cs.tenure, 1)) = 1) filter (where not coalesce(cs.term_adjust, false)), true),
         coalesce(max(cs.term_pct) filter (where coalesce(cs.term_adjust, false)), 0)
    into v_qid, v_tadj, v_tp
    from public.client_services cs where cs.id = any(p_services);
  /* Only while the quotation still stands (2026-10-17, the review's
     finding 2): unexpired by Malaysia's day and not removed. A renewal, or a
     letter replacing one after the quotation lapsed, is priced on today's
     rates, as any other letter. */
  if v_qid is not null and v_tadj and not coalesce(p_renewal, false) then
    select * into v_q from public.quotations q
     where q.id = v_qid and q.removed_at is null
       and q.valid_until >= v_on;
  end if;
  if v_q.id is not null then
    /* As quote_adjust totals it: the monthly lines' subtotal of quantity ×
       rate, the percentage once on it; where every one runs the quotation's
       term, a month's excl. SST, its SST rounded once, times the term; where
       Build quote gave a line months of its own, the whole span (each line's
       amount × its months) with the percentage and SST taken once on it.
       One-off lines and their SST apart. */
    v_qterm := greatest(1, coalesce((v_q.totals->>'term')::int, 1));
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce((v_q.totals->>'sst_pct')::numeric, 0) end;
    /* The lines as the quotation reads them (a line with its term ticked is
       monthly, on its own months), totalled by the one calculation every
       quotation shares (2026-10-18). */
    v_qt := public.quote_totals(
      (select coalesce(jsonb_agg(jsonb_build_object(
                'basis', case when coalesce(cs.term_adjust, false) then 'month' else 'once' end,
                'qty', coalesce(cs.qty, 0), 'rate', coalesce(cs.rate, 0),
                'months', greatest(1, coalesce(cs.tenure, 1)),
                /* each line its own percentage, as the quotation priced it
                   (2026-11-24); one with none takes the largest held */
                'pct', case when coalesce(cs.term_adjust, false) then cs.term_pct end,
                'sst', (select t.rate from public.tax_codes t where t.code = cs.tax_code))), '[]'::jsonb)
         from public.client_services cs where cs.id = any(p_services)),
      v_qterm, v_tp, v_pct);
    v_month := jsonb_typeof(v_qt->'month') = 'object';
    v_once := coalesce((v_qt->'once'->>'subtotal')::numeric, 0);
    v_otax := coalesce((v_qt->'once'->>'sst')::numeric, 0);
    if not v_month then
      v_sub := round(v_once, 2);
      v_tax := v_otax;
    elsif (v_qt->>'even')::boolean then
      v_each := (v_qt->'month'->>'excl')::numeric;
      v_etax := (v_qt->'month'->>'sst')::numeric;
      /* As the page totals it (js/documents.js quotePrice): a month incl.
         SST rounded, times the term, beside the one-off items incl. SST
         (2026-11-07: 1.5 × 333.33 for 12 months is 6,480.00, never
         6,479.94). */
      v_sub := round(round(v_each * v_qterm, 2) + v_once, 2);
      v_tax := v_etax * v_qterm + v_otax;
      v_tot := round(round(v_each + v_etax, 2) * v_qterm, 2) + round(v_once + v_otax, 2);
    else
      v_sub := (v_qt->>'span_excl')::numeric + round(v_once, 2);
      v_tax := (v_qt->>'span_incl')::numeric + round(v_once, 2) + v_otax - v_sub;
    end if;
    if not (v_month and (v_qt->>'even')::boolean) then v_tot := v_sub + v_tax; end if;
    /* The letter keeps what it was priced on, so a redraw prints the same:
       the quotation, its SST and its term (a snapshot with no `quote_term`
       was priced before this, and redraws as it was). */
    select jsonb_agg(l.e || jsonb_build_object('quotation_id', v_qid, 'quote_sst', v_pct, 'quote_term', v_qterm) order by l.n)
      into v_lines from jsonb_array_elements(v_lines) with ordinality l(e, n);
  else
    v_pct := case when cl.sst_applies is false then 0
                  else coalesce(public.app_setting('sst_pct', v_on), 0) end;
    /* Each line at its own SST rate (2026-10-22): its tax code's, else the
       client's. The SST is worked a rate at a time, rounded once each, so
       a letter on one rate prices as it always did. */
    with x as (
      select greatest(1, coalesce(cs.tenure, 1)) as n,
             coalesce(cs.qty, 0) *
             round(coalesce(cs.rate, 0) *
               case when cs.term_adjust is false then 1
                    when cs.term_pct is not null then 1 + cs.term_pct / 100
                    else case greatest(1, coalesce(cs.tenure, 1))
                           when 3 then 1 / 0.9 when 12 then 0.95 when 24 then 0.9 else 1 end
               end, 2) as v,
             coalesce((select t.rate from public.tax_codes t where t.code = cs.tax_code), v_pct) as r
        from public.client_services cs where cs.id = any(p_services)
    ), y as (
      select r,
             coalesce(sum(v) filter (where v_term > 0 and n = v_term), 0) as e,
             coalesce(sum(v * n) filter (where v_term = 0 or n <> v_term), 0) as o
        from x group by r
    )
    select coalesce(sum(e), 0), coalesce(sum(o), 0),
           coalesce(sum(round(e * r) / 100), 0), coalesce(sum(round(o * r) / 100), 0)
      into v_each, v_once, v_etax, v_otax
      from y;
    v_sub := round(v_each * greatest(v_term, 1), 2) + round(v_once, 2);
    v_tax := round(v_etax * greatest(v_term, 1), 2) + v_otax;
    v_tot := round(round(v_each + v_etax, 2) * greatest(v_term, 1), 2) + round(v_once + v_otax, 2);
  end if;
  if abs(coalesce(p_subtotal, -1) - v_sub) > 0.01 or abs(coalesce(p_tax, -1) - v_tax) > 0.01
     or abs(coalesce(p_total, -1) - v_tot) > 0.01 then
    return jsonb_build_object('error', 'stale', 'subtotal', v_sub, 'tax', v_tax, 'total', v_tot);
  end if;

  -- A typed reference spends no sequence number: the counter is the office's
  -- record of how many letters it has issued this month, and a person filling
  -- a gap by hand has not issued one more.
  if v_no is null then
    -- The month is Malaysian, because the office that numbers the letter is.
    v_ym := to_char(v_on, 'YYMM');

    -- The counter still advances on every automatic issue, and the upsert's
    -- row lock is what makes the scan below safe: a second issuer blocks here
    -- until the first has committed its letter, so the two never read the same
    -- gap as free. What the counter gives is a bound to scan within, not the
    -- number itself.
    insert into public.client_document_seq (client_id, ym, next_val)
         values (p_client, v_ym, 2)
    on conflict (client_id, ym)
      do update set next_val = public.client_document_seq.next_val + 1
      returning next_val - 1 into v_seq;

    -- The lowest free slot, not the counter's own value. A letter removed
    -- releases its reference (serial_taken stopped counting removed letters on
    -- 2026-09-20), and without this the automatic path still counted upward
    -- past the gap: a client whose first two letters were issued in testing
    -- and removed started at 03 for ever. The counter is at least the number
    -- of letters issued this month, so a free slot exists at or below it
    -- unless somebody has typed references over the same range by hand; the
    -- cap covers that and refuses rather than looping.
    --
    -- Two digits is the floor, not the ceiling: the hundredth letter of a month
    -- widens to three rather than wrapping. Not lpad(): Postgres pads AND
    -- truncates to the width it is given, so lpad('100', 2, '0') is '10' and the
    -- hundredth letter would collide with the tenth.
    v_try := 1;
    loop
      v_no := 'AQL/' || cl.client_code || '/' || v_ym ||
              case when v_try < 100 then lpad(v_try::text, 2, '0') else v_try::text end;
      exit when not public.serial_taken(v_no);
      v_try := v_try + 1;
      if v_try > greatest(v_seq, 1) + 200 then
        return jsonb_build_object('error', 'no-serial');
      end if;
    end loop;
  end if;

  insert into public.client_documents
    (client_id, kind, number, issued_at, market, subtotal, tax, total,
     bill_to, lines, issued_by, client_code, idem_key)
  values
    (p_client, 'offer', v_no, v_on,
     public.client_bill_market(cl.market, cl.bill_sgd),
     -- the database's own figures, never the page's: the sen allowed
     -- above is for the stale check alone (2026-11-24)
     round(v_sub, 2), round(v_tax, 2), round(v_tot, 2),
     jsonb_build_object(
       'name', coalesce(cl.name, ''), 'legal_name', coalesce(cl.legal_name, ''),
       'address', coalesce(cl.billing_address, ''), 'regno', coalesce(cl.company_no, ''),
       'regno_old', coalesce(cl.company_no_old, ''), 'tin', coalesce(cl.tin, ''),
       'sst_no', coalesce(cl.sst_no, ''), 'sst_applies', cl.sst_applies is not false,
       'contact', coalesce(ct.name, ''), 'contact_role', coalesce(ct.role, ''),
       'contact_salutation', coalesce(ct.salutation, ''),
       -- A Singapore client billed in RM: its market and the rate in force,
       -- so the letter reads its figure in S$ beside it, as issued.
       'market', coalesce(cl.market, 'MY'),
       'fx_sgd', case when cl.market = 'SG' and not cl.bill_sgd then public.app_setting('fx_sgd', v_on) end,
       'phone', coalesce(ct.phone, ''), 'email', coalesce(ct.email, ''),
       'finance_email', coalesce(cl.finance_email, ''),
       'client_code', cl.client_code,
       'entity_id', v_ent.id,
       'owner', coalesce(p_deal ->> 'owner', ''), 'source', coalesce(p_deal ->> 'source', ''),
       'industry', coalesce(p_deal ->> 'industry', ''), 'stage', coalesce(p_deal ->> 'stage', ''),
       'enquiry', coalesce(p_deal ->> 'enquiry', ''),
       'terms', v_terms,
       -- The validity is one of the points typed (2026-10-23): a letter
       -- sent with it in its terms prints none of its own.
       'terms_own', coalesce(p_deal ->> 'terms_own', '') = 'true'),
     v_lines, coalesce(me.name, who), cl.client_code, nullif(btrim(p_idem), ''))
  returning id into v_id;

  insert into public.client_document_services (document_id, service_id)
    select v_id, s.id from unnest(p_services) s(id)
    on conflict do nothing;

  if p_replaces is not null then
    update public.client_documents set superseded_by = v_id where id = p_replaces;
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.superseded', cl.name, v_old.number || ' replaced by ' || v_no);
  end if;

  select count(*) into v_n from public.client_document_services where document_id = v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.issued', cl.name, v_no || ' · ' || v_n || ' line' || case when v_n = 1 then '' else 's' end);

  return jsonb_build_object('ok', true, 'id', v_id, 'number', v_no);
exception
  when unique_violation then
    -- Two presses that raced past the idempotency read: the loser reads the
    -- winner's letter back rather than making a second one.
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.client_documents
        where client_id = p_client and idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'number', v_old.number);
      end if;
    end if;
    -- A typed reference two people sent at once: the loser is told the
    -- reference is spent rather than that "two letters were issued at once",
    -- which names a cause they cannot act on.
    if nullif(btrim(coalesce(p_serial, '')), '') is not null then
      return jsonb_build_object('error', 'serial-taken');
    end if;
    return jsonb_build_object('error', 'clash');
end $$;

create or replace function public.team_member_purge(p_member uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  me      public.team_members := public.ops_me();
  v_m     public.team_members;
  v_email text;
  v_uid   uuid;
  k       record;
  v_held  text[];
  v_any   boolean;
begin
  if me.id is null or not public.allowed('admin') then return jsonb_build_object('error', 'admin-only'); end if;
  select * into v_m from public.team_members x where x.id = p_member for update;
  if v_m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_m.id = me.id then return jsonb_build_object('error', 'own'); end if;
  if coalesce(v_m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if v_m.removed_at is null then return jsonb_build_object('error', 'not-removed'); end if;
  if lower(btrim(coalesce(p_name, ''))) <> lower(btrim(v_m.name)) then return jsonb_build_object('error', 'bad-name'); end if;
  if (coalesce(v_m.is_admin, false) or v_m.role = 'admin') and v_m.active
     and not exists (select 1 from public.team_members x where x.id <> v_m.id and x.active
                       and (coalesce(x.is_admin, false) or x.role = 'admin')) then
    return jsonb_build_object('error', 'last-admin');
  end if;
  /* A required key is cleared only where its rows are the colleague's own
     (review 2026-11-24: the loop deleted every row a required key held, so
     a trip they drove went from the colleagues who joined it). A trip
     another colleague joined holds the delete; a key not named here, added
     later, holds it too, never deleting what it does not know. */
  v_held := case when exists (select 1 from public.outstation_trips t
                               where t.driver_id = p_member and exists (select 1 from unnest(t.companions) c where c <> p_member))
                 then array['trips'] else '{}'::text[] end;
  for k in
    select c.conrelid::regclass as tbl, a.attname as col
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.team_members'::regclass and c.confdeltype in ('a', 'r') and a.attnotnull
       and c.conrelid::regclass::text not in ('ops_task_assignees', 'ops_work_sessions', 'ops_due_requests', 'option_qc',
         'guide_seen', 'rail_orders', 'personnel_records', 'personnel_salaries', 'delete_requests', 'outstation_trips')
  loop
    execute format('select exists (select 1 from %s where %I = $1)', k.tbl, k.col) using p_member into v_any;
    if v_any then v_held := v_held || k.tbl::text; end if;
  end loop;
  if cardinality(v_held) > 0 then return jsonb_build_object('error', 'in-use', 'held', to_jsonb(v_held)); end if;
  v_email := v_m.email;
  v_uid := public.team_login_of(v_m.auth_user_id, v_email);
  -- A trip they joined keeps itself without their name.
  update public.outstation_trips t set companions = array_remove(t.companions, p_member) where p_member = any (t.companions);
  /* A report's names (submitted, confirmed, reviewer) are cleared by their
     keys, which the report's guard holds to its functions: this is one. */
  perform set_config('adspace.sm_fn', 'on', true);
  for k in
    select c.conrelid::regclass as tbl, a.attname as col, a.attnotnull as req
      from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and c.confrelid = 'public.team_members'::regclass and c.confdeltype in ('a', 'r')
  loop
    if k.req then
      execute format('delete from %s where %I = $1', k.tbl, k.col) using p_member;
    else
      execute format('update %s set %I = null where %I = $1', k.tbl, k.col, k.col) using p_member;
    end if;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', v_m.name, 'Deleted permanently');
  delete from public.team_members x where x.id = p_member;
  perform set_config('adspace.sm_fn', 'off', true);
  if v_uid is not null and not exists (select 1 from public.team_members x
                                         where x.auth_user_id = v_uid or lower(x.email) = lower(v_email))
     and not exists (select 1 from public.client_contacts k2 where k2.archived_at is null
                       and (k2.auth_user_id = v_uid or lower(k2.email) = lower(v_email))) then
    delete from auth.users u where u.id = v_uid;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.portal_clients()
returns setof uuid
language sql security definer stable set search_path = public as $$
  select distinct c.client_id from public.client_contacts c
  where c.portal_access and c.archived_at is null and c.email is not null
    and c.auth_user_id = auth.uid()
    and public.portal_client_open(c.client_id)
    and not exists (
      select 1 from public.team_members t
      where t.active
        and (t.auth_user_id = auth.uid()
             or (t.email is not null and lower(t.email) = lower(c.email))))
$$;

create or replace function public.issue_document(
  p_type      text,
  p_client    uuid,
  p_member    uuid,
  p_serial    text,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_idem      text,
  p_salutation text default null,
  p_signed    boolean default null,
  p_supplier  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who     text := lower(auth.jwt() ->> 'email');
  t       public.doc_types%rowtype;
  cl      public.clients%rowtype;
  mb      public.team_members%rowtype;
  sp      public.suppliers%rowtype;
  me      public.team_members%rowtype;
  v_old   public.documents%rowtype;
  v_serial text;
  v_base  text;
  v_n     int;
  v_id    uuid;
  v_langs text[];
  v_signed boolean;
begin
  select * into t from public.doc_types where id = p_type and active;
  -- A letter's own date, backdated where chosen (2026-11-12): never before
  -- 14 Aug 2023 or after today; its reference follows it.
  if p_issued_at is not null and not public.doc_day_ok(p_issued_at) then return jsonb_build_object('error', 'bad-date'); end if;
  if t.id is null then return jsonb_build_object('error', 'no-type'); end if;
  -- A Quotation Cover opens every quotation's PDF; it is never issued on
  -- its own (QUOTATION COVER NOT ISSUED ALONE, 2026-11-25).
  if t.family = 'quote_cover' then return jsonb_build_object('error', 'not-issuable'); end if;
  if not public.register_may(t.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;

  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;

  if t.family in ('quote_cover', 'client') then
    if p_client is null then return jsonb_build_object('error', 'no-client'); end if;
    select * into cl from public.clients where id = p_client;
    if cl.id is null then return jsonb_build_object('error', 'no-client'); end if;
  end if;
  if t.family = 'hr' then
    if p_member is null then return jsonb_build_object('error', 'no-member'); end if;
    select * into mb from public.team_members where id = p_member;
    if mb.id is null then return jsonb_build_object('error', 'no-member'); end if;
    if coalesce(btrim(mb.staff_code), '') = '' then return jsonb_build_object('error', 'no-staff-code'); end if;
  end if;
  if t.family = 'supplier' then
    if p_supplier is null then return jsonb_build_object('error', 'no-supplier'); end if;
    select * into sp from public.suppliers where id = p_supplier;
    if sp.id is null then return jsonb_build_object('error', 'no-supplier'); end if;
    /* The agreement carries its schedules (2026-10-18): who the supplier is,
       when it starts, the fee and at least one account. */
    if t.id = 'supplier_sca' and not public.sca_complete(p_body) then
      return jsonb_build_object('error', 'agreement-incomplete');
    end if;
  end if;

  -- Whether the letter leaves space to be signed is the sheet's tick
  -- (2026-10-01), else the type's own setting. A signed letter is signed by
  -- a person, never by a permission; an unsigned one may still name who
  -- issued it, held to the same test.
  v_signed := coalesce(p_signed, t.signed);
  if coalesce(btrim(p_signatory ->> 'name'), '') <> '' and not public.issuer_name_ok(p_signatory ->> 'name') then
    return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
  end if;
  if v_signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;

  v_serial := nullif(btrim(coalesce(p_serial, '')), '');
  if v_serial is null then
    if t.family = 'quote_cover' then return jsonb_build_object('error', 'serial-required'); end if;
    if t.family in ('client', 'supplier') then
      if t.family = 'client' then
        if coalesce(btrim(cl.client_code), '') = '' then return jsonb_build_object('error', 'no-client-code'); end if;
        v_base := 'ACL/' || upper(btrim(cl.client_code));
      elsif t.id = 'supplier_sca' then
        v_base := 'AD/SCA/' || upper(btrim(sp.code));
      else
        v_base := 'ASL/' || upper(btrim(sp.code));
      end if;
      /* A Supplier Service Agreement is numbered by its month
         (AD/SCA/{Supplier ID}/{YYMM}{NN}, 2026-10-18); every other letter by
         its day. */
      v_base := v_base || '/' || to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
                                         case when t.id = 'supplier_sca' then 'YYMM' else 'YYMMDD' end);
      -- Two issuers on one client (or supplier) and day wait for each other
      -- here, so the second never reads the first one's number as free.
      perform pg_advisory_xact_lock(hashtext('acl:' || v_base));
      v_n := 1;
      loop
        v_serial := v_base || case when v_n < 10 then '0' else '' end || v_n;
        exit when not public.serial_taken(v_serial);
        v_n := v_n + 1;
        if v_n > 999 then return jsonb_build_object('error', 'no-serial'); end if;
      end loop;
    else
      v_base := 'ADHR/' || upper(mb.staff_code) || '/' || coalesce(t.code, 'GL') ||
                to_char(coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date), 'YYMM');
      -- Two issues for one colleague, kind and month wait for each other
      -- here, as a letter's do, so the second never takes the first's number
      -- (review 2026-11-24).
      perform pg_advisory_xact_lock(hashtext('adhr:' || v_base));
      v_serial := v_base; v_n := 1;
      while public.serial_taken(v_serial) loop
        v_n := v_n + 1; v_serial := v_base || '-' || v_n;
      end loop;
    end if;
  else
    if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
    if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  end if;

  v_langs := coalesce(p_languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;

  select * into me from public.team_members where auth_user_id = auth.uid() and active limit 1;

  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, supplier_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key)
  values
    (t.id, t.family, t.name, v_serial,
     case when t.family in ('hr', 'supplier') then null else p_client end,
     case when t.family = 'hr' then p_member else null end,
     case when t.family = 'supplier' then p_supplier else null end,
     coalesce(p_issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), t.title),
     coalesce(nullif(btrim(p_salutation), ''), t.salutation), t.closing,
     coalesce(p_recipient, '{}'::jsonb), coalesce(p_body, '{}'::jsonb), v_langs,
     case when coalesce(btrim(p_signatory ->> 'name'), '') <> '' then p_signatory else null end, v_signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''))
  returning id into v_id;

  -- The record is told an HR letter was issued and nothing about whom: the
  -- Activity record is read by more people than HR is.
  if t.family = 'hr' then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', 'HR', t.name);
  else
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'document.issued', case when t.family = 'supplier' then sp.name else cl.name end, v_serial || ' · ' || t.name);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then
    if coalesce(btrim(p_idem), '') <> '' then
      select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
      if v_old.id is not null then
        return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
      end if;
    end if;
    return jsonb_build_object('error', 'serial-taken');
end $$;

create or replace function public.document_reissue(
  p_doc       uuid,
  p_issued_at date,
  p_title     text,
  p_recipient jsonb,
  p_body      jsonb,
  p_signatory jsonb,
  p_languages text[],
  p_salutation text,
  p_idem      text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  d      public.documents%rowtype;
  v_old  public.documents%rowtype;
  me     public.team_members%rowtype;
  cl     public.clients%rowtype;
  v_id   uuid;
  v_langs text[];
begin
  select * into d from public.documents where id = p_doc;
  if p_issued_at is not null and not public.doc_day_ok(p_issued_at) then return jsonb_build_object('error', 'bad-date'); end if;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'portal' then return jsonb_build_object('error', 'not-portal'); end if;
  if d.family = 'quote_cover' then return jsonb_build_object('error', 'not-issuable'); end if;
  if not public.register_may(d.family, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if coalesce(btrim(p_idem), '') <> '' then
    select * into v_old from public.documents where idem_key = btrim(p_idem) limit 1;
    if v_old.id is not null then
      return jsonb_build_object('ok', true, 'repeat', true, 'id', v_old.id, 'serial', v_old.serial);
    end if;
  end if;
  if exists (select 1 from public.documents
              where upper(serial) = upper(d.serial) and voided_at is null and id <> d.id) then
    return jsonb_build_object('error', 'not-current');
  end if;
  if d.signed then
    if coalesce(btrim(p_signatory ->> 'name'), '') = '' then return jsonb_build_object('error', 'no-signatory'); end if;
    if not public.issuer_name_ok(p_signatory ->> 'name') then
      return jsonb_build_object('error', 'issuer-name', 'name', p_signatory ->> 'name');
    end if;
  end if;
  v_langs := coalesce(p_languages, d.languages, '{en}');
  if array_length(v_langs, 1) is null then v_langs := '{en}'; end if;
  select * into me from public.team_members where auth_user_id = auth.uid() and active limit 1;

  if d.voided_at is null then
    update public.documents set voided_at = now(), voided_by = who, void_reason = 'Reissued' where id = d.id;
  end if;
  insert into public.documents
    (type_id, family, kind, serial, client_id, member_id, supplier_id, issued_at, title, salutation, closing,
     recipient, body, languages, signatory, signed, source, issued_by, idem_key, replaces)
  values
    (d.type_id, d.family, d.kind, d.serial, d.client_id, d.member_id, d.supplier_id,
     coalesce(p_issued_at, d.issued_at, (timezone('Asia/Kuala_Lumpur', now()))::date),
     coalesce(nullif(btrim(p_title), ''), d.title),
     coalesce(nullif(btrim(p_salutation), ''), d.salutation), d.closing,
     coalesce(p_recipient, d.recipient), coalesce(p_body, d.body), v_langs,
     case when d.signed then p_signatory else null end, d.signed, 'portal',
     coalesce(me.name, who), nullif(btrim(p_idem), ''), d.id)
  returning id into v_id;

  if d.client_id is not null then select * into cl from public.clients where id = d.client_id; end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'document.reissued',
          case when d.family = 'hr' then 'HR' else coalesce(cl.name, (select s.name from public.suppliers s where s.id = d.supplier_id), d.recipient ->> 'name', '') end,
          case when d.family = 'hr' then d.kind else d.serial || ' · ' || d.kind end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', d.serial);
exception
  when unique_violation then
    return jsonb_build_object('error', 'serial-taken');
end $$;

create or replace function public.team_session_end(p_id uuid, p_session uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  m      public.team_members;
  v_dev  text;
begin
  if me.id is null or not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if coalesce(m.system, false) and m.id <> me.id then return jsonb_build_object('error', 'system-account'); end if;
  -- An admin's devices are an admin's to sign out (MINOR ABUSE PATHS HELD).
  if m.is_admin and not me.is_admin then return jsonb_build_object('error', 'admin-only'); end if;
  if p_session::text = coalesce(auth.jwt() ->> 'session_id', '') then return jsonb_build_object('error', 'own-session'); end if;
  select public.session_device(s.user_agent) into v_dev
    from auth.sessions s
   where s.id = p_session and s.user_id = m.auth_user_id;
  if v_dev is null then return jsonb_build_object('error', 'not-found'); end if;
  delete from auth.sessions s where s.id = p_session;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Signed-in devices',
          m.name || ' was signed out on ' || v_dev || ' (' || left(p_session::text, 6) || ').');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.team_sessions_end_all(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  m    public.team_members;
  v_n  integer := 0;
begin
  if me.id is null or not public.ops_granted('team.sessions', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into m from public.team_members t where t.id = p_id and t.erased_at is null;
  if m.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if m.id = me.id or m.auth_user_id = me.auth_user_id then return jsonb_build_object('error', 'own-account'); end if;
  if coalesce(m.system, false) then return jsonb_build_object('error', 'system-account'); end if;
  if m.is_admin and not me.is_admin then return jsonb_build_object('error', 'admin-only'); end if;
  delete from auth.sessions s
   where s.user_id = m.auth_user_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('error', 'none'); end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Signed-in devices',
          m.name || ' was signed out on ' || v_n || case when v_n = 1 then ' device.' else ' devices.' end);
  return jsonb_build_object('ok', true, 'ended', v_n);
end $$;

create or replace function public.register_add(
  p_serial    text,
  p_family    text,
  p_kind      text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null,
  p_supplier  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  me    public.team_members%rowtype;
  v_serial text := nullif(btrim(coalesce(p_serial, '')), '');
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  v_id  uuid;
  cl    public.clients%rowtype;
  tm    public.team_members%rowtype;
  sp    public.suppliers%rowtype;
begin
  if v_fam not in ('quote_cover', 'client', 'hr', 'other', 'supplier') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(v_fam, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  -- A Quotation Cover is the first page of every quotation, never a
  -- document added on its own (QUOTATION COVER NOT ADDED, 2026-11-26).
  if v_fam = 'quote_cover' then return jsonb_build_object('error', 'not-issuable'); end if;
  if v_serial is null then return jsonb_build_object('error', 'serial-required'); end if;
  if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
  if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif v_fam = 'supplier' then
    if p_supplier is not null then select * into sp from public.suppliers where id = p_supplier; end if;
    if sp.id is null then return jsonb_build_object('error', 'no-supplier'); end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  select * into me from public.team_members where auth_user_id = auth.uid() and active limit 1;

  insert into public.documents
    (family, kind, serial, client_id, member_id, supplier_id, issued_at, recipient, signed, source, file_url, note, issued_by)
  values
    (v_fam, btrim(p_kind), v_serial, cl.id, tm.id, sp.id, coalesce(p_issued_at, (now() at time zone 'Asia/Kuala_Lumpur')::date),
     jsonb_build_object('name', coalesce(btrim(p_recipient), '')), false, 'manual',
     nullif(btrim(p_file_url), ''), nullif(btrim(p_note), ''), coalesce(me.name, who))
  returning id into v_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.added',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, sp.name, sp.code, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else v_serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then return jsonb_build_object('error', 'serial-taken');
end $$;

create or replace function public.portal_request_once(
  p_client uuid, p_kind text, p_service uuid, p_note text, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  me     public.client_contacts%rowtype;
  sv     public.client_services%rowtype;
  rid    uuid;
  v_ref  text;
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  -- The same request again (a reply lost on the way): the one already filed.
  if v_idem is not null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    if rid is not null then return jsonb_build_object('ok', true, 'id', rid, 'again', true); end if;
  end if;
  if p_kind not in ('upgrade', 'downgrade', 'cancel', 'details') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_note, '')) > 2000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into cl from public.clients where id = p_client;
  select * into me from public.client_contacts
    where client_id = p_client and portal_access and archived_at is null and auth_user_id = auth.uid()
    order by is_primary desc limit 1;
  if p_kind <> 'details' then
    select * into sv from public.client_services
      where id = p_service and client_id = p_client and archived_at is null and state = 'confirmed';
    if sv.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if p_kind <> 'cancel' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;
  insert into public.client_requests (client_id, contact_id, contact_name, kind, service_id, service_label, note, idem)
  values (p_client, me.id, me.name, p_kind, sv.id, sv.label, nullif(btrim(p_note), ''), v_idem)
  on conflict (client_id, idem) where idem is not null do nothing
  returning id, request_ref into rid, v_ref;
  if rid is null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    return jsonb_build_object('ok', true, 'id', rid, 'again', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'request.raised', cl.name, p_kind || coalesce(' · ' || sv.label, '') || coalesce(' · ' || v_ref, ''));
  return jsonb_build_object('ok', true, 'id', rid, 'request_ref', v_ref);
end $$;

create or replace function public.get_portal(p_client uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who text := lower(auth.jwt() ->> 'email');
  cid uuid;
  cl  public.clients%rowtype;
  me  public.client_contacts%rowtype;
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  select p into cid from public.portal_clients() p
    order by (p = p_client) desc nulls last limit 1;
  if cid is null then return jsonb_build_object('error', 'no-access'); end if;
  select * into cl from public.clients where id = cid;
  select * into me from public.client_contacts
    where client_id = cid and portal_access and archived_at is null and auth_user_id = auth.uid()
    order by is_primary desc limit 1;

  return jsonb_build_object(
    'clients', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
      from public.clients c where c.id in (select public.portal_clients())), '[]'::jsonb),
    'client', jsonb_build_object(
      'id', cl.id, 'name', cl.name, 'legal_name', cl.legal_name, 'company_no', cl.company_no,
      'billing_address', cl.billing_address, 'market', coalesce(cl.market, 'MY'),
      'bill_market', public.client_bill_market(cl.market, cl.bill_sgd),
      'sst_applies', coalesce(cl.sst_applies, true), 'stage', cl.stage, 'owner', (select x.name from public.team_members x where x.id = public.client_rep(cl.id, 'service')),
      'industry', cl.industry, 'website', cl.website, 'logo_url', cl.logo_url),
    'me', jsonb_build_object('id', me.id, 'name', me.name, 'email', me.email,
      'lang', case when me.lang = 'zh' then 'zh' else 'en' end),
    'contacts', coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'role', k.role, 'phone', k.phone,
        'email', k.email, 'is_primary', k.is_primary, 'portal_access', k.portal_access)
        order by k.is_primary desc, k.name)
      from public.client_contacts k where k.client_id = cid and k.archived_at is null), '[]'::jsonb),
    'services', coalesce((
      -- `term_adjust` travels with the line, because the client's page works
      -- the figure out the same way the console and the letter do and must
      -- never print a different one.
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', s.label, 'unit', s.unit, 'qty', s.qty,
        'rate', s.rate, 'tenure', s.tenure, 'start_on', s.start_on, 'state', s.state, 'note', s.note,
        'term_adjust', coalesce(s.term_adjust, false), 'term_pct', s.term_pct)
        order by s.created_at)
      from public.client_services s
      where s.client_id = cid and s.archived_at is null and s.state in ('quoted', 'confirmed')), '[]'::jsonb),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'number', d.number,
        'issued_at', d.issued_at, 'market', d.market, 'subtotal', d.subtotal, 'tax', d.tax,
        'total', d.total, 'bill_to', d.bill_to, 'lines', d.lines, 'issued_by', d.issued_by)
        order by d.created_at desc)
      from public.client_documents d where d.client_id = cid and d.voided_at is null), '[]'::jsonb),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'service_label', r.service_label,
        'note', r.note, 'state', r.state, 'fee', r.fee, 'reply', r.reply,
        'created_at', r.created_at, 'withdrawn_at', r.withdrawn_at, 'request_ref', r.request_ref)
        order by r.created_at desc)
      from public.client_requests r where r.client_id = cid), '[]'::jsonb),
    'review', case
      when cl.review_hidden is not true
       and exists (select 1 from public.batches b where b.client_id = cid and b.published)
      then jsonb_build_object('token', cl.access_token) end,
    'campaigns', coalesce((
      -- Where each campaign stands (2026-11-25): its booked creators'
      -- steps, never who they are, and the next shoot ahead.
      select jsonb_agg(jsonb_build_object('id', m.id, 'title', m.title, 'title_zh', m.title_zh,
        'state', m.state, 'deadline', m.deadline, 'token', m.access_token,
        'push_format', m.push_format,
        'booked', coalesce((select jsonb_agg(o.state order by o.position, o.added_at)
          from public.campaign_options o where o.campaign_id = m.id
           and o.state in ('confirmed', 'pending_visit', 'pending_draft', 'reviewing',
                           'changes', 'scheduled', 'posted', 'completed')), '[]'::jsonb),
        'next_shoot', (select min(o.visit_date) from public.campaign_options o
          where o.campaign_id = m.id and o.state in ('confirmed', 'pending_visit')
            and o.visit_date >= (now() at time zone 'Asia/Kuala_Lumpur')::date))
        order by m.created_at desc)
      from public.campaigns m where m.client_id = cid and m.state <> 'draft'), '[]'::jsonb),
    'access', coalesce((
      select jsonb_agg(jsonb_build_object('name', k.name, 'email', k.email) order by k.is_primary desc, k.name)
      from public.client_contacts k
      where k.client_id = cid and k.archived_at is null and k.portal_access), '[]'::jsonb)
  );
end $$;

create or replace function public.feedback_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_req   public.feedback_requests;
  v_cl    public.clients;
  a       jsonb := coalesce(p_answers, '{}'::jsonb);
  q       record;
  v_out   jsonb := '{}'::jsonb;
  v_val   text;
  v_int   int;
  v_lead  int;
  v_band  text;
  v_mgr   int;
  v_ct    public.client_contacts;
  v_resp  uuid;
  v_kword text;
  v_ref   text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{16}$' then
    perform public.feedback_throttle(true);
    return jsonb_build_object('error', 'not_found');
  end if;
  if jsonb_typeof(a) <> 'object' then return jsonb_build_object('error', 'bad-answers'); end if;
  select * into v_req from public.feedback_requests r where r.access_key = p_key for update;
  if not public.feedback_throttle(v_req.id is null) then return jsonb_build_object('error', 'busy'); end if;
  if v_req.id is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_cl from public.clients c where c.id = v_req.client_id;
  if v_req.closed_reason = 'answered' then
    return jsonb_build_object('error', 'answered', 'answered_at', v_req.answered_at,
      'request_ref', (select s.request_ref from public.feedback_responses s where s.request_id = v_req.id));
  end if;
  if v_req.closed_at is not null then return jsonb_build_object('error', 'closed'); end if;

  -- The lead question first: its band chooses which note is asked.
  for q in select * from public.feedback_questions x
            where x.kind = v_req.kind and x.lead loop
    v_val := a ->> q.key;
    if v_val is null or v_val !~ '^[0-9]{1,2}$' then return jsonb_build_object('error', 'required', 'key', q.key); end if;
    v_lead := v_val::int;
    if v_lead < q.scale_min or v_lead > q.scale_max then return jsonb_build_object('error', 'bad-score', 'key', q.key); end if;
    v_band := case when v_lead <= q.band_low_max then 'low' when v_lead <= q.band_mid_max then 'mid' else 'high' end;
  end loop;
  if v_lead is null then return jsonb_build_object('error', 'bad-kind'); end if;

  for q in select * from public.feedback_questions x
            where x.kind = v_req.kind
              and (not x.about_manager or v_req.manager_name is not null)
              and (x.band is null or x.band = v_band)
            order by x.n loop
    v_val := a ->> q.key;
    if q.type = 'scale' then
      if v_val is null or v_val !~ '^[0-9]{1,2}$' then
        if q.required then return jsonb_build_object('error', 'required', 'key', q.key); end if;
        continue;
      end if;
      v_int := v_val::int;
      if v_int < q.scale_min or v_int > q.scale_max then return jsonb_build_object('error', 'bad-score', 'key', q.key); end if;
      v_out := v_out || jsonb_build_object(q.key, v_int);
      if q.about_manager then v_mgr := v_int; end if;
    else
      v_val := nullif(btrim(coalesce(v_val, '')), '');
      if v_val is null then
        if q.required then return jsonb_build_object('error', 'required', 'key', q.key); end if;
        continue;
      end if;
      if length(v_val) > 2000 then return jsonb_build_object('error', 'too-long', 'key', q.key); end if;
      v_out := v_out || jsonb_build_object(q.key, v_val);
    end if;
  end loop;

  -- A signed-in contact of this client is named; anyone else is the link.
  if public.portal_contact_name(v_req.client_id) is not null then
    select * into v_ct from public.client_contacts k
     where k.client_id = v_req.client_id and k.portal_access and k.archived_at is null
       and k.auth_user_id = auth.uid()
     order by k.is_primary desc limit 1;
  end if;

  insert into public.feedback_responses (request_id, client_id, kind, answers, score, band,
    manager_id, manager_score, contact_id, contact_name)
  values (v_req.id, v_req.client_id, v_req.kind, v_out, v_lead, v_band,
    v_req.manager_id, v_mgr, v_ct.id, v_ct.name)
  returning id, request_ref into v_resp, v_ref;
  update public.feedback_requests r set answered_at = now(), closed_at = now(), closed_reason = 'answered',
         opened_at = coalesce(r.opened_at, now())
   where r.id = v_req.id;

  v_kword := case v_req.kind when 'quick' then 'Service rating' else 'Performance review' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_ct.name, 'Feedback form'), 'client.edited', v_cl.name,
          v_kword || ' answered: ' || v_lead || ' of ' ||
          (select x.scale_max from public.feedback_questions x where x.kind = v_req.kind and x.lead) ||
          coalesce(' · ' || v_ref, ''));
  -- The account manager told, else whoever sent it; a low score says so.
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.feedback',
         case when v_band = 'low' then 'Low score · ' else 'Feedback received · ' end || v_cl.name,
         v_kword || ': ' || v_lead || ' of ' ||
         (select x.scale_max from public.feedback_questions x where x.kind = v_req.kind and x.lead) ||
         case when v_band = 'low' then '. Open the client''s Feedback to follow up.' else '.' end,
         v_cl.id, 'client.feedback:' || v_resp || ':' || m.id
    from public.team_members m
   where m.active and m.id = coalesce(v_req.manager_id, v_req.sent_by)
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true, 'request_ref', v_ref);
end $$;

create or replace function public.delete_client(p_client uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  want text;
  who  text := auth.jwt() ->> 'email';
  cl   public.clients%rowtype;
  me   public.team_members%rowtype;
begin
  if who is null then
    raise exception 'Not signed in';
  end if;
  /* The team's alone, at Clients Full Access: a client's login holds no team
     row, and hiding the menu item is not access control. */
  if not public.is_team() or not public.allowed('clients', 'manage') then
    raise exception 'Not allowed';
  end if;

  select value into want from public.app_secrets where key = 'delete_code';

  -- No code set: the interface asks for the client's name instead, and has
  -- already checked it. Nothing more to enforce here.
  if want is not null and want <> '' then
    if p_code is null or p_code <> want then
      return 'wrong-code';
    end if;
  end if;

  select * into cl from public.clients where id = p_client;
  if cl.id is null then
    return 'not-found';
  end if;
  if exists (select 1 from public.quotations q where q.client_id = p_client and q.signed_at is not null) then
    return 'has-signed';
  end if;
  delete from public.clients where id = p_client;
  if not found then
    return 'not-found';
  end if;
  /* Filed here, in the same transaction, never by the page after the answer
     (audit R1, 2026-10-10): a reply lost on the way left no record. */
  select * into me from public.team_members where auth_user_id = auth.uid() and active limit 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, who), 'client.deleted', cl.name, coalesce(cl.client_code, ''));
  return 'deleted';
end $$;

-- The jobs that act as a colleague carry the colleague's account id. ------

create or replace function public.ops_recurring_daily()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a   record;
  pp  text;
  out jsonb := '[]'::jsonb;
  was text := current_setting('request.jwt.claims', true);
begin
  update public.ops_recurring_rules r
     set last_error = 'No active colleague can make it: whoever set it and the owner of its task have left.',
         last_error_at = now()
   where r.active
     and not exists (
       select 1 from public.team_members tm
        where tm.active and tm.email is not null
          and tm.id in (r.created_by,
                        (select x.team_member_id from public.ops_task_assignees x
                          where x.task_id = r.source_task_id and x.responsibility = 'owner' and x.ended_at is null
                          limit 1)));
  for a in
    select actor.email, actor.auth_user_id, array_agg(r.id order by r.id) as rules
      from public.ops_recurring_rules r
      left join public.ops_tasks s on s.id = r.source_task_id
      cross join lateral (
        select tm.email, tm.auth_user_id from public.team_members tm
         where tm.active and tm.email is not null
           and tm.id in (r.created_by,
                         (select x.team_member_id from public.ops_task_assignees x
                           where x.task_id = s.id and x.responsibility = 'owner' and x.ended_at is null
                           limit 1))
         order by (tm.id = r.created_by) desc nulls last
         limit 1) actor
     where r.active
     group by actor.email, actor.auth_user_id
  loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('email', a.email, 'sub', a.auth_user_id, 'role', 'authenticated')::text, true);
    update public.ops_recurring_rules r
       set last_error = 'Its colleague can no longer see the task it copies.', last_error_at = now()
     where r.id = any (a.rules) and r.source_task_id is not null
       and not public.ops_may_see_task(r.source_task_id);
    foreach pp in array public.ops_recurring_periods() loop
      out := out || jsonb_build_object('period', pp, 'rules', to_jsonb(a.rules),
                                       'result', public.ops_generate_recurring(pp, a.rules));
    end loop;
    update public.ops_recurring_rules r
       set last_error = null, last_error_at = null
     where r.id = any (a.rules) and r.last_error_at < now();
  end loop;
  perform set_config('request.jwt.claims', coalesce(was, ''), true);
  return out;
end $$;
create or replace function public.sm_reports_month_tick()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e   public.ops_engagements;
  was text := current_setting('request.jwt.claims', true);
  v_mgr text;
  v_mgr_id uuid;
  v_done boolean := false;
begin
  if new.brand_id is not null or new.on_request or new.period_start < date '2026-10-01' then return null; end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status not in ('completed', 'cancelled')
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null or new.kind = any (coalesce(e.reports, '{}'::text[])) then return null; end if;
  begin
    update public.ops_engagements
       set reports = array_append(coalesce(reports, '{}'::text[]), new.kind), version = version + 1, updated_at = now()
     where id = e.id;
    perform public.ops_engagement_log(e.id, 'edited', jsonb_build_object(
      'reports', to_jsonb(array_append(coalesce(e.reports, '{}'::text[]), new.kind)),
      'note', case new.kind when 'social' then 'Accounts Report' else 'Advertising Report' end
              || ' added to the month. The report was started in Reports.', 'report_id', new.id));
    perform public.ops_engagement_sync_reports(e.id);
    v_done := true;
  exception when others then
    null;
  end;
  if not v_done then
    select m.email, m.auth_user_id into v_mgr, v_mgr_id from public.team_members m
     where m.id = e.manager_id and m.active and m.email is not null;
    if v_mgr is not null then
      perform set_config('request.jwt.claims', jsonb_build_object('email', v_mgr, 'sub', v_mgr_id, 'role', 'authenticated')::text, true);
      begin
        update public.ops_engagements
           set reports = array_append(coalesce(reports, '{}'::text[]), new.kind), version = version + 1, updated_at = now()
         where id = e.id;
        perform public.ops_engagement_log(e.id, 'edited', jsonb_build_object(
          'reports', to_jsonb(array_append(coalesce(e.reports, '{}'::text[]), new.kind)),
          'note', case new.kind when 'social' then 'Accounts Report' else 'Advertising Report' end
                  || ' added to the month. The report was started in Reports.', 'report_id', new.id));
        perform public.ops_engagement_sync_reports(e.id);
      exception when others then
        null;
      end;
      perform set_config('request.jwt.claims', coalesce(was, ''), true);
    end if;
  end if;
  return null;
exception when others then
  perform set_config('request.jwt.claims', coalesce(was, ''), true);
  return null;
end $$;
create or replace function public.agent_schedules_run()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.agent_schedules;
  m public.team_members;
  v jsonb;
  v_why text;
  v_done integer := 0;
  v_skip integer := 0;
  v_fail integer := 0;
  was text := current_setting('request.jwt.claims', true);
begin
  for s in
    select * from public.agent_schedules x
     where x.state = 'waiting' and x.run_at <= now()
     order by x.run_at
     limit 50
     for update skip locked
  loop
    v_why := null; v := null;
    select * into m from public.team_members t where t.id = s.team_member_id;
    if m.id is null or not m.active or m.removed_at is not null or m.email is null then
      v_why := 'The colleague who scheduled this is no longer active.';
    else
      perform set_config('request.jwt.claims', jsonb_build_object('email', m.email, 'sub', m.auth_user_id, 'role', 'authenticated')::text, true);
      if not public.is_team() then
        v_why := 'You no longer have access to the portal.';
      elsif s.condition is not null and not public.agent_schedule_holds(s.condition, s.condition_ref) then
        update public.agent_schedules x set state = 'skipped', ran_at = now(),
               result = case s.condition when 'set_undecided' then 'Skipped: the client has decided every post.'
                                         when 'report_not_sent' then 'Skipped: the report is already marked as sent.'
                                         else 'Skipped: the task is finished.' end
         where x.id = s.id;
        v_skip := v_skip + 1;
        continue;
      else
        begin
          v := public.agent_schedule_do(s, m);
        exception when others then
          v := jsonb_build_object('error', 'fault');
          raise warning 'agent_schedules_run %: %', s.id, sqlerrm;
        end;
        if v ? 'skip' then
          update public.agent_schedules x set state = 'skipped', ran_at = now(), result = v ->> 'said' where x.id = s.id;
          v_skip := v_skip + 1;
          continue;
        end if;
        if v ? 'error' then v_why := public.agent_schedule_said(v ->> 'error'); end if;
      end if;
    end if;
    if v_why is null then
      update public.agent_schedules x set state = 'done', ran_at = now(), result = coalesce(v ->> 'said', 'Done.') where x.id = s.id;
      v_done := v_done + 1;
    else
      update public.agent_schedules x set state = 'failed', ran_at = now(), result = v_why where x.id = s.id;
      v_fail := v_fail + 1;
      if m.id is not null and m.active then
        insert into public.ops_notifications (team_member_id, kind, title, body, dedupe_key)
        values (m.id, 'assistant.failed', left('Not done: ' || s.title, 200), v_why, 'agent.failed.' || s.id)
        on conflict (dedupe_key) do nothing;
      end if;
    end if;
  end loop;
  perform set_config('request.jwt.claims', coalesce(was, ''), true);
  return jsonb_build_object('done', v_done, 'skipped', v_skip, 'failed', v_fail);
end $$;

-- END OF ACCESS BY ACCOUNT ID -----------------------------------------------

select public.functions_tidy();
