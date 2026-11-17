-- ============================================================================
-- ACCESS CLEAN-UP (2026-11-17)
-- ============================================================================
-- The access restructure, release 3 (plan version 4, step 6; the user,
-- 2026-11-17: "approved, go ahead and build all steps").
--
--   * The granted parts are read from access_keys (tier granted) by
--     allowed(), never a list typed into it; the page reads one list too.
--   * The stored levels the rule no longer reads are taken off every group
--     and colleague: creator payments and supplier bank details (they follow
--     their section under Sensitive details) and the five WhatsApp parts.
--     Nothing anyone may do changes.
--   * The three Hiring emails ask Send email (send_ok): the interview's
--     (it asked the portal's switch alone), the decision's and the
--     document's.
--
-- ORDER: the pages, then this file (connector). An old page meets nothing
-- new: a Hiring email refused reads its generic line until the page loads.
-- Safe to run twice.
--
-- ROLLBACK: allowed() and hiring_mail_prepare from GROUP SWITCHES,
-- hiring_outcome_mail_prepare from HIRING OUTCOMES, hiring_doc_mail_prepare
-- from HIRING OFFERS AND CONTRACTS. The stored levels taken off were read by
-- nothing; they are not put back.
-- ============================================================================

-- ACCESS CLEAN-UP ------------------------------------------------------------

update public.team_roles
   set access = access - 'campaigns.pay' - 'suppliers.pay' - 'whatsapp.report' - 'whatsapp.feedback'
                - 'whatsapp.booking' - 'whatsapp.approval' - 'whatsapp.documents'
 where access ?| array['campaigns.pay', 'suppliers.pay', 'whatsapp.report', 'whatsapp.feedback',
                       'whatsapp.booking', 'whatsapp.approval', 'whatsapp.documents'];
update public.team_members
   set access = access - 'campaigns.pay' - 'suppliers.pay' - 'whatsapp.report' - 'whatsapp.feedback'
                - 'whatsapp.booking' - 'whatsapp.approval' - 'whatsapp.documents'
 where access ?| array['campaigns.pay', 'suppliers.pay', 'whatsapp.report', 'whatsapp.feedback',
                       'whatsapp.booking', 'whatsapp.approval', 'whatsapp.documents'];

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
    where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active
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
grant execute on function public.allowed(text, text) to authenticated;

create or replace function public.hiring_mail_prepare(p_interview uuid, p_kind text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  i public.hiring_interviews;
  c public.hiring_candidates;
  v_role text;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into i from public.hiring_interviews where id = p_interview;
  if i.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(i.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = i.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_kind = 'invite' and i.state not in ('invited', 'none') then return jsonb_build_object('error', 'not-open'); end if;
  if p_kind = 'confirm' and i.state <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed'); end if;
  if p_kind = 'confirm' and i.mode = 'online' and i.meeting_link is null then return jsonb_build_object('error', 'no-meet'); end if;
  if p_kind not in ('invite', 'confirm') then return jsonb_build_object('error', 'bad-kind'); end if;
  return jsonb_build_object('id', i.id, 'kind', p_kind, 'to', c.email, 'name', c.name, 'position', c.position,
    'key', c.link_key, 'mode', i.mode, 'minutes', i.minutes, 'note', i.note, 'link', i.meeting_link,
    'times', (select jsonb_agg(public.hiring_when(s) order by s) from unnest(i.slots) s),
    'when', case when i.picked is not null then public.hiring_when(i.slots[i.picked]) end,
    'sender', me.name, 'reply_to', me.email);
end $$;

create or replace function public.hiring_outcome_mail_prepare(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.hiring_candidates where id = p_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  if c.outcome not in ('pool', 'not') then return jsonb_build_object('error', 'no-email'); end if;
  return jsonb_build_object('id', c.id, 'kind', c.outcome, 'to', c.email, 'name', c.name, 'position', c.position, 'key', c.link_key,
    'months', coalesce(public.app_setting('hiring_pool_months', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 12),
    'sender', me.name, 'reply_to', me.email);
end $$;
grant execute on function public.hiring_outcome_mail_prepare(uuid) to authenticated;

create or replace function public.hiring_doc_mail_prepare(p_doc uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me public.team_members := public.ops_me(); d public.hiring_docs; c public.hiring_candidates; v_role text;
begin
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  select * into d from public.hiring_docs where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_role := public.hiring_role(d.candidate_id);
  if v_role is null or v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if d.state <> 'sent' then return jsonb_build_object('error', 'not-sent'); end if;
  select * into c from public.hiring_candidates where id = d.candidate_id;
  if c.removed_at is not null or c.link_key is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('id', d.id, 'kind', 'doc', 'doc', d.kind, 'ref', d.serial, 'to', c.email, 'name', c.name,
    'position', d.terms->>'position', 'key', c.link_key, 'reply_by', public.register_day((d.reply_by at time zone 'Asia/Kuala_Lumpur')::date),
    'returned', d.returned_note is not null, 'sent_key', extract(epoch from coalesce(d.returned_at, d.sent_at))::bigint,
    'sender', me.name, 'reply_to', me.email);
end $$;
grant execute on function public.hiring_doc_mail_prepare(uuid) to authenticated;

-- END OF ACCESS CLEAN-UP -----------------------------------------------------

select public.functions_tidy();
