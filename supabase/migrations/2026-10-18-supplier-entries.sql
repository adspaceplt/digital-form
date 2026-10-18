-- ===========================================================================
-- SUPPLIER ENTRIES — a supplier's document added by hand is filed under the
-- supplier (2026-10-18)
-- ===========================================================================
-- WHY (the user, 2026-10-18: "AS125 supplier documents not linked"): Add
-- entry offered no Supplier Letter, so a supplier's agreement, NDA or
-- incident report kept outside the portal was filed as Other (or under a
-- client made to hold it) and never reached the supplier's record.
--
-- WHAT IT CHANGES
--   * `register_add` and `register_update` take `p_supplier` and the family
--     `supplier` (Suppliers at Work, as `register_may` answers): a supplier
--     entry names its supplier (`no-supplier`) and no client or colleague;
--     an edit files the supplier from and to.
--   * Entries added by hand before, whose reference names a supplier's ID
--     (`…/AS125/…`), are filed under that supplier once: family `supplier`,
--     `supplier_id` set, the client they hung from let go.
--
-- ORDER: this file, then the pages. A page served before calls the eight or
-- nine argument form, which this replaces: it reloads (the functions are
-- dropped and made again with one more argument, defaulted).
-- Safe to run twice. Rollback: the two functions from DOCUMENT EDITS NAME
-- THEIR CHANGES and its add; the moved rows keep their supplier.
-- ===========================================================================

drop function if exists public.register_add(text, text, text, date, text, uuid, text, text, uuid);
create or replace function public.register_add(
  p_serial    text,
  p_family    text,
  p_kind      text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null,
  p_supplier  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  me    public.team_members%rowtype;
  v_serial text := nullif(btrim(coalesce(p_serial, '')), '');
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  v_id  uuid;
  cl    public.clients%rowtype;
  tm    public.team_members%rowtype;
  sp    public.suppliers%rowtype;
begin
  if v_fam not in ('quote_cover', 'client', 'hr', 'other', 'supplier') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(v_fam, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if v_serial is null then return jsonb_build_object('error', 'serial-required'); end if;
  if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
  if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif v_fam = 'supplier' then
    if p_supplier is not null then select * into sp from public.suppliers where id = p_supplier; end if;
    if sp.id is null then return jsonb_build_object('error', 'no-supplier'); end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (family, kind, serial, client_id, member_id, supplier_id, issued_at, recipient, signed, source, file_url, note, issued_by)
  values
    (v_fam, btrim(p_kind), v_serial, cl.id, tm.id, sp.id, coalesce(p_issued_at, (now() at time zone 'Asia/Kuala_Lumpur')::date),
     jsonb_build_object('name', coalesce(btrim(p_recipient), '')), false, 'manual',
     nullif(btrim(p_file_url), ''), nullif(btrim(p_note), ''), coalesce(me.name, who))
  returning id into v_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.added',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, sp.name, sp.code, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else v_serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.register_add(text, text, text, date, text, uuid, text, text, uuid, uuid) to authenticated;

drop function if exists public.register_update(uuid, text, text, date, text, uuid, text, text, uuid);
create or replace function public.register_update(
  p_doc       uuid,
  p_kind      text,
  p_family    text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null,
  p_supplier  uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.documents%rowtype;
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  cl    public.clients%rowtype;
  was_cl public.clients%rowtype;
  tm    public.team_members%rowtype;
  sp    public.suppliers%rowtype;
  was_sp public.suppliers%rowtype;
  moves text[] := array[]::text[];
  fam_word jsonb := '{"quote_cover":"Quotation Covers","client":"Client Letters","hr":"HR Letters","supplier":"Supplier Letters","other":"Other"}'::jsonb;
  v_rec text := coalesce(btrim(p_recipient), '');
  v_note text := nullif(btrim(p_note), '');
  v_file text := nullif(btrim(p_file_url), '');
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'manual' then return jsonb_build_object('error', 'not-manual'); end if;
  if v_fam not in ('quote_cover', 'client', 'hr', 'other', 'supplier') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(d.family, 'work') or not public.register_may(v_fam, 'work') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif v_fam = 'supplier' then
    if p_supplier is not null then select * into sp from public.suppliers where id = p_supplier; end if;
    if sp.id is null then return jsonb_build_object('error', 'no-supplier'); end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  if d.client_id is not null then select * into was_cl from public.clients where id = d.client_id; end if;
  if d.supplier_id is not null then select * into was_sp from public.suppliers where id = d.supplier_id; end if;

  /* What moved, in the order a reader looks: the type, the date, where it is
     filed, who it went to, then whether the note or the file changed. An HR
     row names only its type, date, note and file. */
  if d.kind is distinct from btrim(p_kind) then
    moves := moves || ('type ' || coalesce(d.kind, 'not set') || ' → ' || btrim(p_kind));
  end if;
  if d.issued_at is distinct from p_issued_at then
    moves := moves || ('date ' || public.register_day(d.issued_at) || ' → ' || public.register_day(p_issued_at));
  end if;
  if v_fam <> 'hr' and d.family <> 'hr' then
    if d.family is distinct from v_fam then
      moves := moves || ('filed ' || coalesce(fam_word ->> d.family, d.family) || ' → ' || coalesce(fam_word ->> v_fam, v_fam));
    end if;
    if coalesce(d.recipient ->> 'name', '') is distinct from v_rec then
      moves := moves || ('recipient ' || coalesce(nullif(d.recipient ->> 'name', ''), 'not set') || ' → ' || coalesce(nullif(v_rec, ''), 'not set'));
    end if;
    if d.client_id is distinct from cl.id then
      moves := moves || ('client ' || coalesce(was_cl.name, 'not set') || ' → ' || coalesce(cl.name, 'not set'));
    end if;
    if d.supplier_id is distinct from sp.id then
      moves := moves || ('supplier ' || coalesce(was_sp.code, 'not set') || ' → ' || coalesce(sp.code, 'not set'));
    end if;
  end if;
  if d.note is distinct from v_note then moves := moves || 'note changed'::text; end if;
  if d.file_url is distinct from v_file then moves := moves || 'file link changed'::text; end if;

  update public.documents set
    kind = btrim(p_kind), family = v_fam, issued_at = p_issued_at,
    recipient = jsonb_build_object('name', v_rec),
    client_id = cl.id, member_id = tm.id, supplier_id = sp.id,
    note = v_note, file_url = v_file
  where id = p_doc;
  if array_length(moves, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'register.edited',
            case when v_fam = 'hr' or d.family = 'hr' then 'HR' else coalesce(cl.name, sp.name, sp.code, nullif(v_rec, ''), d.serial) end,
            case when v_fam = 'hr' or d.family = 'hr' then array_to_string(moves, '; ')
                 else d.serial || ': ' || array_to_string(moves, '; ') end);
  end if;
  return jsonb_build_object('ok', true, 'serial', d.serial);
end $$;
grant execute on function public.register_update(uuid, text, text, date, text, uuid, text, text, uuid, uuid) to authenticated;

/* Entries added by hand whose reference names a supplier's ID, filed under
   that supplier once. */
update public.documents d
   set family = 'supplier', supplier_id = s.id, client_id = null
  from public.suppliers s
 where d.supplier_id is null and d.source = 'manual' and d.family in ('other', 'client')
   and d.serial ~ ('/' || s.code || '/');

-- END OF SUPPLIER ENTRIES ----------------------------------------------------
select public.functions_tidy();
