-- ===========================================================================
-- HANDBOOK ACKNOWLEDGED — the files an admin marks required are opened and
-- acknowledged by every colleague before the console opens (2026-11-11)
-- ===========================================================================
-- WHY (the user, 2026-11-11: "everyone who is new … only able to see the
-- handbook and agrees … once agreed, then they would have the next step to
-- enter into those sections"; chose required files alone, acknowledged
-- again on a new version, everyone but admins).
--
-- WHAT CHANGED
--   * `handbook_docs.required`: a file colleagues must read, set by
--     `handbook_required_set(p_id, p_on)` (Team: Handbook files at Work;
--     `denied`, `not-found`; filed `handbook.edited` Required reading: Off
--     → On).
--   * `handbook_reads` (colleague, file, version, opened, acknowledged; RLS
--     on, no policy, no grant): `handbook_opened(p_doc)` keeps the moment a
--     colleague first opened the file's current version (a link file's
--     version is 0); `handbook_ack(p_doc)` keeps its acknowledgement, only
--     once it was opened (`not-opened`).
--   * `handbook_due()`: the caller's required live files whose current
--     version is not acknowledged, none for an admin or the system account;
--     the console holds a colleague on the Handbook while any is due.
--   * `handbook_acks(p_doc)` (Team: Handbook files at Work): every active
--     colleague who is not an admin, with when they opened and acknowledged
--     the file's current version.
--
-- ORDER: this file (connector), then the pages. A page served before reads
-- no gate. Safe to run twice.
--
-- ROLLBACK: the console stops asking when the pages go back; the column,
-- the table and the five functions are left unused.
-- ===========================================================================

-- HANDBOOK ACKNOWLEDGED -----------------------------------------------------

alter table public.handbook_docs add column if not exists required boolean not null default false;

create table if not exists public.handbook_reads (
  member_id  uuid not null references public.team_members(id) on delete cascade,
  doc_id     uuid not null references public.handbook_docs(id) on delete cascade,
  version_no integer not null,
  opened_at  timestamptz,
  acked_at   timestamptz,
  primary key (member_id, doc_id, version_no)
);
alter table public.handbook_reads enable row level security;
revoke all on public.handbook_reads from public, anon, authenticated;

create or replace function public.handbook_required_set(p_id uuid, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d  public.handbook_docs;
begin
  if me.id is null or not public.ops_granted('team.handbook', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.handbook_docs h where h.id = p_id for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.required = coalesce(p_on, false) then return jsonb_build_object('ok', true, 'changed', false); end if;
  update public.handbook_docs h set required = coalesce(p_on, false), updated_at = now() where h.id = d.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'handbook.edited', d.title,
          'Required reading: ' || case when d.required then 'On' else 'Off' end || ' → ' || case when p_on then 'On' else 'Off' end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.handbook_required_set(uuid, boolean) from public, anon;
grant execute on function public.handbook_required_set(uuid, boolean) to authenticated;

create or replace function public.handbook_opened(p_doc uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d  public.handbook_docs;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.handbook_docs h where h.id = p_doc and h.archived_at is null;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.handbook_reads (member_id, doc_id, version_no, opened_at)
  values (me.id, d.id, d.current_version, now())
  on conflict (member_id, doc_id, version_no) do update
    set opened_at = coalesce(public.handbook_reads.opened_at, excluded.opened_at);
  return jsonb_build_object('ok', true, 'version', d.current_version);
end $$;
revoke all on function public.handbook_opened(uuid) from public, anon;
grant execute on function public.handbook_opened(uuid) to authenticated;

create or replace function public.handbook_ack(p_doc uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  d  public.handbook_docs;
  r  public.handbook_reads;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into d from public.handbook_docs h where h.id = p_doc and h.archived_at is null;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.handbook_reads x
   where x.member_id = me.id and x.doc_id = d.id and x.version_no = d.current_version for update;
  if r.opened_at is null then return jsonb_build_object('error', 'not-opened'); end if;
  if r.acked_at is null then
    update public.handbook_reads x set acked_at = now()
     where x.member_id = me.id and x.doc_id = d.id and x.version_no = d.current_version;
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.handbook_ack(uuid) from public, anon;
grant execute on function public.handbook_ack(uuid) to authenticated;

create or replace function public.handbook_due()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if me.is_admin or me.role = 'admin' or coalesce(me.system, false) then
    return jsonb_build_object('ok', true, 'due', '[]'::jsonb);
  end if;
  return jsonb_build_object('ok', true, 'due', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'version', d.current_version,
             'opened', r.opened_at is not null) order by d.title)
      from public.handbook_docs d
      left join public.handbook_reads r
        on r.member_id = me.id and r.doc_id = d.id and r.version_no = d.current_version
     where d.required and d.archived_at is null
       and (d.current_version > 0 or d.link_url is not null)
       and r.acked_at is null), '[]'::jsonb));
end $$;
revoke all on function public.handbook_due() from public, anon;
grant execute on function public.handbook_due() to authenticated;

create or replace function public.handbook_acks(p_doc uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d public.handbook_docs;
begin
  if (public.ops_me()).id is null or not public.ops_granted('team.handbook', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into d from public.handbook_docs h where h.id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true, 'version', d.current_version, 'people', coalesce((
    select jsonb_agg(jsonb_build_object('name', m.name, 'opened_at', r.opened_at, 'acked_at', r.acked_at)
             order by (r.acked_at is null) desc, m.name)
      from public.team_members m
      left join public.handbook_reads r
        on r.member_id = m.id and r.doc_id = d.id and r.version_no = d.current_version
     where m.active and m.removed_at is null and not m.is_admin
       and coalesce(m.role, '') <> 'admin' and not coalesce(m.system, false)), '[]'::jsonb));
end $$;
revoke all on function public.handbook_acks(uuid) from public, anon;
grant execute on function public.handbook_acks(uuid) to authenticated;

-- END OF HANDBOOK ACKNOWLEDGED ----------------------------------------------

select public.functions_tidy();
