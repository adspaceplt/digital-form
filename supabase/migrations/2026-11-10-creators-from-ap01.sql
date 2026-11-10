-- ===========================================================================
-- CREATORS FROM AP01 — 2026-11-10. The user, 2026-11-10: the creators already on record (the AP01 form and
-- its spreadsheet) come into the portal once. Three things they need:
--
--   1. `creators.inactive_reason`: why a creator is inactive (Blacklisted),
--      set beside Set inactive and cleared by Set active (`active` or no
--      reason, a check holds it).
--   2. Payment details brought in are filed approved where the creator was
--      already paid through Bukku (`creator_pay_requests.source` `import`);
--      the AP01 form asked no billing address before January 2026, so such
--      a set may hold none (its SQL Editor part lets the column be empty
--      for `import` alone). The creator's page then asks for the address
--      alone (`creator_pay_form` `address_needed`;
--      `creator_pay_address(p_code, p_address)`, anon, the code counted as
--      `get_creator` counts it: `bad`, `not-needed`), written onto the set
--      approved, which needs no approval again (the payee, bank and account
--      are not touched), filed `creator.updated` under the creator page.
--   3. `profile_of` reads a rednote search link
--      (`rednote.com/search_result?keyword=…`), kept with no handle as a
--      short link is: a creator who gave a rednote ID or name rather than a
--      profile link is found by it.
--
-- Run its SQL Editor part (2026-11-10-creators-from-ap01-editor.sql) first:
-- it lets an imported set's address be empty. Re-runnable. Rollback: drop
-- the columns' checks and `creator_pay_address`; run CREATOR PAGE DETAILS
-- MASKED and the earlier `profile_of` again.

alter table public.creators add column if not exists inactive_reason text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'creators_inactive_reason_check') then
    alter table public.creators add constraint creators_inactive_reason_check
      check (inactive_reason is null or (not active and char_length(btrim(inactive_reason)) between 1 and 200));
  end if;
end $$;

