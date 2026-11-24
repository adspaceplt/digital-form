-- ===========================================================================
-- QUOTATION CHANGES REQUESTED (2026-11-25)
-- ===========================================================================
-- WHY: the user decided "Prices after we send" (2026-11-25): the priced,
-- changeable view of a quotation stands only on the quotation the team has
-- sent, at its own private link. There the prospect may change the plan,
-- platforms, additional content, files and commitment and see the price
-- follow; a changed selection is not signed but sent back to the team as
-- Request these changes, which the team confirms by sending a revision.
--
-- WHAT CHANGED
--   * `quotations.change_request` (the selection asked for, when, and its
--     figures) and `change_requested_at`, read by the Services pane
--     (granted to authenticated).
--   * `quote_change_open(p_key)` (internal): the quotation a link shows,
--     while it may still be changed or signed: sent, not cancelled, not
--     signed, not expired; else `not-found`, `closed`, `unsent`, `signed`,
--     `expired`. `quote_sign_open` reads it and refuses `changes` while a
--     change request stands, so Accept and sign waits for the revision.
--   * `quote_change_sel(p_base, p_sel, p_snap)` (internal): the quotation's
--     own selection with the prospect's plan, content option, platforms,
--     additional content, files (the card's File Release add-ons) and
--     commitment (6, 12 or 24 months, or the quotation's own) in place of
--     its own; every line the team added stays as the team made it. A
--     quotation of several brands is not changed (`brands`).
--   * `quote_website_preview(p_key, p_sel)` (anon, writes nothing): the
--     quotation priced as its selection would be with those changes, on its
--     own Rate Card version, day and currency, with each plan's, platform's,
--     file's and term's price for the choices, and any change request.
--   * `quote_change_request(p_key, p_sel)` (anon): keeps the change request
--     on the quotation shown (a minute apart at least, `recent`; unchanged
--     refused `unchanged`), the reply owed by `quote_reply_by`, and tells
--     who prepared it and the person in charge (else the team who work
--     leads), `quote.changes`; with no selection it withdraws the request.
--
-- ORDER: this file (connector), then the pages. An open page from before
-- never asks for a change; once applied, a quotation with a change request
-- refuses Accept and sign (`changes`), which a page from before reads as
-- "Not sent. Please try again." until reloaded. Safe to run twice.
-- ROLLBACK: run `quote_sign_open` from QUOTATION SIGNING again; the columns
-- and the new functions may stay.
-- ===========================================================================

-- QUOTATION CHANGES REQUESTED -------------------------------------------------

alter table public.quotations add column if not exists change_request      jsonb;
alter table public.quotations add column if not exists change_requested_at timestamptz;
grant select (change_request, change_requested_at) on table public.quotations to authenticated;

/* The quotation a link shows, while it may still be changed or signed. */
create or replace function public.quote_change_open(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if w.status = 'not_proceeding' or q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unsent'); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  return jsonb_build_object('id', q.id);
end $$;
revoke all on function public.quote_change_open(text) from public, anon, authenticated;

/* Accept and sign waits while the prospect's change request stands: the
   team sends the revision, which the link then shows. */
create or replace function public.quote_sign_open(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  o jsonb := public.quote_change_open(p_key);
begin
  if o ? 'error' then return o; end if;
  if exists (select 1 from public.quotations x where x.id = (o->>'id')::uuid and x.change_requested_at is not null) then
    return jsonb_build_object('error', 'changes');
  end if;
  return o;
end $$;
revoke all on function public.quote_sign_open(text) from public, anon, authenticated;

/* The quotation's own selection with the prospect's changes in place. */
create or replace function public.quote_change_sel(p_base jsonb, p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v jsonb := coalesce(p_base, '{}'::jsonb);
  s jsonb;
  k text;
  n int;
  v_ex jsonb := '{}'::jsonb;
  v_once jsonb := '[]'::jsonb;
begin
  if p_sel is null then return v; end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if v ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  if p_sel ? 'plan' then
    s := public.quote_svc(p_snap, p_sel->>'plan');
    if jsonb_typeof(p_sel->'plan') <> 'string' or s is null or s->'spec'->>'role' is distinct from 'plan' or s->>'rate' is null then
      return jsonb_build_object('error', 'bad-plan');
    end if;
    if p_sel->>'plan' is distinct from v->>'plan' then v := v - 'mix' - 'extra'; end if;
    v := v || jsonb_build_object('plan', p_sel->>'plan');
  end if;
  if p_sel ? 'mix' then
    if jsonb_typeof(p_sel->'mix') <> 'string' or p_sel->>'mix' !~ '^[0-9]$' then return jsonb_build_object('error', 'bad-selection'); end if;
    v := v || jsonb_build_object('mix', p_sel->>'mix');
  end if;
  if p_sel ? 'platforms' then
    if jsonb_typeof(p_sel->'platforms') <> 'array' then return jsonb_build_object('error', 'bad-selection'); end if;
    v := v || jsonb_build_object('platforms', coalesce((select jsonb_agg(x order by array_position(array['meta', 'tiktok', 'rednote', 'linkedin'], x))
                                                          from (select distinct x from jsonb_array_elements_text(p_sel->'platforms') x
                                                                 where x in ('meta', 'tiktok', 'rednote', 'linkedin')) d), '[]'::jsonb));
  end if;
  if p_sel ? 'extra' then
    if jsonb_typeof(p_sel->'extra') <> 'object' or (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
      return jsonb_build_object('error', 'bad-extra');
    end if;
    for k in select jsonb_object_keys(p_sel->'extra') loop
      s := public.quote_svc(p_snap, k);
      if s is null or s->'spec'->>'role' is distinct from 'content' or coalesce(p_sel->'extra'->>k, '') !~ '^[0-9]{1,2}$' then
        return jsonb_build_object('error', 'bad-extra');
      end if;
      n := (p_sel->'extra'->>k)::int;
      if n > 0 then v_ex := v_ex || jsonb_build_object(k, n); end if;
    end loop;
    v := v || jsonb_build_object('extra', v_ex);
  end if;
  if p_sel ? 'files' then
    if jsonb_typeof(p_sel->'files') <> 'object' or (select count(*) from jsonb_object_keys(p_sel->'files')) > 5 then
      return jsonb_build_object('error', 'bad-once');
    end if;
    -- the files asked for replace the files held; every other one-off item stays
    select coalesce(jsonb_agg(o), '[]'::jsonb) into v_once from jsonb_array_elements(coalesce(v->'once', '[]'::jsonb)) o
     where not (coalesce(public.quote_svc(p_snap, o->>'slug')->'spec'->>'role', '') = 'addon'
                and public.quote_web_once_ok(public.quote_svc(p_snap, o->>'slug')));
    for k in select jsonb_object_keys(p_sel->'files') loop
      s := public.quote_svc(p_snap, k);
      if s is null or s->'spec'->>'role' is distinct from 'addon' or not public.quote_web_once_ok(s)
         or coalesce(p_sel->'files'->>k, '') !~ '^[0-9]{1,2}$' then
        return jsonb_build_object('error', 'bad-once');
      end if;
      n := (p_sel->'files'->>k)::int;
      if n > 0 then v_once := v_once || jsonb_build_array(jsonb_build_object('slug', k, 'qty', n)); end if;
    end loop;
    v := v || jsonb_build_object('once', v_once);
  end if;
  if p_sel ? 'term' then
    if coalesce(p_sel->>'term', '') !~ '^[0-9]{1,2}$'
       or not ((p_sel->>'term')::int = any (public.quote_web_terms()) or (p_sel->>'term')::int = (p_base->>'term')::int) then
      return jsonb_build_object('error', 'bad-term');
    end if;
    v := v || jsonb_build_object('term', (p_sel->>'term')::int);
  end if;
  return v;
end $$;
revoke all on function public.quote_change_sel(jsonb, jsonb, jsonb) from public, anon, authenticated;

/* The quotation's card, day and currency, as it was priced. */
create or replace function public.quote_change_snap(q public.quotations)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_on date := (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date;
  v_card jsonb := coalesce(public.quote_card(v_on, q.version), public.quote_card());
  v_fx numeric := public.quote_fx(q.client_id, v_on);
begin
  if v_card is null then return null; end if;
  return jsonb_build_object('fx', v_fx, 'version', v_card->>'version',
    'snap', public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', q.client_id, v_on), v_fx));
end $$;
revoke all on function public.quote_change_snap(public.quotations) from public, anon, authenticated;

/* The sent quotation priced with the prospect's changes, and the price of
   each choice; nothing is kept. */
create or replace function public.quote_website_preview(p_key text, p_sel jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  o jsonb := public.quote_change_open(p_key);
  q public.quotations;
  c jsonb;
  v_snap jsonb;
  v_fx numeric;
  v_sel jsonb;
  v_p jsonb;
  v_set jsonb;
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid;
  if q.selection ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  c := public.quote_change_snap(q);
  if c is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := (c->>'fx')::numeric;
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_snap := c->'snap';
  v_set := coalesce(v_snap->'settings', '{}'::jsonb);
  v_sel := public.quote_change_sel(q.selection, p_sel, v_snap);
  if v_sel ? 'error' then return v_sel; end if;
  v_p := public.quote_fx_out(public.quote_compose(v_snap, v_sel, q.source <> 'website'), v_fx);
  if v_p ? 'error' then return jsonb_build_object('error', v_p->>'error'); end if;
  return jsonb_build_object(
    'selection', v_sel,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('slug', l->>'slug', 'kind', l->>'kind', 'basis', l->>'basis',
        'label', l->>'label', 'qty', (l->>'qty')::numeric, 'months', l->'months', 'sst', coalesce(l->'sst', l->'tax_pct'),
        'amount', coalesce((l->>'amount')::numeric, round((l->>'qty')::numeric * (l->>'rate')::numeric, 2))) order by n)
      from jsonb_array_elements(v_p->'lines') with ordinality x(l, n)), '[]'::jsonb),
    'on_request', coalesce(v_p->'on_request', '[]'::jsonb),
    'extra_rates', coalesce(v_p->'extra_rates', '{}'::jsonb),
    'totals', jsonb_build_object('term', v_p->'totals'->'term', 'term_pct', v_p->'totals'->'term_pct',
      'sst_pct', v_p->'totals'->'sst_pct', 'budget', v_p->'totals'->'budget', 'month', v_p->'totals'->'month',
      'once', v_p->'totals'->'once', 'term_rows', v_p->'totals'->'term_rows',
      'currency', q.totals->'currency', 'fx', q.totals->'fx', 'layout', q.totals->'layout',
      'ads', q.totals->'ads', 'ads_total', q.totals->'ads_total'),
    'card', jsonb_build_object(
      'plans', coalesce((select jsonb_object_agg(s->>'slug', (s->>'rate')::numeric) from jsonb_array_elements(v_snap->'services') s
                          where s->'spec'->>'role' = 'plan' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '{}'::jsonb),
      'platforms', coalesce((select jsonb_object_agg(s->'spec'->>'platform', (s->>'rate')::numeric) from jsonb_array_elements(v_snap->'services') s
                          where s->'spec'->>'role' = 'platform' and s->>'rate' is not null and coalesce((s->>'active')::boolean, true)), '{}'::jsonb),
      'files', coalesce((select jsonb_agg(jsonb_build_object('slug', s->>'slug', 'name', s->>'name', 'rate', (s->>'rate')::numeric)
                            order by (s->>'rate')::numeric) from jsonb_array_elements(v_snap->'services') s
                          where s->'spec'->>'role' = 'addon' and public.quote_web_once_ok(s) and s->>'rate' is not null
                            and coalesce((s->>'active')::boolean, true)), '[]'::jsonb),
      'terms', (select jsonb_agg(jsonb_build_object('months', m, 'pct', public.quote_term_pct(v_set, m)) order by m)
                  from (select distinct m from unnest(public.quote_web_terms() || coalesce((q.selection->>'term')::int, 12)) m where m > 1) t)),
    'change', case when q.change_requested_at is not null then q.change_request || jsonb_build_object('at', q.change_requested_at, 'reply_due', q.reply_due) end,
    'version', c->>'version');
end $$;
revoke all on function public.quote_website_preview(text, jsonb) from public;
grant execute on function public.quote_website_preview(text, jsonb) to anon, authenticated;

/* Request these changes: kept on the quotation shown for the team to
   confirm by its revision; no selection withdraws the request. */
create or replace function public.quote_change_request(p_key text, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  o jsonb := public.quote_change_open(p_key);
  q public.quotations;
  cl public.clients;
  c jsonb;
  v_fx numeric;
  v_sel jsonb;
  v_p jsonb;
  v_now timestamptz := now();
  v_body text;
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  select * into cl from public.clients where id = q.client_id;
  if p_sel is null then
    if q.change_requested_at is null then return jsonb_build_object('ok', true, 'again', true); end if;
    update public.quotations set change_request = null, change_requested_at = null where id = q.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.quotation', q.brand, q.ref || ' · changes withdrawn on the quotation link');
    return jsonb_build_object('ok', true);
  end if;
  if q.selection ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  if q.change_requested_at > v_now - interval '1 minute' then return jsonb_build_object('error', 'recent'); end if;
  c := public.quote_change_snap(q);
  if c is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := (c->>'fx')::numeric;
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_sel := public.quote_change_sel(q.selection, p_sel, c->'snap');
  if v_sel ? 'error' then return v_sel; end if;
  -- Unchanged whatever order the platforms were held in.
  if (v_sel - 'platforms') = (q.selection - 'platforms')
     and (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from jsonb_array_elements_text(coalesce(v_sel->'platforms', '[]'::jsonb)) x)
       = (select coalesce(jsonb_agg(x order by x), '[]'::jsonb) from jsonb_array_elements_text(coalesce(q.selection->'platforms', '[]'::jsonb)) x) then
    return jsonb_build_object('error', 'unchanged');
  end if;
  v_p := public.quote_fx_out(public.quote_compose(c->'snap', v_sel, q.source <> 'website'), v_fx);
  if v_p ? 'error' then return jsonb_build_object('error', v_p->>'error'); end if;
  update public.quotations
     set change_request = jsonb_build_object('selection', v_sel,
           'month', v_p->'totals'->'month'->'incl', 'once', v_p->'totals'->'once'->'incl', 'version', c->>'version'),
         change_requested_at = v_now, reply_due = public.quote_reply_by(v_now)
   where id = q.id
   returning * into q;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', q.brand, q.ref || ' · changes requested on the quotation link');
  v_body := q.ref || coalesce(' · ' || coalesce(q.totals->>'currency', 'RM') || ' ' ||
              to_char((v_p->'totals'->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', '')
            || ' · Reply by ' || public.register_day((q.reply_due at time zone 'Asia/Kuala_Lumpur')::date);
  -- Who prepared it and the person in charge are told; where neither is
  -- here, the team who work leads.
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(cl.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.changes', 'Changes requested · ' || q.brand, v_body,
      q.id::text || ':' || v_now::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(cl.owner)],
      'quote.changes', 'Changes requested · ' || q.brand, v_body, q.client_id, q.id::text || ':' || v_now::text);
  end if;
  return jsonb_build_object('ok', true, 'reply_due', q.reply_due);
end $$;
revoke all on function public.quote_change_request(text, jsonb) from public;
grant execute on function public.quote_change_request(text, jsonb) to anon, authenticated;

-- END OF QUOTATION CHANGES REQUESTED -------------------------------------------

select public.functions_tidy();
