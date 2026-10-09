-- ===========================================================================
-- WHATSAPP BY GROUP — a user group may be kept from sending on WhatsApp.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-09: "can we hide the sent via whatsapp
-- button from certain team group?")
--   Two parts, each following its section unless a group's panel shuts it
--   (No Access): `reports.whatsapp` (Send on WhatsApp on a published report)
--   and `clients.whatsapp` (Request feedback on WhatsApp in a client's ⋯).
--   `wa_report_prepare`, `wa_feedback_prepare` and `wa_record` ask the part
--   at Work in place of the section, so a shut group is refused by the
--   database as well as not shown the button.
--
-- ROLLBACK
--   Restate the three functions from 2026-10-09-contact-salutation.sql and
--   2026-10-09-whatsapp.sql. A part left stored on a group changes nothing
--   once nothing asks it.
-- ===========================================================================

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
  if not public.allowed('reports.whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
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
  if not public.allowed('clients.whatsapp', 'work') then return jsonb_build_object('error', 'denied'); end if;
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

create or replace function public.wa_record(p_purpose text, p_ref uuid, p_client uuid, p_number text, p_name text,
                                            p_template text, p_params jsonb, p_ok boolean, p_wa_id text, p_error text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  v_cl text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('report', 'feedback') then return jsonb_build_object('error', 'bad-purpose'); end if;
  if (p_purpose = 'report' and not public.allowed('reports.whatsapp', 'work'))
     or (p_purpose = 'feedback' and not public.allowed('clients.whatsapp', 'work')) then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_seen(p_client, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, params, ref_kind, ref_id, client_id, state,
                                wa_id, error, created_by, sent_at, tries)
  values (p_purpose, coalesce(p_number, ''), p_name, coalesce(p_template, ''), coalesce(p_params, '[]'::jsonb),
          case when p_purpose = 'report' then 'report' else 'client' end, p_ref, p_client,
          case when p_ok then 'sent' else 'failed' end, left(p_wa_id, 200), left(p_error, 500), me.name,
          case when p_ok then now() end, 1);
  select c.name into v_cl from public.clients c where c.id = p_client;
  if p_ok then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'wa.sent', v_cl, case when p_purpose = 'report' then 'Report sent on WhatsApp' else 'Feedback request sent on WhatsApp' end
            || coalesce(' to ' || nullif(btrim(p_name), ''), ''));
  end if;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.wa_record(text, uuid, uuid, text, text, text, jsonb, boolean, text, text) from public, anon;
grant execute on function public.wa_record(text, uuid, uuid, text, text, text, jsonb, boolean, text, text) to authenticated;

-- END OF WHATSAPP BY GROUP ----------------------------------------------------

select public.functions_tidy();