alter table public.creator_pay_requests add column if not exists source text not null default 'creator';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'creator_pay_requests_source_check') then
    alter table public.creator_pay_requests add constraint creator_pay_requests_source_check
      check (source in ('creator', 'import'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'creator_pay_requests_address_check') then
    alter table public.creator_pay_requests add constraint creator_pay_requests_address_check
      check (address is not null or source = 'import');
  end if;
end $$;

/* A set as the creator's page reads it: the numbers as their last four. */
create or replace function public.creator_pay_json(r public.creator_pay_requests, p_whole boolean)
returns jsonb language sql stable set search_path = public as $$
  select case when r.id is null then null else jsonb_build_object(
    'id', r.id, 'ref', r.ref, 'status', r.status, 'created_at', r.created_at, 'decided_at', r.decided_at,
    'note', r.note, 'bill_kind', r.bill_kind, 'source', r.source,
    'id_no', case when p_whole then r.id_no end, 'id_end', right(regexp_replace(r.id_no, '\W', '', 'g'), 4),
    'legal_name', r.legal_name, 'tin', r.tin, 'address', r.address, 'currency', r.currency,
    'method', r.method, 'method_word', public.creator_pay_method(r.method, r.bank), 'bank', r.bank,
    'account', case when p_whole then r.account end, 'account_end', right(r.account, 4),
    'payee', r.payee, 'email', r.email, 'whatsapp', r.whatsapp) end
$$;
revoke all on function public.creator_pay_json(public.creator_pay_requests, boolean) from public, anon, authenticated;

create or replace function public.creator_pay_form(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     public.creators;
  v_last public.creator_pay_requests;
  v_paid public.creator_pay_requests;
  v_day  date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators x where x.id = v_id;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;
  select * into v_last from public.creator_pay_requests x where x.creator_id = cr.id and x.status <> 'withdrawn'
   order by x.seq desc limit 1;
  select * into v_paid from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  return jsonb_build_object('ok', true, 'due', public.creator_pay_due(cr.id), 'whatsapp', public.creator_mask_phone(cr.whatsapp),
    'address_needed', v_paid.id is not null and v_paid.address is null,
    'last', public.creator_pay_masked(public.creator_pay_json(v_last, false)),
    'paid', public.creator_pay_masked(public.creator_pay_json(v_paid, false)),
    'days', jsonb_build_object('myr', public.app_setting('creator_pay_days_myr', v_day),
                               'other', public.app_setting('creator_pay_days_other', v_day)),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'job', public.creator_job_ref(o.id), 'campaign', m.title, 'state', o.state,
        'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'paid_at', b.paid_seen_at, 'amount', b.amount, 'currency', b.currency)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = cr.id and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb));
end $$;
grant execute on function public.creator_pay_form(text) to anon, authenticated;

/* The billing address alone, onto the set approved that holds none. */
create or replace function public.creator_pay_address(p_code text, p_address text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     public.creators;
  v_paid public.creator_pay_requests;
  v_addr text := btrim(regexp_replace(coalesce(p_address, ''), '\s+', ' ', 'g'));
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators x where x.id = v_id;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;
  if length(v_addr) < 5 or length(v_addr) > 300 then return jsonb_build_object('error', 'bad', 'field', 'address'); end if;
  select * into v_paid from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
   order by x.decided_at desc limit 1 for update;
  if v_paid.id is null or v_paid.address is not null then return jsonb_build_object('error', 'not-needed'); end if;
  update public.creator_pay_requests x set address = v_addr where x.id = v_paid.id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Creator page', 'creator.updated', cr.name,
          coalesce(cr.creator_code || ' · ', '') || 'Billing address added · ' || v_paid.ref);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_pay_address(text, text) from public;
grant execute on function public.creator_pay_address(text, text) to anon, authenticated;

/* One reading of a profile link. Returns {platform, handle, url} or null.
   The host is taken from the URL's own authority and must be the platform's
   (with or without www. or m.); a URL that merely contains "instagram.com/"
   somewhere, as a query or a path on another site, is not a profile. The
   link stored is rebuilt from what was read, so trailing tracking
   parameters, fragments and anything else typed after the handle are gone.
   A rednote short link (xhslink) names nobody, so it is kept as typed on its
   own host with a null handle and cannot claim an identity; a rednote search
   for a creator's ID or name (2026-11-10) is kept the same way. */
create or replace function public.profile_of(p_url text)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v    text := btrim(coalesce(p_url, ''));
  m    text[];
  host text;
  bare text;
  path text;
  q    text;
  h    text;
begin
  if v = '' or length(v) > 300 or v ~ '\s' then return null; end if;
  if v !~* '^https?://' then v := 'https://' || v; end if;
  m := regexp_match(v, '^https?://([^/?#]+)([^?#]*)(\?[^#]*)?', 'i');
  if m is null then return null; end if;
  host := lower(m[1]);
  if host ~ '[@:]' then return null; end if;
  bare := regexp_replace(host, '^(www\.|m\.|mobile\.|web\.)', '');
  path := coalesce(m[2], '');
  q := coalesce(m[3], '');

  if bare = 'instagram.com' then
    m := regexp_match(path, '^/([A-Za-z0-9._]{1,40})/?$');
    if m is null then return null; end if;
    h := m[1];
    if lower(h) in ('p', 'reel', 'reels', 'stories', 'explore', 'tv', 'accounts', 'direct') then
      return null;
    end if;
    return jsonb_build_object('platform', 'instagram', 'handle', h,
      'url', 'https://www.instagram.com/' || h || '/');

  elsif bare = 'tiktok.com' then
    m := regexp_match(path, '^/@([A-Za-z0-9._]{1,40})/?$');
    if m is null then return null; end if;
    return jsonb_build_object('platform', 'tiktok', 'handle', m[1],
      'url', 'https://www.tiktok.com/@' || m[1]);

  elsif bare = 'facebook.com' then
    if path ~* '^/profile\.php/?$' then
      m := regexp_match(q, '[?&]id=([0-9]{5,20})(&|$)');
      if m is null then return null; end if;
      return jsonb_build_object('platform', 'facebook', 'handle', m[1],
        'url', 'https://www.facebook.com/profile.php?id=' || m[1]);
    end if;
    m := regexp_match(path, '^/people/([^/]{1,80})/([0-9]{5,20})/?$');
    if m is not null then
      return jsonb_build_object('platform', 'facebook', 'handle', m[2],
        'url', 'https://www.facebook.com/profile.php?id=' || m[2]);
    end if;
    m := regexp_match(path, '^/([A-Za-z0-9.]{2,60})/?$');
    if m is null then return null; end if;
    h := m[1];
    if lower(h) in ('pages', 'groups', 'watch', 'events', 'marketplace', 'people',
                    'share', 'sharer', 'reel', 'reels', 'stories', 'hashtag', 'login',
                    'help', 'photo.php', 'story.php', 'permalink.php') then
      return null;
    end if;
    return jsonb_build_object('platform', 'facebook', 'handle', h,
      'url', 'https://www.facebook.com/' || h);

  elsif bare in ('xiaohongshu.com', 'rednote.com') then
    if path ~* '^/search_result/?$' then
      m := regexp_match(q, '[?&]keyword=([A-Za-z0-9%._~+-]{1,120})(&|$)');
      if m is null then return null; end if;
      return jsonb_build_object('platform', 'xhs', 'handle', null,
        'url', 'https://www.rednote.com/search_result?keyword=' || m[1]);
    end if;
    m := regexp_match(path, '^/user/profile/([0-9a-zA-Z]{8,40})/?$');
    if m is null then return null; end if;
    return jsonb_build_object('platform', 'xhs', 'handle', m[1],
      'url', 'https://' || host || '/user/profile/' || m[1]);

  elsif bare in ('xhslink.com', 'xhslink.cn') then
    m := regexp_match(path, '^/([A-Za-z0-9/_-]{2,60})$');
    if m is null then return null; end if;
    return jsonb_build_object('platform', 'xhs', 'handle', null,
      'url', 'https://' || host || '/' || m[1]);
  end if;
  return null;
end $$;
grant execute on function public.profile_of(text) to anon, authenticated;

-- END OF CREATORS FROM AP01 --------------------------------------------------

select public.functions_tidy();
