-- An HR entry names its colleague (2026-09-26).
--
-- A row added by hand in Documents was always addressed to a client, so an
-- HR letter's sheet offered a client select (reported with a screenshot).
-- register_add and register_update take the colleague (p_member): an HR
-- row keeps the team member and no client, every other row keeps its client
-- and no team member. The page shows the one select that fits the kind.
--
-- Safe to run twice. Rollback: re-run the two functions from
-- 2026-09-18-register-edit.sql and drop these nine-argument ones.

drop function if exists public.register_add(text, text, text, date, text, uuid, text, text);
create or replace function public.register_add(
  p_serial    text,
  p_family    text,
  p_kind      text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null
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
begin
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(v_fam, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if v_serial is null then return jsonb_build_object('error', 'serial-required'); end if;
  if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
  if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (family, kind, serial, client_id, member_id, issued_at, recipient, signed, source, file_url, note, issued_by)
  values
    (v_fam, btrim(p_kind), v_serial, cl.id, tm.id, coalesce(p_issued_at, current_date),
     jsonb_build_object('name', coalesce(btrim(p_recipient), '')), false, 'manual',
     nullif(btrim(p_file_url), ''), nullif(btrim(p_note), ''), coalesce(me.name, who))
  returning id into v_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.added',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else v_serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.register_add(text, text, text, date, text, uuid, text, text, uuid) to authenticated;

drop function if exists public.register_update(uuid, text, text, date, text, uuid, text, text);
create or replace function public.register_update(
  p_doc       uuid,
  p_kind      text,
  p_family    text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.documents%rowtype;
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  cl    public.clients%rowtype;
  tm    public.team_members%rowtype;
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'manual' then return jsonb_build_object('error', 'not-manual'); end if;
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(d.family, 'work') or not public.register_may(v_fam, 'work') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  update public.documents set
    kind = btrim(p_kind), family = v_fam, issued_at = p_issued_at,
    recipient = jsonb_build_object('name', coalesce(btrim(p_recipient), '')),
    client_id = cl.id, member_id = tm.id,
    note = nullif(btrim(p_note), ''), file_url = nullif(btrim(p_file_url), '')
  where id = p_doc;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.edited',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else d.serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'serial', d.serial);
end $$;
grant execute on function public.register_update(uuid, text, text, date, text, uuid, text, text, uuid) to authenticated;
