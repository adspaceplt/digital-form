-- ===========================================================================
-- CONFIRM ONCE — a client's creator selection, the team's Confirm creators
-- and a portal request are each one act that happens once (audit F1, S3, C1,
-- 2026-10-10). 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored
-- byte for byte in supabase/schema.sql under the same banner; tests/sql.js
-- compares the two.
--
-- WHAT CHANGED
--   1. `confirm_selection_with(p_token, p_person, p_passcode, p_selected,
--      p_backup, p_seen, p_idem)`: the selection page's Confirm sends the
--      creators on the client's screen, the price shown for each and a key
--      made once for the press. Under the campaign's row lock it refuses
--      `empty`, `closed`, `over-slots`, `stale` (a creator no longer open to
--      choose) and `prices` (a price changed since the page read it; the
--      answer carries the prices now), then saves the selection and files
--      the confirmation with what was confirmed (`snapshot`) in the same
--      transaction. The same key again answers `ok` with `again` and files
--      nothing. Joins `open_to_anon`: run 2026-10-07-function-hygiene.sql
--      again BEFORE this file.
--   2. `confirm_selection` (a page loaded before this one) refuses `empty`
--      when nothing is shortlisted (a backup, once selection has closed),
--      so a selection that never saved is never confirmed.
--   3. `campaign_confirm_creators(p_campaign, p_options, p_person, p_source,
--      p_idem)`: the console's Confirm creators, Creator Campaigns at Work on
--      a client in scope. Every named booking must still be shortlisted on
--      that campaign (`stale` with the count), then the confirmation, the
--      bookings and the campaign's state move together, filed
--      `campaign.locked`; the same key again files nothing.
--   4. `portal_request_once(p_client, p_kind, p_service, p_note, p_idem)`:
--      the portal's Request change keeps one key from the sheet's opening
--      until it is sent, so a reply lost on the way and a second press file
--      one request. `portal_request` (an older page) is the same with no key.
--   5. `campaign_confirmations.idem`, `.snapshot`, `client_requests.idem`,
--      each key unique within its campaign or client.
--
-- ROLLBACK
--   Pages first (they fall back to the older functions where these are
--   missing), then remove the three new functions, put `confirm_selection`
--   and `portal_request` back from their earlier bands, and leave the
--   columns (they hold nothing a page reads).
-- ===========================================================================

alter table public.campaign_confirmations add column if not exists idem text;
alter table public.campaign_confirmations add column if not exists snapshot jsonb;
create unique index if not exists campaign_conf_idem
  on public.campaign_confirmations(campaign_id, idem) where idem is not null;
alter table public.client_requests add column if not exists idem text;
create unique index if not exists client_requests_idem
  on public.client_requests(client_id, idem) where idem is not null;

