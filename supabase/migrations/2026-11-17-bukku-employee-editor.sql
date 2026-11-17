-- ===========================================================================
-- A COLLEAGUE IN BUKKU, THE SQL EDITOR PART (2026-11-17) — run in the SQL
-- Editor after A COLLEAGUE IN BUKKU: it widens `bukku_links.kind` to take
-- `member` (a constraint is replaced by dropping it) and restates
-- `bukku_unlink` / `_undo`, whose bodies remove a link, which the connector
-- holds. Running it turns the Bukku band on a colleague's Onboarding on.
-- Safe to run twice.
-- ROLLBACK: delete the member links, put the check back as CREATOR
-- PAYMENTS, THE SQL EDITOR PART states it, and run its bukku_unlink and
-- bukku_unlink_undo again.
-- ===========================================================================

-- A COLLEAGUE IN BUKKU, THE SQL EDITOR PART -----------------------------------

alter table public.bukku_links drop constraint if exists bukku_links_kind_check;
alter table public.bukku_links add constraint bukku_links_kind_check
  check (kind in ('client', 'supplier', 'entity', 'creator', 'member'));

create or replace function public.bukku_unlink(p_kind text, p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.bukku_links;
  v_at timestamptz := clock_timestamp();
  v_n int := 0;
begin
  if p_kind not in ('client', 'supplier', 'entity', 'creator', 'member') or not public.bukku_may(p_kind, p_id, 'work') then
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
    if r.kind = 'entity' then
      perform public.bukku_file_entity(r.record_id, me.name, 'Unlinked from Bukku · ' || coalesce(r.code, r.contact_id::text));
    else
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, case r.kind when 'client' then 'client.edited' when 'creator' then 'creator.updated' when 'member' then 'team.edited' else 'supplier.edited' end,
              public.bukku_record_name(r.kind, r.record_id),
              'Unlinked from Bukku · ' || coalesce(r.code, r.contact_id::text));
    end if;
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
  if p_kind not in ('client', 'supplier', 'entity', 'creator', 'member') or not public.bukku_may(p_kind, p_id, 'work') then
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
    if g.kind = 'entity' then
      perform public.bukku_file_entity(g.record_id, me.name, 'Linked to Bukku again · ' || coalesce(g.code, g.contact_id::text));
    else
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, case g.kind when 'client' then 'client.edited' when 'creator' then 'creator.updated' when 'member' then 'team.edited' else 'supplier.edited' end,
              public.bukku_record_name(g.kind, g.record_id),
              'Linked to Bukku again · ' || coalesce(g.code, g.contact_id::text));
    end if;
    v_n := v_n + 1;
  end loop;
  delete from public.bukku_links_gone x where x.gone_at = p_stamp;
  return jsonb_build_object('ok', true, 'records', v_n);
end $$;
revoke all on function public.bukku_unlink_undo(text, uuid, timestamptz) from public, anon;
grant execute on function public.bukku_unlink_undo(text, uuid, timestamptz) to authenticated;

-- END OF A COLLEAGUE IN BUKKU, THE SQL EDITOR PART ---------------------------

select public.functions_tidy();
