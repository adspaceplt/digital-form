-- ===========================================================================
-- CREATOR PAYMENTS SHEET — a creator's payment details, once approved, are
-- added as a row of the finance team's Google Sheet (2026-11-09, Creator
-- R4). Safe to run twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the user, 2026-11-08: the payments spreadsheet, "full bank
-- number in the sheet", the columns matched by their headers, "dont hardcode
-- anything")
-- * `creator_sheet_settings` (one row; RLS on, no policy, no grant): whether
--   rows are added, the spreadsheet (its ID, read from a link) and the tab
--   (empty: the first). Settings, Clients: Creator payments sheet
--   (`team.settings`; `creator_sheet_get`, `creator_sheet_set`: `bad-sheet`,
--   `bad-tab`; filed `team.changed` under Creator payments sheet).
-- * `creator_sheet_rows` (RLS on, no policy, no grant): a request approved
--   while the sheet is on is queued once (trigger
--   `creator_pay_requests_sheet`), and added by `creator-mail` with the
--   emails (`creator_sheet_claim`, `creator_sheet_done`, the service role's
--   alone), each value under the header that names it; a row refused is
--   tried again at the next wake, five tries at most.
--   `creator_sheet_state(p_creator)` (Creator payment details View) answers
--   each request's row for the console.
-- * pg_cron `creator-mail-drain` also wakes for a row waiting.
-- ===========================================================================

create table if not exists public.creator_sheet_settings (
  id             int primary key default 1 check (id = 1),
  on_send        boolean not null default true,
  spreadsheet_id text check (spreadsheet_id is null or spreadsheet_id ~ '^[A-Za-z0-9_-]{20,100}$'),
  tab            text check (tab is null or length(tab) between 1 and 100),
  updated_at     timestamptz not null default now(),
  updated_by     uuid
);
alter table public.creator_sheet_settings enable row level security;
revoke all on table public.creator_sheet_settings from public, anon, authenticated;
insert into public.creator_sheet_settings (id, on_send, spreadsheet_id)
values (1, true, '1UDXqCkUZQ-cyfB5j7dEvf2p7fmJZeIYZiWL6_byi-HA')
on conflict (id) do nothing;

create table if not exists public.creator_sheet_rows (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null unique references public.creator_pay_requests(id) on delete cascade,
  status      text not null default 'queued' check (status in ('queued', 'sending', 'added', 'failed')),
  tries       int not null default 0,
  error       text,
  created_at  timestamptz not null default now(),
  claimed_at  timestamptz,
  added_at    timestamptz
);
create index if not exists creator_sheet_rows_open_idx on public.creator_sheet_rows (created_at) where status in ('queued', 'failed');
alter table public.creator_sheet_rows enable row level security;
revoke all on table public.creator_sheet_rows from public, anon, authenticated;

/* A request approved while the sheet is on is queued once. A fault never
   fails the approval. */
create or replace function public.creator_pay_requests_sheet()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from 'approved' or old.status = 'approved' then return null; end if;
  begin
    if exists (select 1 from public.creator_sheet_settings s where s.id = 1 and s.on_send and s.spreadsheet_id is not null) then
      insert into public.creator_sheet_rows (request_id) values (new.id) on conflict (request_id) do nothing;
      perform public.creator_mail_kick();
    end if;
  exception when others then
    return null;
  end;
  return null;
end $$;
revoke all on function public.creator_pay_requests_sheet() from public, anon, authenticated;
create or replace trigger creator_pay_requests_sheet after update of status on public.creator_pay_requests
  for each row execute function public.creator_pay_requests_sheet();

create or replace function public.creator_sheet_get()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.ops_granted('team.settings', 'work') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'on', s.on_send, 'spreadsheet_id', s.spreadsheet_id, 'tab', s.tab,
      'updated_at', s.updated_at, 'updated_by', m.name,
      'added', (select count(*) from public.creator_sheet_rows r where r.status = 'added'),
      'waiting', (select count(*) from public.creator_sheet_rows r where r.status in ('queued', 'sending') or (r.status = 'failed' and r.tries < 5)),
      'failed', (select count(*) from public.creator_sheet_rows r where r.status = 'failed' and r.tries >= 5),
      'last_error', (select r.error from public.creator_sheet_rows r where r.status = 'failed' order by r.claimed_at desc nulls last limit 1)) end
    from public.creator_sheet_settings s left join public.team_members m on m.id = s.updated_by
   where s.id = 1
$$;
revoke all on function public.creator_sheet_get() from public, anon;
grant execute on function public.creator_sheet_get() to authenticated;

