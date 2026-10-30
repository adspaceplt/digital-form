-- BUKKU PERSON BY ITS WORDS — Bukku's billing person is the contact whose
-- every word Bukku's name holds, where it is the only one (2026-10-30; the
-- user: "my contact added as Ms Angel, but the Bukku record is Ms Angel
-- Lim. it says not same person"). The same words still come first; two
-- contacts each inside Bukku's name are nobody. Send to Bukku already kept
-- a name Bukku holds in full; the read now agrees with it. Safe to run
-- twice; its rollback is the definition in 2026-10-30-billing-from-bukku.sql.

create or replace function public.bukku_person_contact(p_kind text, p_id uuid, p_person text)
returns public.client_contacts
language plpgsql stable security definer set search_path = public as $$
declare
  v_p text := btrim(regexp_replace(lower(coalesce(p_person, '')), '[^a-z0-9]+', ' ', 'g'));
  r public.client_contacts; v_n int;
begin
  if v_p = '' then return r; end if;
  select k.* into r from public.client_contacts k
   where k.archived_at is null
     and (case when p_kind = 'client' then k.client_id = p_id
               else k.client_id in (select ce.client_id from public.client_entities ce where ce.entity_id = p_id) end)
     and v_p in (btrim(regexp_replace(lower(coalesce(k.name, '')), '[^a-z0-9]+', ' ', 'g')),
                 btrim(regexp_replace(lower(public.contact_named(k.salutation, k.name)), '[^a-z0-9]+', ' ', 'g')))
   order by k.is_primary desc, k.name
   limit 1;
  if r.id is not null then return r; end if;
  select count(*), (array_agg(k.id))[1] into v_n, r.id from public.client_contacts k
   where k.archived_at is null
     and (case when p_kind = 'client' then k.client_id = p_id
               else k.client_id in (select ce.client_id from public.client_entities ce where ce.entity_id = p_id) end)
     and btrim(regexp_replace(lower(coalesce(k.name, '')), '[^a-z0-9]+', ' ', 'g')) <> ''
     and string_to_array(btrim(regexp_replace(lower(coalesce(k.name, '')), '[^a-z0-9]+', ' ', 'g')), ' ')
         <@ string_to_array(v_p, ' ');
  if v_n is distinct from 1 then return null::public.client_contacts; end if;
  select k.* into r from public.client_contacts k where k.id = r.id;
  return r;
end $$;
revoke all on function public.bukku_person_contact(text, uuid, text) from public, anon, authenticated;

-- END OF BUKKU PERSON BY ITS WORDS ------------------------------------------

select public.functions_tidy();
