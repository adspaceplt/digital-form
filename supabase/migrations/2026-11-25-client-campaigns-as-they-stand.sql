-- ===========================================================================
-- A CLIENT'S CAMPAIGNS AS THEY STAND (2026-11-25)
-- ===========================================================================
-- WHY: the client portal's approved boards draw each creator campaign as a
-- track of its booked creators (Posted 3, Reviewing 2 …) and its next shoot.
--
-- WHAT IT CHANGES: `get_portal` adds to each campaign `push_format`,
-- `booked` (its booked creators' steps, states alone) and `next_shoot`.
--
-- ORDER: this file, then the pages (an old page ignores the new keys).
-- Safe to run twice.
-- ROLLBACK: run `get_portal` from PAGES IN THE CLIENT'S LANGUAGE again.
-- ===========================================================================

-- A CLIENT'S CAMPAIGNS AS THEY STAND ---------------------------------------
-- The client portal draws each campaign as a track of its booked creators
-- (2026-11-25): `get_portal` sends each campaign's push format, its booked
-- creators' steps in order (states alone, no creator) and its next shoot.
-- Everything else is as before, every refusal kept.
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
    where client_id = cid and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;

  return jsonb_build_object(
    'clients', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
      from public.clients c where c.id in (select public.portal_clients())), '[]'::jsonb),
    'client', jsonb_build_object(
      'id', cl.id, 'name', cl.name, 'legal_name', cl.legal_name, 'company_no', cl.company_no,
      'billing_address', cl.billing_address, 'market', coalesce(cl.market, 'MY'),
      'bill_market', public.client_bill_market(cl.market, cl.bill_sgd),
      'sst_applies', coalesce(cl.sst_applies, true), 'stage', cl.stage, 'owner', cl.owner,
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
        'created_at', r.created_at, 'withdrawn_at', r.withdrawn_at)
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
revoke all on function public.get_portal(uuid) from public, anon;
grant execute on function public.get_portal(uuid) to authenticated;

-- END OF A CLIENT'S CAMPAIGNS AS THEY STAND ----------------------------------

select public.functions_tidy();