create or replace function public.confirm_selection_with(
  p_token text, p_person text, p_passcode text, p_selected uuid[], p_backup uuid[],
  p_seen jsonb, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c      campaigns%rowtype;
  v_sel  uuid[];
  v_bak  uuid[];
  v_all  uuid[];
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
  v_now  jsonb;
  v_snap jsonb;
  n      integer;
begin
  select * into c from campaigns where access_token = p_token for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  -- The same press again: the first answer stands and nothing is filed twice.
  if v_idem is not null and exists (select 1 from campaign_confirmations k
                                     where k.campaign_id = c.id and k.idem = v_idem) then
    return jsonb_build_object('ok', true, 'again', true);
  end if;

  v_sel := array(select distinct x from unnest(coalesce(p_selected, '{}'::uuid[])) x where x is not null);
  v_bak := case when coalesce(c.backups_open, false)
                then array(select distinct x from unnest(coalesce(p_backup, '{}'::uuid[])) x
                            where x is not null and not (x = any (v_sel)))
                else '{}'::uuid[] end;
  v_all := v_sel || v_bak;
  n := cardinality(v_sel);

  if c.selection_closed_at is not null and not (coalesce(c.backups_open, false) and n = 0) then
    return jsonb_build_object('error', 'closed');
  end if;
  if cardinality(v_all) = 0 then return jsonb_build_object('error', 'empty'); end if;
  if n > c.slots then return jsonb_build_object('error', 'over-slots', 'slots', c.slots); end if;
  -- Every creator named is still on the campaign and open to choose.
  if (select count(*) from campaign_options o
       where o.id = any (v_all) and o.campaign_id = c.id
         and o.state in ('option', 'shortlisted', 'backup')) <> cardinality(v_all) then
    return jsonb_build_object('error', 'stale');
  end if;
  -- The prices the client read are the prices now.
  select jsonb_object_agg(o.id::text, o.rate) into v_now
    from campaign_options o where o.id = any (v_all);
  if exists (select 1 from campaign_options o
              where o.id = any (v_all)
                and coalesce(p_seen -> (o.id::text), 'null'::jsonb)
                    is distinct from coalesce(to_jsonb(o.rate), 'null'::jsonb)) then
    return jsonb_build_object('error', 'prices', 'rates', v_now);
  end if;

  update campaign_options set state = 'option'
   where campaign_id = c.id and state in ('shortlisted', 'backup');
  if n > 0 then
    update campaign_options set state = 'shortlisted'
     where campaign_id = c.id and id = any (v_sel) and state = 'option';
  end if;
  if cardinality(v_bak) > 0 then
    update campaign_options set state = 'backup'
     where campaign_id = c.id and id = any (v_bak) and state = 'option';
  end if;

  select jsonb_agg(jsonb_build_object('id', o.id, 'creator', cr.name, 'rate', o.rate, 'as', o.state)
                   order by o.position, o.added_at)
    into v_snap
    from campaign_options o join creators cr on cr.id = o.creator_id
   where o.id = any (v_all);
  insert into campaign_confirmations (campaign_id, kind, person, source, idem, snapshot)
  values (c.id, 'client', trim(p_person), 'portal', v_idem, coalesce(v_snap, '[]'::jsonb));

  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          case when n > 0 then n::text || ' creator' || case when n = 1 then '' else 's' end || ' confirmed'
               else cardinality(v_bak)::text || ' backup' || case when cardinality(v_bak) = 1 then '' else 's' end || ' confirmed' end);

  return jsonb_build_object('ok', true, 'selected', n);
end $$;

revoke all on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) from public;
grant execute on function public.confirm_selection_with(text, text, text, uuid[], uuid[], jsonb, text) to anon, authenticated;

