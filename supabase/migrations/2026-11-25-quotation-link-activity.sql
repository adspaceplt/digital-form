-- ===========================================================================
-- QUOTATION LINK ACTIVITY (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25: every step a prospect or client takes on a
-- quotation link is filed in the Activity record under Clients, the
-- client's name its subject, and each line opens to the visit it came
-- from. Today only a new lead's `client.added` was filed for a website
-- request, and the link's other steps were one `client.quotation` line
-- with no facts.
--
-- WHAT CHANGES
--   * `activity_log.meta` (jsonb, nullable): a line's facts, written by a
--     function alone (`activity_log_stamp` clears it on a page's own
--     insert). A line without it does not open. `activity_log_meta_check`
--     holds it an object that never carries an `ip` key: the caller's
--     address is never kept with a line (PDPA; the 30-day address rule).
--   * `request_relayed(p_name)`: an `x-adspace-{name}` header, taken only
--     beside the relay secret (as `request_ip()` takes the address).
--   * `ua_device(p)`: the device and browser read from a user agent
--     (iPhone · Safari).
--   * `request_visit()`: the caller's device, city (where the edge names
--     one), country and a six-character session reference: a salted hash of
--     the address, the user agent and Malaysia's day, so the lines of one
--     visit match without the address being kept. The salt is
--     `activity_session_salt` in `app_secrets`, made here once.
--   * `quote_activity(q, action, detail, who)`: one line, actor Quotation
--     website, subject the client's name, `meta` the reference, the name
--     and email, and the visit.
--   * Six tags filed under Clients (`activity_section`):
--     `quotation.requested` (a website request, a new lead or a client
--     already held, by trigger `quotations_website_activity`),
--     `quotation.opened` (`quote_opened`, kept once a visit as the signed
--     record keeps it), `quotation.changes` and `quotation.withdrawn`
--     (`quote_change_request`), `quotation.declined` (`quote_decline`) and
--     `quotation.signed` (`quote_sign_finish`), each in place of the
--     `client.quotation` line the function filed before. Each function is
--     restated from its last section with that line alone changed; every
--     refusal is kept.
--
-- ORDER: the pages first (a line with `meta` reads as any other line on a
-- page served before), then this file (connector), then `quote-request`
-- (it relays the caller's device and place for the website request; before
-- it, a website request's line names the edge function's device). Safe to
-- run twice.
-- ROLLBACK: run `activity_log_stamp` (ACTIVITY ACTOR STAMPED),
-- `activity_section` (its last section before this one), `quote_opened`,
-- `quote_sign_finish` and `quote_decline` (SIGNED DOCUMENT SEAL, QUOTATION
-- WAYS OUT) and `quote_change_request` (ONE-TIME, NEVER ONE-OFF) again,
-- then disable trigger `quotations_website_activity`. The column, the
-- helpers and the lines filed may stay.
-- ===========================================================================

-- QUOTATION LINK ACTIVITY ------------------------------------------------------

alter table public.activity_log add column if not exists meta jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'activity_log_meta_check') then
    alter table public.activity_log add constraint activity_log_meta_check
      check (meta is null or (jsonb_typeof(meta) = 'object' and not meta ? 'ip'));
  end if;
end $$;

insert into public.app_secrets (key, value)
select 'activity_session_salt', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
 where not exists (select 1 from public.app_secrets s where s.key = 'activity_session_salt');

/* A header an edge function relays for its caller (`x-adspace-{name}`),
   taken only beside the relay secret, as request_ip() takes the address. */
create or replace function public.request_relayed(p_name text)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  h json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
begin
  if coalesce(p_name, '') !~ '^[a-z]{2,20}$' then return null; end if;
  if nullif(h ->> 'x-adspace-relay', '') is not null
     and h ->> 'x-adspace-relay' = (select s.value from public.app_secrets s where s.key = 'ip_relay_secret') then
    return nullif(btrim(h ->> ('x-adspace-' || p_name)), '');
  end if;
  return null;
end $$;
revoke all on function public.request_relayed(text) from public, anon, authenticated;

/* The device and browser a user agent names, as a person says them:
   iPhone · Safari, Mac · Chrome, Windows · Edge. */
