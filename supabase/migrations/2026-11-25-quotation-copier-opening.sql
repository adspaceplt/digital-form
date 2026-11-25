-- ===========================================================================
-- QUOTATION COPIER'S OPENING (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25 (choice A). QUOTATION SENT WHEN IT REACHES THE
-- CLIENT stamps a team's quotation sent at its first opening by anyone but
-- a signed-in colleague. The live openings of ADP/QT2611-C01 and -B01 came
-- four seconds after Copy link, from the copier's own iPhone: the console
-- on the Home Screen keeps its sign-in apart from Safari, so a colleague
-- opening the link they copied read as the client.
--
-- WHAT CHANGES
--   * `quotation_link_copies` (quotation, address, when): where a colleague
--     copied a quotation's link, one row an address, its time renewed at
--     every copy. Row level security on, no policy, no grant: no page reads
--     it. The address is the caller's as `request_ip()` reads it (the
--     gateway's, never a header a caller sets). Cleared 30 days after the
--     copy by `privacy_retention` (QUOTATION COPIER'S ADDRESS KEPT 30 DAYS).
--   * `quotation_link`: records the copier's address at every press (the
--     console asks it at every Copy link, the link already made or not).
--   * `quote_opened`: an opening from an address a colleague copied that
--     quotation's link from in the last 30 days neither stamps it sent nor
--     moves the stage; it is still filed, `{ref} · Opened by the team`.
--   Each restated from its last section with those lines alone added.
--
-- ORDER: the pages first (Copy link asks the function at every press),
-- then this file (connector), then QUOTATION COPIER'S ADDRESS KEPT 30 DAYS
-- (SQL Editor: its function holds the connector's stop words). Safe to run
-- twice.
-- ROLLBACK: run `quotation_link` (QUOTATION SIGNING) and `quote_opened`
-- (QUOTATION SENT WHEN IT REACHES THE CLIENT) again; the table is then
-- read by nothing.
-- ===========================================================================

-- QUOTATION COPIER'S OPENING ---------------------------------------------------

create table if not exists public.quotation_link_copies (
  id           uuid primary key default gen_random_uuid(),
  quotation_id uuid not null,
  ip           text,
  at           timestamptz not null default now()
);
create unique index if not exists quotation_link_copies_one on public.quotation_link_copies (quotation_id, ip);
alter table public.quotation_link_copies enable row level security;
revoke all on table public.quotation_link_copies from public, anon, authenticated;

create or replace function public.quotation_link(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_ip text := nullif(public.request_ip(), '');
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.access_key is null then
    update public.quotations set access_key = public.new_link_key() where id = q.id returning * into q;
  end if;
  -- Where the link was copied from, so the colleague's own opening is never
  -- taken for the client's (QUOTATION COPIER'S OPENING, 2026-11-25). Kept
  -- 30 days (privacy_retention), never read by a page.
  if v_ip is not null then
    insert into public.quotation_link_copies (quotation_id, ip, at) values (q.id, v_ip, now())
    on conflict (quotation_id, ip) do update set at = excluded.at;
  end if;
  return jsonb_build_object('ok', true, 'key', q.access_key);
end $$;
revoke all on function public.quotation_link(uuid) from public, anon;
grant execute on function public.quotation_link(uuid) to authenticated;

create or replace function public.quote_opened(p_key text, p_device text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w public.quotations;
  q public.quotations;
  v_ip  text := nullif(public.request_ip(), '');
  v_dev text := public.seal_device(p_device);
  v_team boolean := false;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  if public.is_team() then return jsonb_build_object('ok', true, 'kept', false); end if;
  select * into w from public.quotations x where x.access_key = p_key and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if q.id is null or (q.source = 'website' and q.released_at is null) then
    return jsonb_build_object('ok', true, 'kept', false);
  end if;
  -- An opening from where a colleague copied this quotation's link in the
  -- last 30 days is the team's own, never the client's.
  v_team := v_ip is not null and exists (select 1 from public.quotation_link_copies c
              where c.quotation_id in (w.id, q.id) and c.ip = v_ip and c.at > now() - interval '30 days');
  -- A team's quotation reaches the client the first time its link is
  -- opened by anyone but a colleague: it is sent out then, once.
  if q.source = 'console' and q.sent_out_at is null and not v_team then
    update public.quotations set sent_out_at = now() where id = q.id and sent_out_at is null;
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
  perform public.quote_activity(q, 'quotation.opened', q.ref || case when v_team then ' · Opened by the team' else '' end, q.contact);
  return jsonb_build_object('ok', true, 'kept', true);
end $$;
revoke all on function public.quote_opened(text, text) from public;
grant execute on function public.quote_opened(text, text) to anon, authenticated;

-- END OF QUOTATION COPIER'S OPENING --------------------------------------------

select public.functions_tidy();
