-- ===========================================================================
-- QUOTATION DRAFTS (2026-11-25)
-- ===========================================================================
-- WHY: the user, 2026-11-25: a quote part-built in Build quote was lost
-- when the sheet closed before Create. What was entered is now kept as a
-- draft against the client and the colleague, in the database so it
-- follows the colleague to another device.
--
-- WHAT CHANGED
--   * `quotation_drafts`: one row per client per colleague (`client_id`,
--     `member_id`, unique together), the builder's selection as entered
--     (`selection`: type, brands, lines, extras, term), the Rate Card
--     version it was priced on (`card`) and when it was saved. No number
--     and no PDF: a draft is never a quotation. RLS on, no policy, no
--     grant: read and written only through the three functions below,
--     each the caller's own row, as `rail_orders` is.
--   * `quotation_draft_read(p_client)`, `quotation_draft_save(p_client,
--     p_sel, p_card)` and `quotation_draft_discard(p_client)`: the caller a
--     colleague (`denied`), at Work on Clients' Quotations
--     (`clients.quotes`, as `quotation_create` asks; `denied`), and the
--     client within their scope (`client-scope`). A selection that is no
--     object is `bad-request`; one over 200 KB, or a version over 40
--     characters, `too-long`. A personal working copy, so nothing is filed
--     in the Activity record.
--   * `quotation_drafts_clear` (trigger on `quotations`, after insert): a
--     console quotation made clears its maker's draft on that client, so
--     Create clears it whichever page made it.
--   * Discarded or cleared, a draft's selection and version are emptied
--     (`selection` null): nothing entered is kept, and the empty row is
--     filled again by the next save. A client deleted, or a colleague,
--     takes their drafts with them.
--
-- ORDER: this file (connector), then the pages (Pages deploy). An old tab
-- calls none of the functions; a new page before this file reads the
-- draft functions as missing and builds without a draft. Safe to run twice.
-- ROLLBACK: pages first (Build quote stops offering a draft), then
--   drop trigger if exists quotation_drafts_clear on public.quotations;
--   drop function if exists public.quotation_drafts_clear();
--   drop function if exists public.quotation_draft_discard(uuid);
--   drop function if exists public.quotation_draft_save(uuid, jsonb, text);
--   drop function if exists public.quotation_draft_read(uuid);
--   drop table if exists public.quotation_drafts;
-- ===========================================================================

create table if not exists public.quotation_drafts (
  id         uuid primary key default gen_random_uuid(),
  client_id  uuid not null references public.clients(id) on delete cascade,
  member_id  uuid not null references public.team_members(id) on delete cascade,
  selection  jsonb,
  card       text,
  saved_at   timestamptz not null default now(),
  unique (client_id, member_id)
);
alter table public.quotation_drafts enable row level security;
revoke all on public.quotation_drafts from public, anon, authenticated;

create or replace function public.quotation_draft_read(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_d public.quotation_drafts;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  select * into v_d from public.quotation_drafts d where d.client_id = p_client and d.member_id = me.id;
  if v_d.id is null or v_d.selection is null then return jsonb_build_object('draft', null); end if;
  return jsonb_build_object('draft', jsonb_build_object('selection', v_d.selection, 'card', v_d.card, 'saved_at', v_d.saved_at));
end $$;
grant execute on function public.quotation_draft_read(uuid) to authenticated;

create or replace function public.quotation_draft_save(p_client uuid, p_sel jsonb, p_card text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_at timestamptz := now();
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_sel is null or jsonb_typeof(p_sel) <> 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  if octet_length(p_sel::text) > 200000 or length(coalesce(p_card, '')) > 40 then return jsonb_build_object('error', 'too-long'); end if;
  insert into public.quotation_drafts (client_id, member_id, selection, card, saved_at)
  values (p_client, me.id, p_sel, nullif(p_card, ''), v_at)
  on conflict (client_id, member_id) do update set selection = excluded.selection, card = excluded.card, saved_at = excluded.saved_at;
  return jsonb_build_object('saved_at', v_at);
end $$;
grant execute on function public.quotation_draft_save(uuid, jsonb, text) to authenticated;

create or replace function public.quotation_draft_discard(p_client uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_n int;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  update public.quotation_drafts d set selection = null, card = null, saved_at = now()
   where d.client_id = p_client and d.member_id = me.id and d.selection is not null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'removed', v_n);
end $$;
grant execute on function public.quotation_draft_discard(uuid) to authenticated;

create or replace function public.quotation_drafts_clear()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
begin
  if new.source = 'console' and me.id is not null then
    update public.quotation_drafts d set selection = null, card = null, saved_at = now()
     where d.client_id = new.client_id and d.member_id = me.id and d.selection is not null;
  end if;
  return new;
end $$;
revoke all on function public.quotation_drafts_clear() from public, anon, authenticated;

create or replace trigger quotation_drafts_clear
  after insert on public.quotations
  for each row execute function public.quotation_drafts_clear();

-- END OF QUOTATION DRAFTS ------------------------------------------------------

select public.functions_tidy();
