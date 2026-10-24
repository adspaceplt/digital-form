-- ===========================================================================
-- A COLLEAGUE'S LAST SIGN-IN AND LAST ACTIVE — read on their record's rail
-- at Team Full Access (2026-10-24)
-- ===========================================================================
-- WHY (Team audit TEAM2-9; the user decided the colleague record takes a
-- rail as a client's does, with when they last signed in and were last
-- active)
--   Team showed nothing of whether a colleague uses the console: an invited
--   colleague who never signed in, or one who stopped, read the same as
--   everybody else.
--
-- WHAT CHANGED
--   * `team_members.last_seen_at`: stamped by `page_pulse` for the team
--     audience (the console's minute) at most once every 15 minutes, for the
--     signed-in colleague alone (`ops_me()`); a client page asks for the
--     clients' audience and never stamps. Withheld from the table's column
--     grants (never named in them); `team_rows()` answers it at Team Full
--     Access alone and as null below it.
--   * `team_role_defaults` leaves `updated_at` alone when only
--     `last_seen_at` moved, so the stamp never makes a colleague's record
--     read as changed meanwhile (a save over the row as read).
--   * `page_pulse` is volatile (it writes the stamp); a stamp that fails is
--     swallowed and never fails the minute.
--   * `team_member_seen(p_id)` (Team Full Access, else null): the last
--     sign-in from `auth.users`, the last active, and when an invitation
--     was last sent (`team_invites`), for one colleague not erased.
--   * Trigger `team_members_erased_seen` clears `last_seen_at` the moment a
--     colleague's personal details are erased.
--
-- ORDER
--   This file, then the pages (the rail asks `team_member_seen`). An open
--   page before never asks it; one after this file and before the pages
--   reads nothing new.
--
-- Safe to run twice. Rollback: run THE TEAM LIST HOLDS WHAT EVERY COLLEAGUE
-- NEEDS' team_rows, ONE CHECK A MINUTE's page_pulse and the schema's
-- team_role_defaults again; the column, trigger and function may stay.
-- ===========================================================================

alter table public.team_members add column if not exists last_seen_at timestamptz;

create or replace function public.team_role_defaults()
returns trigger language plpgsql as $$
declare r public.team_roles;
begin
  /* The console's minute stamps when a colleague was last active; that
     alone is no change to their record (A COLLEAGUE'S LAST SIGN-IN). */
  if tg_op = 'UPDATE' and new.last_seen_at is distinct from old.last_seen_at
     and (to_jsonb(new) - 'last_seen_at') = (to_jsonb(old) - 'last_seen_at') then
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
  new.updated_at    := now();
  return new;
end $$;

create or replace function public.team_members_erased_seen()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.erased_at is not null then new.last_seen_at := null; end if;
  return new;
end $$;
revoke all on function public.team_members_erased_seen() from public, anon, authenticated;
create or replace trigger team_members_erased_seen before update of erased_at on public.team_members
  for each row execute function public.team_members_erased_seen();

create or replace function public.page_pulse(p_audience text default null, p_bell boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members;
  v  jsonb := jsonb_build_object('maintenance', public.maintenance_state());
begin
  if p_audience in ('team', 'clients') then
    v := v || jsonb_build_object('announcements', coalesce(public.announcement_now(p_audience), '[]'::jsonb));
  end if;
  /* The console's minute says the colleague is active, at most once every
     15 minutes; a client page asks for the clients and never stamps. */
  if p_audience = 'team' then
    begin
      update public.team_members t set last_seen_at = now()
       where t.id = (public.ops_me()).id
         and (t.last_seen_at is null or t.last_seen_at < now() - interval '15 minutes');
    exception when others then null;
    end;
  end if;
  if coalesce(p_bell, false) then
    me := public.ops_me();
    if me.id is not null then
      v := v || jsonb_build_object('bell', jsonb_build_object(
        'unread', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                              from (select * from public.ops_notifications o
                                     where o.team_member_id = me.id and o.read_at is null and o.hidden_at is null
                                     order by o.created_at desc limit 30) x), '[]'::jsonb),
        'earlier', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                               from (select * from public.ops_notifications o
                                      where o.team_member_id = me.id and o.read_at is not null and o.hidden_at is null
                                        and o.created_at >= now() - interval '7 days'
                                      order by o.created_at desc limit 10) x), '[]'::jsonb)));
    end if;
  end if;
  return v;
end $$;
revoke all on function public.page_pulse(text, boolean) from public;
grant execute on function public.page_pulse(text, boolean) to anon, authenticated;

create or replace function public.team_rows()
returns setof public.team_members
language sql stable security definer set search_path = public as $$
  select (jsonb_populate_record(t, case when public.allowed('team', 'manage') then '{}'::jsonb
                                        else '{"last_seen_at": null}'::jsonb end)).*
    from public.team_members t
   where public.allowed('team', 'view')
   order by t.active desc, t.role, t.name
$$;
revoke all on function public.team_rows() from public, anon, authenticated;
grant execute on function public.team_rows() to authenticated;

create or replace function public.team_member_seen(p_id uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
           'last_sign_in_at', (select u.last_sign_in_at from auth.users u
                                where lower(u.email) = lower(t.email)
                                order by u.last_sign_in_at desc nulls last limit 1),
           'last_seen_at', t.last_seen_at,
           'invited_at', (select max(i.created_at) from public.team_invites i
                           where lower(i.email) = lower(t.email) and i.kind = 'team'))
    from public.team_members t
   where t.id = p_id and t.erased_at is null and public.allowed('team', 'manage')
$$;
revoke all on function public.team_member_seen(uuid) from public, anon, authenticated;
grant execute on function public.team_member_seen(uuid) to authenticated;

-- END OF A COLLEAGUE'S LAST SIGN-IN -------------------------------------------

select public.functions_tidy();