/* The sheet set from Settings: a Google Sheets link or its ID, and a tab. */
create or replace function public.creator_sheet_set(p_on boolean, p_sheet text, p_tab text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.creator_sheet_settings;
  v_id text := nullif(btrim(coalesce(p_sheet, '')), '');
  v_tab text := nullif(btrim(coalesce(p_tab, '')), '');
  v_moved text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_id ~ '/spreadsheets/d/' then v_id := substring(v_id from '/spreadsheets/d/([A-Za-z0-9_-]+)'); end if;
  if v_id is not null and v_id !~ '^[A-Za-z0-9_-]{20,100}$' then return jsonb_build_object('error', 'bad-sheet'); end if;
  if coalesce(p_on, false) and v_id is null then return jsonb_build_object('error', 'bad-sheet'); end if;
  if v_tab is not null and length(v_tab) > 100 then return jsonb_build_object('error', 'bad-tab'); end if;
  select * into s from public.creator_sheet_settings where id = 1 for update;
  if s.on_send is distinct from coalesce(p_on, false) then
    v_moved := v_moved || ('Add rows: ' || case when s.on_send then 'On → Off' else 'Off → On' end);
  end if;
  if s.spreadsheet_id is distinct from v_id then v_moved := v_moved || 'Google Sheets link changed'::text; end if;
  if s.tab is distinct from v_tab then
    v_moved := v_moved || ('Tab: ' || coalesce(s.tab, 'First tab') || ' → ' || coalesce(v_tab, 'First tab'));
  end if;
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.creator_sheet_settings set on_send = coalesce(p_on, false), spreadsheet_id = v_id, tab = v_tab,
    updated_at = now(), updated_by = me.id where id = 1;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Creator payments sheet', array_to_string(v_moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_sheet_set(boolean, text, text) from public, anon;
grant execute on function public.creator_sheet_set(boolean, text, text) to authenticated;

/* Each request's row on the sheet, for the console. */
create or replace function public.creator_sheet_state(p_creator uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null or not public.allowed('campaigns.creators', 'view') then jsonb_build_object('error', 'denied')
    else jsonb_build_object('ok', true, 'rows', coalesce((select jsonb_agg(jsonb_build_object('request', r.id, 'ref', r.ref,
      'status', case when s.status = 'failed' and s.tries < 5 then 'queued' else s.status end, 'added_at', s.added_at))
      from public.creator_pay_requests r join public.creator_sheet_rows s on s.request_id = r.id
     where r.creator_id = p_creator), '[]'::jsonb)) end
$$;
revoke all on function public.creator_sheet_state(uuid) from public, anon;
grant execute on function public.creator_sheet_state(uuid) to authenticated;

/* The sender's own: the rows waiting, each with the request's values whole,
   the creator, who approved it and the sheet. */
create or replace function public.creator_sheet_claim(p_n int default 5)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v jsonb;
begin
  with c as (
    update public.creator_sheet_rows x set status = 'sending', claimed_at = now(), tries = x.tries + 1
     where x.id in (select y.id from public.creator_sheet_rows y
                     where y.status = 'queued' or (y.status = 'failed' and y.tries < 5)
                     order by y.created_at limit least(greatest(coalesce(p_n, 5), 1), 20) for update skip locked)
    returning x.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'values', jsonb_build_object(
      'creator_id', k.creator_code, 'creator_name', k.name, 'reference', r.ref,
      'billing_as', case r.bill_kind when 'nric' then 'Individual (NRIC)' when 'passport' then 'Individual (passport)' else 'Company' end,
      'id_no', r.id_no, 'legal_name', r.legal_name, 'tin', r.tin, 'address', r.address, 'currency', r.currency,
      'method', public.creator_pay_method(r.method, null), 'bank', r.bank, 'account', r.account, 'payee', r.payee,
      'email', r.email, 'whatsapp', r.whatsapp,
      'submitted', to_char(r.created_at at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM-DD HH24:MI'),
      'approved', to_char(r.decided_at at time zone 'Asia/Kuala_Lumpur', 'YYYY-MM-DD HH24:MI'),
      'approved_by', m.name))), '[]'::jsonb)
    into v
    from c join public.creator_pay_requests r on r.id = c.request_id
    join public.creators k on k.id = r.creator_id
    left join public.team_members m on m.id = r.decided_by;
  return jsonb_build_object('rows', v,
    'sheet', (select jsonb_build_object('on', s.on_send, 'spreadsheet_id', s.spreadsheet_id, 'tab', s.tab)
                from public.creator_sheet_settings s where s.id = 1));
end $$;
revoke all on function public.creator_sheet_claim(int) from public, anon, authenticated;
grant execute on function public.creator_sheet_claim(int) to service_role;

create or replace function public.creator_sheet_done(p_id uuid, p_ok boolean, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  update public.creator_sheet_rows x set status = case when p_ok then 'added' else 'failed' end,
    error = case when p_ok then null else left(nullif(p_error, ''), 480) end,
    added_at = case when p_ok then now() end
   where x.id = p_id and x.status = 'sending';
  return jsonb_build_object('ok', found);
end $$;
revoke all on function public.creator_sheet_done(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.creator_sheet_done(uuid, boolean, text) to service_role;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: creator emails and sheet rows are woken by their writes alone until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'creator-mail-drain';
  perform cron.schedule('creator-mail-drain', '*/5 * * * *',
    'select public.creator_mail_kick() where exists (select 1 from public.creator_emails e where e.status = ''queued'') ' ||
    'or exists (select 1 from public.creator_sheet_rows r where r.status = ''queued'' or (r.status = ''failed'' and r.tries < 5))');
end $$;

-- Rollback: drop the trigger creator_pay_requests_sheet and the creator_sheet_*
-- functions and tables, and run CREATOR PAYMENT DETAILS' cron block again.

-- END OF CREATOR PAYMENTS SHEET -----------------------------------------------

select public.functions_tidy();
