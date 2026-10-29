-- ===========================================================================
-- BUKKU UNLINK — a record linked to the wrong Bukku contact is let go
-- (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "linking of the client in Bukku is a dead end
-- is it it doesnt allow to unlink"): once linked, Send to Bukku offered the
-- linked contact alone, and nothing took the link away.
--
-- WHAT IT ADDS
--   * `bukku_links_gone`: the links let go, kept for their way back (RLS
--     on, no policy, no grant).
--   * `bukku_unlink(p_kind, p_id)`: Clients: Billing (a client) or Suppliers
--     (a supplier) at Work, as Send to Bukku asks. It lets go of the
--     record's link and, since a supplier that is also a client is one
--     Bukku contact, of its pair's link to the same contact (each pair
--     record at its own Work; `denied` naming none). Nothing is sent to or
--     changed in Bukku. `not-linked` where there is none. Filed
--     `client.edited` / `supplier.edited` Unlinked from Bukku · code.
--     Answers `stamp` for the way back.
--   * `bukku_unlink_undo(p_kind, p_id, p_stamp)`: the same level puts back
--     what that unlink let go, as it stood (Last sent and its changes kept);
--     `moved` where the record has been linked since, `taken` where another
--     record holds that contact now. Filed Linked to Bukku again · code.
--
-- ORDER: this file (SQL Editor: it holds `delete`), then the pages. A page
-- served before draws no Unlink; a page served after on a database without
-- this file says This needs a database update. Safe to run twice.
--
-- ROLLBACK
--   drop function if exists public.bukku_unlink_undo(text, uuid, timestamptz);
--   drop function if exists public.bukku_unlink(text, uuid);
--   drop table if exists public.bukku_links_gone;
-- ===========================================================================

-- BUKKU UNLINK --------------------------------------------------------------

create table if not exists public.bukku_links_gone (
  kind       text not null,
  record_id  uuid not null,
  contact_id bigint not null,
  code       text,
  sent_at    timestamptz,
  sent_by    uuid,
  sent_hash  text,
  gone_at    timestamptz not null default now(),
  gone_by    uuid references public.team_members(id) on delete set null
);
alter table public.bukku_links_gone enable row level security;
revoke all on table public.bukku_links_gone from public, anon, authenticated;
create index if not exists bukku_links_gone_record_idx on public.bukku_links_gone (kind, record_id, gone_at);

/* The links one contact holds for a record and its pair: a client and every
   supplier that is that client, alike. Internal. */
create or replace function public.bukku_pair_links(p_kind text, p_id uuid)
returns setof public.bukku_links
language sql stable security definer set search_path = public as $$
  with me as (
    select case when p_kind = 'client' then p_id
                else (select s.client_id from public.suppliers s where s.id = p_id) end as cid,
           coalesce((select l.contact_id from public.bukku_links l where l.kind = p_kind and l.record_id = p_id),
                    case when p_kind = 'supplier' then
                      (select l.contact_id from public.bukku_links l
                        where l.kind = 'client' and l.record_id = (select s.client_id from public.suppliers s where s.id = p_id)) end) as contact
  )
  select l.* from public.bukku_links l, me
   where me.contact is not null and l.contact_id = me.contact
     and ((l.kind = p_kind and l.record_id = p_id)
       or (me.cid is not null and l.kind = 'client' and l.record_id = me.cid)
       or (me.cid is not null and l.kind = 'supplier'
           and l.record_id in (select s.id from public.suppliers s where s.client_id = me.cid)))
$$;
revoke all on function public.bukku_pair_links(text, uuid) from public, anon, authenticated;

/* A record's name and its ID, as the activity record files it. Internal. */
create or replace function public.bukku_record_name(p_kind text, p_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select case when p_kind = 'client'
              then (select x.name from public.clients x where x.id = p_id)
              else (select coalesce(x.name, x.code) from public.suppliers x where x.id = p_id) end
$$;
revoke all on function public.bukku_record_name(text, uuid) from public, anon, authenticated;

create or replace function public.bukku_unlink(p_kind text, p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.bukku_links;
  v_at timestamptz := clock_timestamp();
  v_n int := 0;
begin
  if p_kind not in ('client', 'supplier') or not public.bukku_may(p_kind, p_id, 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  if public.bukku_record_name(p_kind, p_id) is null then return jsonb_build_object('error', 'not-found'); end if;
  for r in select * from public.bukku_pair_links(p_kind, p_id) loop
    if not public.bukku_may(r.kind, r.record_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
  end loop;
  for r in select * from public.bukku_pair_links(p_kind, p_id) loop
    insert into public.bukku_links_gone (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash, gone_at, gone_by)
    values (r.kind, r.record_id, r.contact_id, r.code, r.sent_at, r.sent_by, r.sent_hash, v_at, me.id);
    delete from public.bukku_links x where x.kind = r.kind and x.record_id = r.record_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case when r.kind = 'client' then 'client.edited' else 'supplier.edited' end,
            public.bukku_record_name(r.kind, r.record_id),
            'Unlinked from Bukku · ' || coalesce(r.code, r.contact_id::text));
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then return jsonb_build_object('error', 'not-linked'); end if;
  return jsonb_build_object('ok', true, 'stamp', v_at, 'records', v_n);
end $$;
revoke all on function public.bukku_unlink(text, uuid) from public, anon;
grant execute on function public.bukku_unlink(text, uuid) to authenticated;

create or replace function public.bukku_unlink_undo(p_kind text, p_id uuid, p_stamp timestamptz)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  g public.bukku_links_gone;
  v_n int := 0;
begin
  if p_kind not in ('client', 'supplier') or not public.bukku_may(p_kind, p_id, 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  if not exists (select 1 from public.bukku_links_gone x
                  where x.gone_at = p_stamp and x.kind = p_kind and x.record_id = p_id) then
    return jsonb_build_object('error', 'not-found');
  end if;
  for g in select * from public.bukku_links_gone x where x.gone_at = p_stamp loop
    if not public.bukku_may(g.kind, g.record_id, 'work') then return jsonb_build_object('error', 'denied'); end if;
    if exists (select 1 from public.bukku_links l where l.kind = g.kind and l.record_id = g.record_id) then
      return jsonb_build_object('error', 'moved');
    end if;
    if public.bukku_contact_taken(g.kind, g.record_id, g.contact_id) then return jsonb_build_object('error', 'taken'); end if;
  end loop;
  for g in select * from public.bukku_links_gone x where x.gone_at = p_stamp loop
    insert into public.bukku_links (kind, record_id, contact_id, code, sent_at, sent_by, sent_hash)
    values (g.kind, g.record_id, g.contact_id, g.code, coalesce(g.sent_at, now()), g.sent_by, g.sent_hash);
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, case when g.kind = 'client' then 'client.edited' else 'supplier.edited' end,
            public.bukku_record_name(g.kind, g.record_id),
            'Linked to Bukku again · ' || coalesce(g.code, g.contact_id::text));
    v_n := v_n + 1;
  end loop;
  delete from public.bukku_links_gone x where x.gone_at = p_stamp;
  return jsonb_build_object('ok', true, 'records', v_n);
end $$;
revoke all on function public.bukku_unlink_undo(text, uuid, timestamptz) from public, anon;
grant execute on function public.bukku_unlink_undo(text, uuid, timestamptz) to authenticated;

-- END OF BUKKU UNLINK -------------------------------------------------------

select public.functions_tidy();
