-- ===========================================================================
-- BUKKU SEND CLAIMED (2026-11-24)
-- ===========================================================================
-- WHY: the audit of 2026-11-24 (approved by the user): two presses of Send
-- to Bukku on a record with no contact both made a new Bukku contact, the
-- second filed over the first, which stood in Bukku unlinked.
--
-- WHAT CHANGED
--   * `bukku_send_claims` (kind, record, claimed at, by; RLS on, no policy,
--     no grant).
--   * `bukku_send_claim(p_kind, p_id)` (the record's Work level, as
--     `bukku_linked`; `denied`, `busy`): the record is claimed for two
--     minutes before bukku-sync makes a new contact; a claim still open
--     refuses the second press.
--   * `bukku_send_release(p_kind, p_id)` lets go of the caller's own claim
--     once the send has its answer.
--
-- ORDER: this file (connector), then bukku-sync (until it is deployed
-- nothing asks the claim), then the pages (Bukku says `busy`; an old page
-- reads it as Bukku's refusal). Safe to run twice.
-- ROLLBACK: redeploy the previous bukku-sync; the table and the two
-- functions may stay unused.
-- ===========================================================================

-- BUKKU SEND CLAIMED ---------------------------------------------------------

create table if not exists public.bukku_send_claims (
  kind       text not null,
  record_id  uuid not null,
  claimed_at timestamptz,
  claimed_by uuid,
  primary key (kind, record_id)
);
alter table public.bukku_send_claims enable row level security;
revoke all on table public.bukku_send_claims from public, anon, authenticated;

create or replace function public.bukku_send_claim(p_kind text, p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_got boolean;
begin
  if me.id is null or not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  insert into public.bukku_send_claims as c (kind, record_id, claimed_at, claimed_by)
  values (p_kind, p_id, now(), me.id)
  on conflict (kind, record_id) do update set claimed_at = now(), claimed_by = me.id
   where c.claimed_at is null or c.claimed_at < now() - interval '2 minutes'
  returning true into v_got;
  if v_got is null then return jsonb_build_object('error', 'busy'); end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_send_claim(text, uuid) from public, anon;
grant execute on function public.bukku_send_claim(text, uuid) to authenticated;

create or replace function public.bukku_send_release(p_kind text, p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  update public.bukku_send_claims c set claimed_at = null
   where c.kind = p_kind and c.record_id = p_id and c.claimed_by = me.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_send_release(text, uuid) from public, anon;
grant execute on function public.bukku_send_release(text, uuid) to authenticated;

-- END OF BUKKU SEND CLAIMED --------------------------------------------------

select public.functions_tidy();