create or replace function public.confirm_selection(
  p_token text, p_person text, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if c.passcode is not null and c.passcode <> ''
     and (p_passcode is null or p_passcode <> c.passcode) then
    return jsonb_build_object('error', 'passcode');
  end if;
  if coalesce(trim(p_person), '') = '' then
    return jsonb_build_object('error', 'name-required');
  end if;
  if c.selection_closed_at is not null and not coalesce(c.backups_open, false) then
    return jsonb_build_object('error', 'closed');
  end if;
  -- Nothing saved is nothing to confirm (a save refused under the page).
  if not exists (select 1 from campaign_options o
                  where o.campaign_id = c.id
                    and o.state = case when c.selection_closed_at is not null
                                       then 'backup' else 'shortlisted' end) then
    return jsonb_build_object('error', 'empty');
  end if;

  insert into campaign_confirmations (campaign_id, kind, person, source)
  values (c.id, 'client', trim(p_person), 'portal');

  insert into public.activity_log (actor, action, subject, detail)
  values (trim(p_person), 'campaign.confirmed', c.title,
          (select count(*)::text || ' creator' || case when count(*) = 1 then '' else 's' end
             from campaign_options
            where campaign_id = c.id and state = 'shortlisted') || ' confirmed');

  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.confirm_selection(text, text, text) from public;
grant execute on function public.confirm_selection(text, text, text) to anon, authenticated;

create or replace function public.campaign_confirm_creators(
  p_campaign uuid, p_options uuid[], p_person text, p_source text, p_idem text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  c        public.campaigns%rowtype;
  v_ids    uuid[] := array(select distinct x from unnest(coalesce(p_options, '{}'::uuid[])) x where x is not null);
  v_idem   text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
  v_person text;
  v_source text := case when p_source in ('portal', 'whatsapp', 'email', 'call') then p_source else 'whatsapp' end;
  v_ok     integer;
  v_snap   jsonb;
begin
  if not public.allowed('campaigns.campaigns', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into c from public.campaigns where id = p_campaign for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_scope_ok('campaign', c.id, 'work') then
    return jsonb_build_object('error', 'client-scope');
  end if;
  if v_idem is not null and exists (select 1 from public.campaign_confirmations k
                                     where k.campaign_id = c.id and k.idem = v_idem) then
    return jsonb_build_object('ok', true, 'again', true);
  end if;
  if cardinality(v_ids) = 0 then return jsonb_build_object('error', 'empty'); end if;
  select count(*) into v_ok from public.campaign_options o
   where o.id = any (v_ids) and o.campaign_id = c.id and o.state = 'shortlisted';
  if v_ok <> cardinality(v_ids) then
    return jsonb_build_object('error', 'stale', 'count', cardinality(v_ids) - v_ok);
  end if;
  v_person := coalesce(nullif(btrim(coalesce(p_person, '')), ''), me.name);

  select jsonb_agg(jsonb_build_object('id', o.id, 'creator', cr.name, 'rate', o.rate, 'as', o.state)
                   order by o.position, o.added_at)
    into v_snap
    from public.campaign_options o join public.creators cr on cr.id = o.creator_id
   where o.id = any (v_ids);
  insert into public.campaign_confirmations (campaign_id, kind, person, source, idem, snapshot)
  values (c.id, case when v_source = 'portal' then 'client' else 'keyed_in' end,
          v_person, v_source, v_idem, coalesce(v_snap, '[]'::jsonb));
  update public.campaign_options
     set state = 'confirmed', confirmed_at = now(), confirmed_by = v_person
   where id = any (v_ids);
  update public.campaigns set state = 'production' where id = c.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'campaign.locked', c.title,
          cardinality(v_ids)::text || ' creators · ' || v_person);

  return jsonb_build_object('ok', true, 'confirmed', cardinality(v_ids));
end $$;
revoke all on function public.campaign_confirm_creators(uuid, uuid[], text, text, text) from public, anon;
grant execute on function public.campaign_confirm_creators(uuid, uuid[], text, text, text) to authenticated;

create or replace function public.portal_request_once(
  p_client uuid, p_kind text, p_service uuid, p_note text, p_idem text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  who    text := lower(auth.jwt() ->> 'email');
  cl     public.clients%rowtype;
  me     public.client_contacts%rowtype;
  sv     public.client_services%rowtype;
  rid    uuid;
  v_idem text := left(nullif(btrim(coalesce(p_idem, '')), ''), 64);
begin
  if who is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  -- The same request again (a reply lost on the way): the one already filed.
  if v_idem is not null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    if rid is not null then return jsonb_build_object('ok', true, 'id', rid, 'again', true); end if;
  end if;
  if p_kind not in ('upgrade', 'downgrade', 'cancel', 'details') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  select * into cl from public.clients where id = p_client;
  select * into me from public.client_contacts
    where client_id = p_client and portal_access and archived_at is null and lower(email) = who
    order by is_primary desc limit 1;
  if p_kind <> 'details' then
    select * into sv from public.client_services
      where id = p_service and client_id = p_client and archived_at is null and state = 'confirmed';
    if sv.id is null then return jsonb_build_object('error', 'not-found'); end if;
  end if;
  if p_kind <> 'cancel' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('error', 'note-required');
  end if;
  insert into public.client_requests (client_id, contact_id, contact_name, kind, service_id, service_label, note, idem)
  values (p_client, me.id, me.name, p_kind, sv.id, sv.label, nullif(btrim(p_note), ''), v_idem)
  on conflict (client_id, idem) where idem is not null do nothing
  returning id into rid;
  if rid is null then
    select r.id into rid from public.client_requests r
     where r.client_id = p_client and r.idem = v_idem;
    return jsonb_build_object('ok', true, 'id', rid, 'again', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'request.raised', cl.name, p_kind || coalesce(' · ' || sv.label, ''));
  return jsonb_build_object('ok', true, 'id', rid);
end $$;

create or replace function public.portal_request(
  p_client uuid, p_kind text, p_service uuid default null, p_note text default null)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.portal_request_once(p_client, p_kind, p_service, p_note, null)
$$;

revoke all on function public.portal_request_once(uuid, text, uuid, text, text) from public, anon;
grant execute on function public.portal_request_once(uuid, text, uuid, text, text) to authenticated;
revoke all on function public.portal_request(uuid, text, uuid, text) from public, anon;
grant execute on function public.portal_request(uuid, text, uuid, text) to authenticated;

-- END OF CONFIRM ONCE ----------------------------------------------------------

select public.functions_tidy();
