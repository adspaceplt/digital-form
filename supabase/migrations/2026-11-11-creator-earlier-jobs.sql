-- ===========================================================================
-- CREATOR EARLIER JOBS — a creator's past job IDs from the AP01 form, kept
-- on their Payment tab with the Bukku bill each one was paid by (2026-11-11)
-- ===========================================================================
-- WHY (the user, 2026-11-11: "i can add the KJxxxx … as some have past
-- payments … however now i couldnt add anything it shows nothing"): an
-- earlier job ID could be held only on a booking (`campaign_options.
-- earlier_job`), and a job from before the portal has no booking.
--
-- WHAT CHANGED
--   * `creator_earlier_jobs` (creator, ref, added and removed by whom and
--     when; RLS on, no policy, no grant): one live row a job ID across every
--     creator, the job ID shaped as a booking's earlier job is.
--   * `creator_earlier_job_add(p_creator, p_ref)` and
--     `creator_earlier_job_remove(p_id, p_restore)` (`campaigns.pay` at
--     Work; `denied`, `not-found`, `bad-ref`, `taken`): Remove keeps the row
--     (`removed_at`), Undo and adding the same ID again bring it back. Each
--     filed `creator.updated` under the creator.
--   * `creator_earlier_job_set` (a booking's) refuses an ID a creator's
--     earlier jobs hold (`taken`).
--   * `creator_bills_list` answers `past`: each live earlier job with the
--     bill whose reference or number holds it (`creator_ref_key`, as a
--     booking's bill is found), Earlier payments keeping the bills neither a
--     booking nor an earlier job holds.
--
-- ORDER: this file (connector), then the pages. A page served before reads
-- the list without `past`. Safe to run twice.
--
-- ROLLBACK: restate creator_bills_list and creator_earlier_job_set from
-- CREATOR PAYMENTS in schema.sql; the two functions and the table are left
-- unused.
-- ===========================================================================

-- CREATOR EARLIER JOBS -------------------------------------------------------

create table if not exists public.creator_earlier_jobs (
  id         uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.creators(id) on delete cascade,
  ref        text not null check (ref ~ '^[A-Z0-9][A-Z0-9/._-]{1,39}$'),
  added_at   timestamptz not null default now(),
  added_by   text,
  removed_at timestamptz,
  removed_by text
);
alter table public.creator_earlier_jobs enable row level security;
revoke all on public.creator_earlier_jobs from public, anon, authenticated;
create unique index if not exists creator_earlier_jobs_ref_idx on public.creator_earlier_jobs (ref) where removed_at is null;
create index if not exists creator_earlier_jobs_creator_idx on public.creator_earlier_jobs (creator_id);

create or replace function public.creator_earlier_job_add(p_creator uuid, p_ref text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c  public.creators;
  j  public.creator_earlier_jobs;
  v  text := nullif(upper(regexp_replace(btrim(coalesce(p_ref, '')), '\s+', '', 'g')), '');
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.creators x where x.id = p_creator;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v is null or v !~ '^[A-Z0-9][A-Z0-9/._-]{1,39}$' then return jsonb_build_object('error', 'bad-ref'); end if;
  perform pg_advisory_xact_lock(hashtextextended('creator_earlier_job:' || v, 0));
  if exists (select 1 from public.campaign_options x where x.earlier_job = v)
     or exists (select 1 from public.creator_earlier_jobs x where x.ref = v and x.removed_at is null) then
    return jsonb_build_object('error', 'taken');
  end if;
  -- the same ID removed from this creator before comes back as it was
  select * into j from public.creator_earlier_jobs x
   where x.creator_id = c.id and x.ref = v order by x.added_at desc limit 1;
  if j.id is not null then
    update public.creator_earlier_jobs x set removed_at = null, removed_by = null where x.id = j.id;
  else
    insert into public.creator_earlier_jobs (creator_id, ref, added_by) values (c.id, v, me.name) returning * into j;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name, coalesce(c.creator_code || ' · ', '') || 'Earlier job added: ' || v);
  return jsonb_build_object('ok', true, 'id', j.id, 'ref', v);
end $$;
revoke all on function public.creator_earlier_job_add(uuid, text) from public, anon;
grant execute on function public.creator_earlier_job_add(uuid, text) to authenticated;

create or replace function public.creator_earlier_job_remove(p_id uuid, p_restore boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  j  public.creator_earlier_jobs;
  c  public.creators;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into j from public.creator_earlier_jobs x where x.id = p_id for update;
  if j.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.creators x where x.id = j.creator_id;
  if coalesce(p_restore, false) then
    if j.removed_at is null then return jsonb_build_object('ok', true); end if;
    if exists (select 1 from public.campaign_options x where x.earlier_job = j.ref)
       or exists (select 1 from public.creator_earlier_jobs x where x.ref = j.ref and x.removed_at is null) then
      return jsonb_build_object('error', 'taken');
    end if;
    update public.creator_earlier_jobs x set removed_at = null, removed_by = null where x.id = j.id;
  else
    if j.removed_at is not null then return jsonb_build_object('ok', true); end if;
    update public.creator_earlier_jobs x set removed_at = now(), removed_by = me.name where x.id = j.id;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name, coalesce(c.creator_code || ' · ', '') ||
          case when coalesce(p_restore, false) then 'Earlier job restored: ' else 'Earlier job removed: ' end || j.ref);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_earlier_job_remove(uuid, boolean) from public, anon;
grant execute on function public.creator_earlier_job_remove(uuid, boolean) to authenticated;

create or replace function public.creator_earlier_job_set(p_option uuid, p_ref text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  c  public.creators;
  v  text := nullif(upper(regexp_replace(btrim(coalesce(p_ref, '')), '\s+', '', 'g')), '');
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v is not null and v !~ '^[A-Z0-9][A-Z0-9/._-]{1,39}$' then return jsonb_build_object('error', 'bad-ref'); end if;
  if v is not null and (exists (select 1 from public.campaign_options x where x.earlier_job = v and x.id <> o.id)
                        or exists (select 1 from public.creator_earlier_jobs x where x.ref = v and x.removed_at is null)) then
    return jsonb_build_object('error', 'taken');
  end if;
  if v is not distinct from o.earlier_job then return jsonb_build_object('ok', true); end if;
  update public.campaign_options x set earlier_job = v where x.id = o.id;
  select * into c from public.creators x where x.id = o.creator_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'creator.updated', c.name,
          coalesce(public.creator_job_ref(o.id) || ' · ', '') || 'Earlier job ID: ' || coalesce(o.earlier_job, 'not set') || ' → ' || coalesce(v, 'not set'));
  update public.creator_bills b set option_id = public.creator_bill_option(b.creator_id, b.ref, b.number)
   where b.creator_id = o.creator_id;
  return jsonb_build_object('ok', true, 'earlier_job', v);
end $$;
revoke all on function public.creator_earlier_job_set(uuid, text) from public, anon;
grant execute on function public.creator_earlier_job_set(uuid, text) to authenticated;

create or replace function public.creator_bills_list(p_creator uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pay boolean := public.ops_granted('campaigns.pay', 'view'); l public.bukku_links;
begin
  if (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.creators c where c.id = p_creator) then return jsonb_build_object('error', 'not-found'); end if;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = p_creator;
  return jsonb_build_object('ok', true, 'pay', v_pay, 'linked', l.contact_id is not null,
    'read_at', (select max(b.read_at) from public.creator_bills b where b.creator_id = p_creator),
    'jobs', coalesce((select jsonb_agg(jsonb_build_object(
        'option', o.id, 'job', public.creator_job_ref(o.id), 'earlier_job', o.earlier_job, 'state', o.state,
        'campaign', m.title, 'campaign_id', m.id, 'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = p_creator and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb),
    -- a creator's past job IDs from before the portal, each with the bill
    -- whose reference or number holds it
    'past', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'ref', e.ref,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'amount', case when v_pay then b.amount end, 'currency', b.currency)
                   from public.creator_bills b
                  where b.creator_id = p_creator and b.option_id is null and not b.gone
                    and length(public.creator_ref_key(e.ref)) >= 4
                    and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                      or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0)
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by e.ref desc)
        from public.creator_earlier_jobs e where e.creator_id = p_creator and e.removed_at is null), '[]'::jsonb),
    'earlier', coalesce((select jsonb_agg(jsonb_build_object('number', b.number, 'ref', b.ref, 'status', b.status, 'date', b.bill_date,
        'amount', case when v_pay then b.amount end, 'currency', b.currency) order by b.bill_date desc nulls last)
        from public.creator_bills b where b.creator_id = p_creator and b.option_id is null and not b.gone
         and not exists (select 1 from public.creator_earlier_jobs e
                          where e.creator_id = p_creator and e.removed_at is null and length(public.creator_ref_key(e.ref)) >= 4
                            and (position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.ref)) > 0
                              or position(public.creator_ref_key(e.ref) in public.creator_ref_key(b.number)) > 0))), '[]'::jsonb));
end $$;
revoke all on function public.creator_bills_list(uuid) from public, anon;
grant execute on function public.creator_bills_list(uuid) to authenticated;

-- END OF CREATOR EARLIER JOBS ------------------------------------------------

select public.functions_tidy();
