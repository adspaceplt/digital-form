-- ===========================================================================
-- CONTACT SALUTATION — how a client's contact is addressed (Mr, Ms, Dato'…),
-- and the WhatsApp greeting that uses it.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-09: "could you add the salutation under
-- clients > contact (doesnt look good to just call the name)")
--   1. `client_contacts.salutation`: Mr, Ms, Mrs, Mdm, Dr, Prof, Dato',
--      Datin, Datuk, Dato' Sri, Datin Sri, Tan Sri, Puan Sri, Tun, Tuan,
--      Puan, Encik, Cik, or none; 30 characters at most.
--   2. `contact_greeting(salutation, name)`: with a salutation, it and the
--      whole name ("Mr Lim Wei Ming": the surname may come first or last, so
--      the name is never cut); without one, the first word of the name, as
--      before. The WhatsApp report and feedback messages greet the main
--      contact with it (`wa_report_prepare`, `wa_feedback_prepare`).
--
-- ROLLBACK
--   Restate the two functions from 2026-10-09-whatsapp.sql. The column may
--   stay.
-- ===========================================================================

alter table public.client_contacts add column if not exists salutation text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'client_contacts_salutation_len') then
    alter table public.client_contacts add constraint client_contacts_salutation_len
      check (salutation is null or length(salutation) <= 30);
  end if;
end $$;

/* How a contact is greeted: the salutation and the whole name, else the
   first word of the name. */
create or replace function public.contact_greeting(p_salutation text, p_name text)
returns text
language sql immutable set search_path = public as $$
  select case when nullif(btrim(coalesce(p_salutation, '')), '') is not null
              then btrim(p_salutation) || ' ' || btrim(coalesce(p_name, ''))
              else split_part(btrim(coalesce(p_name, '')), ' ', 1) end
$$;

revoke all on function public.contact_greeting(text, text) from public, anon, authenticated;

create or replace function public.wa_report_prepare(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r   public.sm_reports;
  c   public.clients;
  k   public.client_contacts;
  t   public.wa_templates;
  v_n text;
begin
  if not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports x where x.id = p_id;
  if r.id is null or not public.client_seen(r.client_id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
  select * into t from public.wa_templates x where x.purpose = 'report' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  select * into c from public.clients x where x.id = r.client_id;
  select * into k from public.client_contacts x where x.client_id = r.client_id and x.archived_at is null
   order by x.is_primary desc nulls last, x.created_at limit 1;
  v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
  if v_n is null then return jsonb_build_object('error', 'no-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'first', public.contact_greeting(k.salutation, k.name),
    'client', coalesce(nullif(r.brand_name, ''), c.name), 'client_id', c.id,
    'template', t.name, 'lang', t.lang, 'params', t.params);
end $$;

revoke all on function public.wa_report_prepare(uuid) from public, anon;
grant execute on function public.wa_report_prepare(uuid) to authenticated;

create or replace function public.wa_feedback_prepare(p_client uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c   public.clients;
  k   public.client_contacts;
  t   public.wa_templates;
  v_n text;
begin
  if not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.clients x where x.id = p_client;
  if c.id is null or not public.client_seen(c.id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.wa_templates x where x.purpose = 'feedback' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  select * into k from public.client_contacts x where x.client_id = c.id and x.archived_at is null
   order by x.is_primary desc nulls last, x.created_at limit 1;
  v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
  if v_n is null then return jsonb_build_object('error', 'no-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'first', public.contact_greeting(k.salutation, k.name),
    'client', c.name, 'client_id', c.id, 'template', t.name, 'lang', t.lang, 'params', t.params);
end $$;

revoke all on function public.wa_feedback_prepare(uuid) from public, anon;
grant execute on function public.wa_feedback_prepare(uuid) to authenticated;

-- END OF CONTACT SALUTATION ---------------------------------------------------

select public.functions_tidy();
