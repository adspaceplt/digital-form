-- ===========================================================================
-- QUOTATION TAX DAY — a quotation charges SST at the rate in force on its own
-- day, never on a client exempt from it, and an expired one issues no Letter
-- of Offer (2026-10-15)
-- ===========================================================================
-- WHY (the audit of 2026-10-15, I1, I5, I6, S8)
--   * I5: SST was the rate kept in the rate card version when it was
--     published, so an SST change set from a later day left every later
--     quotation on the old rate while the Letter of Offer used the new one.
--   * I1: `quote_price` charged SST whatever the client's `sst_applies`, so
--     an exempt client's quotation read "incl. SST" and its Letter of Offer
--     carried none.
--   * I6: Issue Letter of Offer worked on a quotation the page showed as
--     Expired.
--   * S8: `rate_card_current()` answered every colleague, though the tables
--     it reads answer Services at View.
--
-- WHAT CHANGED
--   * `quote_tax_snap(p_snap, p_client)` (internal): the version's snapshot
--     with `settings.sst_pct` set to today's SST (MYT, `app_setting`), or 0
--     where the client's `sst_applies` is false.
--   * `quote_preview(p_sel)` prices on it; `p_sel.client` (optional, a
--     client the caller sees at View) names whose exemption applies, and is
--     never priced or kept.
--   * `quotation_make` prices on it for its client, and keeps no `client`.
--   * `quotation_offer` refuses `expired` once `valid_until` has passed
--     (MYT); the page offers it only while the quotation is valid.
--   * `rate_card_current()` answers at Services or Clients: Services View.
--
-- ORDER
--   This file, then the pages (`js/quotes.js` sends `client` with a
--   preview and names `expired`). A page from before previews without the
--   exemption (Make still applies it) and is told `expired` in its general
--   words.
--
-- Safe to run twice. Rollback: run QUOTATION RATES's quote_preview,
-- quotation_make and quotation_offer and RATE CARD VERSIONS's
-- rate_card_current again; drop function quote_tax_snap(jsonb, uuid).
-- ===========================================================================

create or replace function public.quote_tax_snap(p_snap jsonb, p_client uuid)
returns jsonb
language sql stable set search_path = public as $$
  select jsonb_set(coalesce(p_snap, '{}'::jsonb), '{settings}',
           coalesce(p_snap->'settings', '{}'::jsonb) || jsonb_build_object('sst_pct',
             case when exists (select 1 from public.clients c where c.id = p_client and c.sst_applies is false) then 0
                  else coalesce(public.app_setting('sst_pct', (now() at time zone 'Asia/Kuala_Lumpur')::date),
                                (p_snap->'settings'->>'sst_pct')::numeric, 0) end))
$$;
revoke all on function public.quote_tax_snap(jsonb, uuid) from public, anon, authenticated;

create or replace function public.quote_preview(p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_card jsonb := public.quote_card();
  v_cl uuid;
begin
  if not public.is_team() or not public.allowed('clients.services', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  if coalesce(p_sel->>'client', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and public.client_scope_ok('client', (p_sel->>'client')::uuid, 'view') then
    v_cl := (p_sel->>'client')::uuid;
  end if;
  return public.quote_adjust(public.quote_price(public.quote_tax_snap(v_card->'snapshot', v_cl), p_sel - 'client'), p_sel->'edits') ||
         jsonb_build_object('version', v_card->>'version');
end $$;
revoke all on function public.quote_preview(jsonb) from public, anon;
grant execute on function public.quote_preview(jsonb) to authenticated;

create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_card jsonb := public.quote_card();
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
  v_sel jsonb := case when jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      when p_source = 'console' then p_sel - 'client'
                      else p_sel - 'edits' - 'client' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_p := public.quote_adjust(public.quote_price(public.quote_tax_snap(v_card->'snapshot', v_c.id), v_sel), v_sel->'edits');
  if v_p ? 'error' then return v_p; end if;
  v_days := coalesce(public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key)
  values (public.quote_ref(v_c.name, v_now), v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request'), p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end)
  returning * into v_q;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || ' sent · ' || coalesce('Monthly incl. SST RM ' ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') ||
          ' · rate card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.quotation_offer(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_l jsonb;
  v_ids uuid[] := '{}';
  v_id uuid;
begin
  if me.id is null or not public.allowed('clients.services', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or v_q.removed_at is not null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  select coalesce(array_agg(s.id order by s.created_at), '{}') into v_ids
    from public.client_services s where s.quotation_id = v_q.id and s.archived_at is null;
  if array_length(v_ids, 1) is not null then return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids), 'again', true); end if;
  if v_q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  for v_l in select * from jsonb_array_elements(v_q.lines) loop
    insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                        tenure, term_adjust, term_pct, detail, quotation_id)
    values (v_q.client_id,
            case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
            v_l->>'label', (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
            case when v_l->>'basis' = 'month' then 'Per month' else 'One-off' end, 'quoted',
            'Quotation ' || v_q.ref,
            case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (v_q.totals->>'term')::int) else 1 end,
            v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (v_q.totals->>'term_pct')::numeric else 0 end,
            nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
            v_q.id)
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' · ' || array_length(v_ids, 1) || ' lines To quote for the Letter of Offer');
  return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids));
end $$;
revoke all on function public.quotation_offer(uuid) from public, anon;
grant execute on function public.quotation_offer(uuid) to authenticated;

create or replace function public.rate_card_current()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version', v.version, 'valid_until', v.valid_until,
           'published_at', v.published_at, 'published_by', v.published_by, 'snapshot', v.snapshot)
    from public.rate_card_versions v
   where public.is_team() and (public.allowed('services', 'view') or public.allowed('clients.services', 'view'))
   order by v.published_at desc
   limit 1
$$;
revoke all on function public.rate_card_current() from public, anon;
grant execute on function public.rate_card_current() to authenticated;

-- END OF QUOTATION TAX DAY ----------------------------------------------------
select public.functions_tidy();
