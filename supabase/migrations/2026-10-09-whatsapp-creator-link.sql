-- ===========================================================================
-- WHATSAPP CREATOR LINK — a creator is told on WhatsApp when a booking is
-- confirmed, with a button to their own page; a Singapore number of eight
-- digits is read as one wherever it is typed.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-09: "creator - new job confirmed for them
-- and their link for them for full details"; "does the whatsapp number
-- supports singapore number?")
--   1. `wa_outbox.button`: the variable part of a template's link button
--      (the creator's access code: digital.adspace.me/creator/?k={{1}}),
--      sent by `wa-send` as the button's parameter.
--   2. `wa_enqueue(…, p_button)` queues a message with it; `wa_queue` keeps
--      its arguments and queues with none.
--   3. `campaign_options_wa` tells a creator only that a booking is
--      confirmed (from option, shortlisted or backup): the creator's first
--      name and the campaign, and their code for the button. Changes
--      requested and cleared to post are no longer sent on WhatsApp; the
--      creator's page and its notifications carry them.
--   4. `wa_number`: eight digits starting 3, 6, 8 or 9 take 65 whatever
--      the market (a Malaysian mobile is never eight digits), so a
--      creator's or a colleague's Singapore number reads too.
--
-- ROLLBACK
--   Restate wa_number, wa_queue and campaign_options_wa from
--   2026-10-09-whatsapp.sql. The column may stay.
-- ===========================================================================

alter table public.wa_outbox add column if not exists button text;

/* A WhatsApp number in its international form, or null. */
create or replace function public.wa_number(p_raw text, p_market text default 'MY')
returns text
language sql immutable set search_path = public as $$
  select case
    when p_raw is null or btrim(p_raw) like '@%' then null
    else (select case
            when length(d) < 8 or length(d) > 15 then null
            when upper(coalesce(p_market, 'MY')) = 'SG' and length(d) = 8 then '65' || d
            when length(d) = 8 and d ~ '^[3689]' then '65' || d
            when d like '0%' then '60' || substr(d, 2)
            else d end
          from (select regexp_replace(p_raw, '[^0-9]', '', 'g') as d) x)
  end
$$;

revoke all on function public.wa_number(text, text) from public, anon, authenticated;

/* One message into the queue, where its purpose has a template on and the
   number reads; `p_button` is the variable part of the template's link
   button, where it has one. */
create or replace function public.wa_enqueue(p_purpose text, p_number text, p_name text, p_params jsonb,
                                             p_ref_kind text, p_ref_id uuid, p_client uuid, p_button text)
returns void
language plpgsql security definer set search_path = public as $$
declare t public.wa_templates;
begin
  select * into t from public.wa_templates x where x.purpose = p_purpose and x.active and x.name <> '';
  if t.purpose is null or p_number is null then return; end if;
  insert into public.wa_outbox (purpose, to_number, to_name, template, lang, params, ref_kind, ref_id, client_id, created_by, button)
  values (p_purpose, p_number, p_name, t.name, t.lang,
          coalesce((select jsonb_agg(e.value) from (select value from jsonb_array_elements(coalesce(p_params, '[]'::jsonb)) with ordinality e(value, n)
                     where n <= t.params order by n) e), '[]'::jsonb),
          p_ref_kind, p_ref_id, p_client, 'system', nullif(btrim(coalesce(p_button, '')), ''));
  perform public.wa_kick();
end $$;

revoke all on function public.wa_enqueue(text, text, text, jsonb, text, uuid, uuid, text) from public, anon, authenticated;

create or replace function public.wa_queue(p_purpose text, p_number text, p_name text, p_params jsonb,
                                           p_ref_kind text, p_ref_id uuid, p_client uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.wa_enqueue(p_purpose, p_number, p_name, p_params, p_ref_kind, p_ref_id, p_client, null);
end $$;

revoke all on function public.wa_queue(text, text, text, jsonb, text, uuid, uuid) from public, anon, authenticated;

/* A creator's booking confirmed: told on WhatsApp, with a button to their
   own page. Only that step, and only forward. */
create or replace function public.campaign_options_wa()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k       public.creators;
  v_title text;
  v_cl    uuid;
begin
  if new.state is not distinct from old.state then return new; end if;
  if not (new.state = 'confirmed' and old.state in ('option', 'shortlisted', 'backup')) then return new; end if;
  select * into k from public.creators x where x.id = new.creator_id;
  if k.id is null then return new; end if;
  select coalesce(nullif(btrim(c.title), ''), 'Your campaign'), c.client_id into v_title, v_cl
    from public.campaigns c where c.id = new.campaign_id;
  perform public.wa_enqueue('creator', public.wa_number(k.whatsapp, 'MY'), k.name,
    jsonb_build_array(split_part(btrim(k.name), ' ', 1), v_title), 'option', new.id, v_cl, k.access_code);
  return new;
exception when others then
  return new;
end $$;

revoke all on function public.campaign_options_wa() from public, anon, authenticated;

-- END OF WHATSAPP CREATOR LINK ------------------------------------------------

select public.functions_tidy();