create or replace function public.ua_device(p text)
returns text
language sql immutable set search_path = public as $$
  select nullif(concat_ws(' · ',
    case
      when u ~ 'iPad' then 'iPad'
      when u ~ 'iPhone|iPod' then 'iPhone'
      when u ~ 'Android' and u ~ 'Mobile' then 'Android phone'
      when u ~ 'Android' then 'Android tablet'
      when u ~ 'CrOS' then 'Chromebook'
      when u ~ 'Macintosh|Mac OS X' then 'Mac'
      when u ~ 'Windows' then 'Windows'
      when u ~ 'Linux' then 'Linux'
    end,
    case
      when u ~ 'Edg(e|A|iOS)?/' then 'Edge'
      when u ~ 'OPR/' then 'Opera'
      when u ~ 'SamsungBrowser/' then 'Samsung Internet'
      when u ~ 'FBAN|FBAV|FB_IAB' then 'Facebook'
      when u ~ 'Instagram' then 'Instagram'
      when u ~ 'Firefox/|FxiOS/' then 'Firefox'
      when u ~ 'Chrome/|CriOS/' then 'Chrome'
      when u ~ 'Version/[0-9].*Safari/' then 'Safari'
    end), '')
  from (select coalesce(p, '') as u) t
$$;
revoke all on function public.ua_device(text) from public, anon, authenticated;

/* The visit a line came from: the device and browser, the city where the
   edge names one, the country, and a session reference matching the lines
   of one visit (the address, the user agent and Malaysia's day, salted and
   hashed to six characters). The address itself is never answered. */
create or replace function public.request_visit()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  h json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  v_agent text := left(coalesce(public.request_relayed('agent'), h ->> 'user-agent', ''), 400);
  v_country text := upper(coalesce(public.request_relayed('country'), public.request_country(), ''));
  v_city text := left(public.seal_device(coalesce(public.request_relayed('city'), h ->> 'cf-ipcity')), 80);
  v_ip text := coalesce(public.request_ip(), '');
  v_salt text := (select s.value from public.app_secrets s where s.key = 'activity_session_salt');
begin
  if v_country !~ '^[A-Z]{2}$' or v_country in ('XX', 'T1') then v_country := null; end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'device', public.ua_device(v_agent),
    'city', v_city,
    'country', v_country,
    'session', case when v_salt is not null and (v_ip <> '' or v_agent <> '') then
      upper(left(encode(digest(v_salt || '|' || v_ip || '|' || v_agent || '|' ||
        ((now() at time zone 'Asia/Kuala_Lumpur')::date)::text, 'sha256'), 'hex'), 6)) end));
end $$;
revoke all on function public.request_visit() from public, anon, authenticated;

/* One step on a quotation link, filed under Clients: the client's name its
   subject, the one-line detail, and the line's facts (the reference, who,
   and the visit). */
create or replace function public.quote_activity(p_q public.quotations, p_action text, p_detail text, p_who jsonb)
returns void
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name text;
begin
  select c.name into v_name from public.clients c where c.id = p_q.client_id;
  insert into public.activity_log (actor, action, subject, detail, meta)
  values ('Quotation website', p_action, coalesce(v_name, p_q.brand), p_detail,
          jsonb_strip_nulls(jsonb_build_object('ref', p_q.ref,
            'name', nullif(btrim(coalesce(p_who->>'salutation', '') || ' ' || coalesce(p_who->>'name', '')), ''),
            'email', nullif(lower(btrim(coalesce(p_who->>'email', ''))), ''))) || public.request_visit());
end $$;
revoke all on function public.quote_activity(public.quotations, text, text, jsonb) from public, anon, authenticated;

/* A quotation requested on the website, for a new lead or a client the
   team already holds: one line however the request found its client. */
create or replace function public.quotations_website_activity()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  c public.clients;
begin
  select * into c from public.clients x where x.id = new.client_id;
  perform public.quote_activity(new, 'quotation.requested',
    new.ref || ' · ' || case when c.created_at >= now() then 'New lead'
                             when c.stage in ('lead', 'contacted', 'proposal') then 'Existing lead'
                             else 'Existing client' end,
    new.contact);
  return null;
end $$;
revoke all on function public.quotations_website_activity() from public, anon, authenticated;
create or replace trigger quotations_website_activity after insert on public.quotations
  for each row when (new.source = 'website') execute function public.quotations_website_activity();

