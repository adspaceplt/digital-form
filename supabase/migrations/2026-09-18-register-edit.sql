-- 2026-09-18 · The Register: a hand-added row is edited, and its date may be blank.
--
-- A serial imported from the old list is known before its details are, so
-- `documents.issued_at` becomes optional and `register_update` lets a
-- hand-added row be corrected afterwards. Safe to run twice. Not needed on a
-- database that has run supabase/schema.sql on or after this date.
--
-- Rollback: alter table public.documents alter column issued_at set not null;
--           drop function if exists public.register_update(uuid, text, text, date, text, uuid, text, text);
alter table public.documents alter column issued_at drop not null;

-- 5a. Editing a hand-added row: the kind, the family, the date, the recipient,
--     the client, the note and the file link. The serial never changes; a
--     wrong serial is deleted and added again, so the deletions remember it.
create or replace function public.register_update(
  p_doc       uuid,
  p_kind      text,
  p_family    text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.documents%rowtype;
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  cl    public.clients%rowtype;
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'manual' then return jsonb_build_object('error', 'not-manual'); end if;
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(d.family, 'work') or not public.register_may(v_fam, 'work') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if p_client is not null then select * into cl from public.clients where id = p_client; end if;
  update public.documents set
    kind = btrim(p_kind), family = v_fam, issued_at = p_issued_at,
    recipient = jsonb_build_object('name', coalesce(btrim(p_recipient), '')),
    client_id = cl.id, note = nullif(btrim(p_note), ''), file_url = nullif(btrim(p_file_url), '')
  where id = p_doc;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.edited',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else d.serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'serial', d.serial);
end $$;
grant execute on function public.register_update(uuid, text, text, date, text, uuid, text, text) to authenticated;
