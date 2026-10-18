-- ===========================================================================
-- AN INVITATION GOES TO A COLLEAGUE — a team login is made only for an
-- active colleague's address, twenty invitations a day each (2026-10-18)
-- ===========================================================================
-- WHY (Team audit, item 8): `invite-member` made a login for any address
-- with only Team: Send invitation, and no limit, so a login could be made
-- for an address that is nobody on the team, as often as asked.
--
-- WHAT IT CHANGES
--   * `team_invites` (caller, address, kind, when; RLS on, no policy, no
--     grant): every invitation the function makes.
--   * `team_invite_claim(p_caller, p_email, p_kind)`: the service role's
--     alone; refuses `too-many` once the caller has made 20 in the last 24
--     hours, else files the invitation. `invite-member` asks it before it
--     makes a login, and makes a team login only for an address an active
--     colleague holds (`not_team_member`).
--
-- ORDER: this file, then `invite-member` (deployed and read back). Safe to
-- run twice.
-- Rollback: deploy the earlier `invite-member`; the table and function may
-- stay.
-- ===========================================================================

create table if not exists public.team_invites (
  id         uuid primary key default gen_random_uuid(),
  caller_id  uuid not null,
  email      text not null,
  kind       text not null check (kind in ('team', 'client')),
  created_at timestamptz not null default now()
);
create index if not exists team_invites_caller_idx on public.team_invites (caller_id, created_at);
alter table public.team_invites enable row level security;
revoke all on table public.team_invites from public, anon, authenticated;

create or replace function public.team_invite_claim(p_caller uuid, p_email text, p_kind text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if p_caller is null or coalesce(btrim(p_email), '') = '' or p_kind not in ('team', 'client') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  perform pg_advisory_xact_lock(hashtext('team_invite_claim:' || p_caller::text));
  select count(*) into n from public.team_invites i
   where i.caller_id = p_caller and i.created_at > now() - interval '24 hours';
  if n >= 20 then return jsonb_build_object('error', 'too-many', 'limit', 20); end if;
  insert into public.team_invites (caller_id, email, kind) values (p_caller, lower(btrim(p_email)), p_kind);
  return null;
end $$;
revoke all on function public.team_invite_claim(uuid, text, text) from public, anon, authenticated;
grant execute on function public.team_invite_claim(uuid, text, text) to service_role;

-- END OF AN INVITATION GOES TO A COLLEAGUE ----------------------------------

select public.functions_tidy();