create or replace function public.activity_log_stamp()
returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' then
    new.actor := coalesce(nullif(lower(auth.jwt() ->> 'email'), ''), 'unknown');
    new.created_at := now();
    -- A line's facts are a function's alone (QUOTATION LINK ACTIVITY).
    new.meta := null;
  end if;
  return new;
end $$;
revoke all on function public.activity_log_stamp() from public, anon, authenticated;
create or replace trigger activity_log_stamp before insert on public.activity_log
  for each row execute function public.activity_log_stamp();

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('assistant.campaign', 'campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.file_deleted', 'campaign.file_hidden',
                    'campaign.file_shown', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.offered', 'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.unoffered', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('assistant.call', 'client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.quotation', 'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_deleted', 'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.added', 'request.changed', 'request.deleted', 'request.raised',
                    'quotation.changes', 'quotation.declined', 'quotation.opened', 'quotation.requested',
                    'quotation.signed', 'quotation.withdrawn',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('assistant.whatsapp', 'wa.sent', 'wa.template', 'email.sent') then 'whatsapp'
    when action in ('assistant.report', 'report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished', 'report.version_deleted') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('assistant.meeting', 'assistant.schedule', 'assistant.task', 'ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('supplier.added', 'supplier.approved', 'supplier.deleted', 'supplier.edited') then 'suppliers'
    when action in ('assistant.set', 'client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.month', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('script.approved', 'script.changes', 'script.created', 'script.deleted',
                    'script.link', 'script.saved', 'script.shared', 'script.shot',
                    'script.unshared') then 'scripts'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on', 'service.published') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited', 'team.revealed') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

create or replace function public.quote_opened(p_key text, p_device text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  v_ip  text := nullif(public.request_ip(), '');
  v_dev text := public.seal_device(p_device);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if public.is_team() then return jsonb_build_object('ok', true, 'kept', false); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if q.id is null or (q.source = 'website' and q.released_at is null) then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  if exists (select 1 from public.signing_steps s
              where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened'
                and s.at > now() - interval '6 hours'
                and s.ip is not distinct from v_ip and s.device is not distinct from v_dev)
     or (select count(*) from public.signing_steps s
          where s.doc_kind = 'quotation' and s.doc_id = q.id and s.step = 'opened') >= 100 then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  insert into public.signing_steps (doc_kind, doc_id, step, ip, country, device)
  values ('quotation', q.id, 'opened', v_ip, nullif(public.request_country(), ''), v_dev);
  -- The same opening, kept once, is the Activity record's line.
  perform public.quote_activity(q, 'quotation.opened', q.ref, q.contact);
  return jsonb_build_object('ok', true, 'kept', true);
end $$;
revoke all on function public.quote_opened(text, text) from public;
grant execute on function public.quote_opened(text, text) to anon, authenticated;

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
    perform public.quote_activity(q, 'quotation.withdrawn', q.ref, q.contact);
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
  perform public.quote_activity(q, 'quotation.changes', q.ref || coalesce(' · ' || coalesce(q.totals->>'currency', 'RM') || ' ' ||
    to_char((v_p->'totals'->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', ''), q.contact);
  v_body := q.ref || coalesce(' · ' || coalesce(q.totals->>'currency', 'RM') || ' ' ||
              to_char((v_p->'totals'->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', '')
            || ' · Send by ' || public.register_day((q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
            || ' (' || trim(to_char(q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
            lower(to_char(q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam'));
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

create or replace function public.quote_decline(p_key text, p_reason text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  c public.clients;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if char_length(coalesce(v_reason, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id) for update;
  if q.id is null or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if q.declined_at is not null then return jsonb_build_object('ok', true, 'again', true); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unsent'); end if;
  if q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  update public.quotations set status = 'not_proceeding', declined_at = now(), decline_reason = v_reason where id = q.id;
  insert into public.signing_steps (doc_kind, doc_id, step, ip, country)
  values ('quotation', q.id, 'declined', nullif(public.request_ip(), ''), nullif(public.request_country(), ''));
  perform public.quote_activity(q, 'quotation.declined', q.ref || coalesce(' · ' || v_reason, ''), q.contact);
  select * into c from public.clients where id = q.client_id;
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(c.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.declined', 'Quotation declined · ' || q.brand,
      q.ref || coalesce(' · ' || v_reason, ''), q.id::text || ':declined');
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(c.owner)],
      'quote.declined', 'Quotation declined · ' || q.brand, q.ref || coalesce(' · ' || v_reason, ''),
      q.client_id, q.id::text || ':declined');
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quote_decline(text, text) from public;
grant execute on function public.quote_decline(text, text) to anon, authenticated;

create or replace function public.quote_sign_finish(p_key text, p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  o   jsonb := public.quote_sign_open(p_key);
  q   public.quotations;
  s   public.quote_sign_codes;
  c   public.clients;
  h   json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  v_at timestamptz := now();
begin
  if o ? 'error' then return o; end if;
  select * into q from public.quotations where id = (o->>'id')::uuid for update;
  -- Read again once the row is held: a colleague's Mark signed, Cancel or
  -- revision meanwhile is seen (audit 2026-11-04).
  o := public.quote_sign_open(p_key);
  if o ? 'error' then return o; end if;
  if (o->>'id')::uuid is distinct from q.id then return jsonb_build_object('error', 'not-found'); end if;
  select * into s from public.quote_sign_codes x
   where x.quotation_id = q.id and x.used_at is null
   order by x.created_at desc limit 1 for update;
  if s.id is null then return jsonb_build_object('error', 'no-code'); end if;
  if s.expires_at <= now() then return jsonb_build_object('error', 'code-expired'); end if;
  if s.tries >= 5 then return jsonb_build_object('error', 'locked'); end if;
  if regexp_replace(coalesce(p_code, ''), '\s+', '', 'g') !~ '^[0-9]{6}$'
     or crypt(regexp_replace(p_code, '\s+', '', 'g'), s.code_hash) <> s.code_hash then
    update public.quote_sign_codes set tries = tries + 1 where id = s.id;
    return jsonb_build_object('error', 'wrong', 'left', greatest(0, 4 - s.tries));
  end if;
  update public.quote_sign_codes set used_at = v_at where id = s.id;
  update public.quotations
     set signed_at = v_at,
         signed = jsonb_build_object('via', 'online') || (s.payload - 'device') || jsonb_build_object('record', jsonb_build_object(
           'at', v_at, 'email', s.email,
           'in_contacts', exists (select 1 from public.client_contacts k
                                   where k.client_id = q.client_id and k.archived_at is null
                                     and lower(btrim(coalesce(k.email, ''))) = lower(btrim(coalesce(s.email, ''))))
                          or lower(btrim(coalesce(q.contact->>'email', ''))) = lower(btrim(coalesce(s.email, ''))),
           'ip', nullif(public.request_ip(), ''), 'country', nullif(public.request_country(), ''),
           'agent', left(coalesce(h ->> 'user-agent', ''), 300),
           -- The device as the signer's browser reported it with the code.
           'device', s.payload->>'device',
           'fingerprint', upper(left(encode(digest(q.ref || q.lines::text || q.totals::text || s.payload::text || v_at::text, 'sha256'), 'hex'), 16)))),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  select * into c from public.clients where id = q.client_id;
  perform public.quote_activity(q, 'quotation.signed',
    q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name'),
    jsonb_build_object('name', s.payload->'signer'->>'name', 'email', s.email));
  -- Who prepared it and the person in charge are told; where neither is
  -- here (a website lead nobody has taken), the team who work leads.
  if public.quote_sign_member(q.made_by) is null and public.quote_sign_member(c.owner) is null then
    perform public.quote_tell(q.client_id, 'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.id::text || ':' || v_at::text);
  else
    perform public.quote_sign_tell(array[public.quote_sign_member(q.made_by), public.quote_sign_member(c.owner)],
      'quote.signed', 'Quotation signed · ' || q.brand,
      q.ref || ' · ' || (s.payload->'signer'->>'name') || ' for ' || (s.payload->'company'->>'legal_name') || ' · check and submit',
      q.client_id, q.id::text || ':' || v_at::text);
  end if;
  return jsonb_build_object('ok', true, 'at', v_at);
end $$;
revoke all on function public.quote_sign_finish(text, text) from public;
grant execute on function public.quote_sign_finish(text, text) to anon, authenticated;

-- END OF QUOTATION LINK ACTIVITY -----------------------------------------------

select public.functions_tidy();
