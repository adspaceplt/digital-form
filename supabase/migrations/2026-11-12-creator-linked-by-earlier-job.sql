-- ===========================================================================
-- CREATOR LINKED BY EARLIER JOB — a creator with no approved payment details
-- is linked to the Bukku contact whose bill holds their earlier job ID
-- (2026-11-12)
-- ===========================================================================
-- WHY (the user, 2026-11-12: KJ3105 added to Gaby Low read Not billed; her
-- Bukku contact is Low Chee Guan, bill AB2608035): bills are read only for
-- a creator linked to Bukku, and the link asked for approved payment
-- details and matched by name, so a creator known by another name, with no
-- details in the portal yet, could not be linked.
--
-- WHAT CHANGED
--   * `bukku_creator_link_prep(p_id)` (Creators List View and Creator
--     payment details at Work, as `bukku_may` asks): what Link to Bukku
--     needs of a creator whatever their details: the name it matches (the
--     approved legal name, else the creator's), the Creator ID, the link
--     and every live earlier job ID (a booking's and the Payment tab's).
--     `bukku-sync` uses it for a creator's find and link alone; Send still
--     needs approved details (`bukku_prepare`, `no-details`).
--   * `creator_bills_due` also reads a linked creator holding an earlier
--     job ID that no paid bill holds yet, so the night reads their bills.
--
-- ORDER: this file (connector), then `bukku-sync`, then the pages. A page
-- served before still says Approve the creator's payment details. Safe to
-- run twice.
--
-- ROLLBACK: restate creator_bills_due from CREATOR PAYMENTS in schema.sql;
-- bukku_creator_link_prep is left unused.
-- ===========================================================================

-- CREATOR LINKED BY EARLIER JOB ---------------------------------------------

create or replace function public.bukku_creator_link_prep(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cr public.creators; rq public.creator_pay_requests; l public.bukku_links; b public.bukku_settings;
begin
  if not public.bukku_may('creator', p_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into cr from public.creators x where x.id = p_id;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into rq from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = cr.id;
  select * into b from public.bukku_settings x where x.id = 1;
  return jsonb_build_object('ok', true, 'kind', 'creator', 'id', cr.id,
    'legal_name', public.bukku_name_case(coalesce(rq.legal_name, cr.name), coalesce(rq.bill_kind = 'brn', false)),
    'other_name', cr.name, 'our_id', cr.creator_code, 'field_id', coalesce(b.field_creator, b.field_supplier),
    'contact_id', l.contact_id, 'details', rq.id is not null,
    'jobs', coalesce((select jsonb_agg(distinct j.ref) from (
        select e.ref from public.creator_earlier_jobs e where e.creator_id = cr.id and e.removed_at is null
        union all
        select o.earlier_job from public.campaign_options o where o.creator_id = cr.id and o.earlier_job is not null) j
       where length(public.creator_ref_key(j.ref)) >= 4), '[]'::jsonb));
end $$;
revoke all on function public.bukku_creator_link_prep(uuid) from public, anon;
grant execute on function public.bukku_creator_link_prep(uuid) to authenticated;

/* The creators the night reads: linked to Bukku, with a booking posted and
   not yet read Paid, or an earlier job ID no paid bill holds yet. The
   service role's alone. */
create or replace function public.creator_bills_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('creator', l.record_id, 'contact', l.contact_id)), '[]'::jsonb)
    from public.bukku_links l
   where l.kind = 'creator'
     and (exists (select 1 from public.campaign_options o
                  where o.creator_id = l.record_id and o.state in ('posted', 'completed')
                    and not exists (select 1 from public.creator_bills b where b.option_id = o.id and b.status = 'paid' and not b.gone))
       or exists (select 1 from public.creator_earlier_jobs e
                  where e.creator_id = l.record_id and e.removed_at is null and length(public.creator_ref_key(e.ref)) >= 4
                    and not exists (select 1 from public.creator_bills b
                                     where b.creator_id = l.record_id and b.status = 'paid' and not b.gone
                                       and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                                         or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0))))
$$;
revoke all on function public.creator_bills_due() from public, anon, authenticated;
grant execute on function public.creator_bills_due() to service_role;

-- END OF CREATOR LINKED BY EARLIER JOB --------------------------------------

select public.functions_tidy();
