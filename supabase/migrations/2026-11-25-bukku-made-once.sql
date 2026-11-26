-- ===========================================================================
-- BUKKU MADE ONCE (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25 (the Bukku review, "approve all the fixes"). A
-- contact Bukku made whose link the portal failed to file, or whose answer
-- timed out, let the claim go, so the next Send made a second contact; a
-- bill made whose list then failed to read let its hold go, so the next
-- press could make a second bill.
--
-- WHAT CHANGES
--   * `bukku_send_claims` keeps `sent_code` (the contact code a new contact
--     was sent under) and `made_contact` (the contact Bukku made).
--   * `bukku_send_claim` answers them when a record is claimed again, so
--     bukku-sync links that contact rather than making another.
--   * `bukku_send_sent(p_kind, p_id, p_code, p_contact)` writes them on the
--     caller's claim before and after the contact is sent.
--   * `bukku_send_release` clears them once the send is settled.
--   * `creator_bill_made(p_option, p_number)` files a bill made in Bukku and
--     keeps the press held ten minutes more, for a bill whose list was not
--     read back.
--
-- ORDER: this file (connector), then bukku-sync. Until bukku-sync is
-- deployed nothing calls the new function, and the claim answers two keys
-- more. Safe to run twice.
-- ROLLBACK: run BUKKU SEND CLAIMED's `bukku_send_claim` and
-- `bukku_send_release` again and redeploy the previous bukku-sync; the two
-- columns and two functions may stay unused.
-- ===========================================================================

-- BUKKU MADE ONCE ------------------------------------------------------------

alter table public.bukku_send_claims add column if not exists sent_code text;
alter table public.bukku_send_claims add column if not exists made_contact bigint;

create or replace function public.bukku_send_claim(p_kind text, p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_got boolean;
  k public.bukku_send_claims;
begin
  if me.id is null or not public.bukku_may(p_kind, p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  insert into public.bukku_send_claims as c (kind, record_id, claimed_at, claimed_by)
  values (p_kind, p_id, now(), me.id)
  on conflict (kind, record_id) do update set claimed_at = now(), claimed_by = me.id
   where c.claimed_at is null or c.claimed_at < now() - interval '2 minutes'
  returning true into v_got;
  if v_got is null then return jsonb_build_object('error', 'busy'); end if;
  -- What an earlier send left unsettled: the code it was sent under, and
  -- the contact Bukku made, so the contact is linked, never made twice.
  select * into k from public.bukku_send_claims x where x.kind = p_kind and x.record_id = p_id;
  return jsonb_build_object('ok', true, 'sent_code', k.sent_code, 'made', k.made_contact);
end $$;
revoke all on function public.bukku_send_claim(text, uuid) from public, anon;
grant execute on function public.bukku_send_claim(text, uuid) to authenticated;

create or replace function public.bukku_send_sent(p_kind text, p_id uuid, p_code text, p_contact bigint)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  update public.bukku_send_claims c
     set sent_code = coalesce(left(nullif(btrim(coalesce(p_code, '')), ''), 40), c.sent_code),
         made_contact = coalesce(p_contact, c.made_contact)
   where c.kind = p_kind and c.record_id = p_id and c.claimed_by = me.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_send_sent(text, uuid, text, bigint) from public, anon;
grant execute on function public.bukku_send_sent(text, uuid, text, bigint) to authenticated;

create or replace function public.bukku_send_release(p_kind text, p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  update public.bukku_send_claims c set claimed_at = null, sent_code = null, made_contact = null
   where c.kind = p_kind and c.record_id = p_id and c.claimed_by = me.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.bukku_send_release(text, uuid) from public, anon;
grant execute on function public.bukku_send_release(text, uuid) to authenticated;

-- A bill made in Bukku whose list was not read back: filed as made, and the
-- press held ten minutes more, so a second press makes no second bill.
create or replace function public.creator_bill_made(p_option uuid, p_number text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  f  public.creator_fees;
  c  public.creators;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  update public.creator_bill_claims k set claimed_at = now() where k.option_id = o.id;
  if nullif(btrim(coalesce(p_number, '')), '') is not null then
    select * into f from public.creator_fees x where x.option_id = o.id;
    select * into c from public.creators x where x.id = o.creator_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'creator.updated', c.name,
            coalesce(public.creator_job_ref(o.id) || ' · ', '') || 'Bill ' || left(btrim(p_number), 60) || ' created in Bukku · '
            || public.creator_fee_word(f.amount, f.currency));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_bill_made(uuid, text) from public, anon;
grant execute on function public.creator_bill_made(uuid, text) to authenticated;

-- END OF BUKKU MADE ONCE -----------------------------------------------------

select public.functions_tidy();
