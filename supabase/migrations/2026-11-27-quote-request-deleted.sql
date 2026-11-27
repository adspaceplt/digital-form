-- ===========================================================================
-- QUOTE REQUEST DELETED (2026-11-27)
-- ===========================================================================
-- WHY: the user, 2026-11-27: a website request's ⋯ is Download PDF, Show
-- quotation link, Ask for details · Edit, Cancel quote · Delete. Delete
-- replaces Remove there, under the delete rule (Full control deletes with
-- the reference typed back; Edit files a request, `rpc:quotation_delete`
-- already on `delete_kinds`).
-- WHAT IT CHANGES: `quotation_delete` takes a website request never
-- released (sent or published) without a Remove first. Every other check
-- stands: Full control, the client in scope, the reference typed back,
-- nothing sent out or signed, no service line, letter or revision naming
-- it; the reference is kept, never issued again.
-- ROLLBACK: re-run `quotation_delete` from 2026-11-26-quotations-issued-when-created.sql.
-- Safe to run twice.

create or replace function public.quotation_delete(p_id uuid, p_ref text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_n int;
  v_doc text;
  v_by text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'manage') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- A website request the team never sent is deleted from its own ⋯
  -- (QUOTE REQUEST DELETED, 2026-11-27); any other is removed first.
  if v_q.removed_at is null and not (v_q.source = 'website' and v_q.released_at is null) then
    return jsonb_build_object('error', 'not-removed');
  end if;
  if btrim(coalesce(p_ref, '')) <> v_q.ref then return jsonb_build_object('error', 'bad-ref'); end if;
  -- One that reached the client (its link opened, or sent) or was signed
  -- is kept, Void on the Register and /verify/, never deleted
  -- (QUOTATIONS ISSUED WHEN CREATED, 2026-11-26).
  if v_q.sent_out_at is not null or v_q.signed_at is not null then return jsonb_build_object('error', 'sent'); end if;
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select x.ref into v_by from public.quotations x where x.replaces = v_q.id order by x.issued_at limit 1;
  if v_by is not null then return jsonb_build_object('error', 'revised', 'ref', v_by); end if;
  insert into public.quotation_refs_kept (ref, deleted_by) values (v_q.ref, me.name)
  on conflict (ref) do nothing;
  delete from public.quotations where id = v_q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' deleted');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_delete(uuid, text) from public, anon;
grant execute on function public.quotation_delete(uuid, text) to authenticated;

-- END OF QUOTE REQUEST DELETED ----------------------------------------------
