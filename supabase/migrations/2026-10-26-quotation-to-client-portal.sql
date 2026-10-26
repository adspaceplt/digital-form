-- ===========================================================================
-- QUOTATION TO CLIENT PORTAL — billing before the Letter of Offer, and the
-- prospect's one link followed to the client portal (2026-10-26)
-- ===========================================================================
-- WHY (the user, 2026-10-26, after the lifecycle review): "letter of offer
-- needs billing details to issue, so billing should be before LoO", and the
-- prospect's quotation link stopped at the letter: nothing led a new client
-- to the client portal. The review also found the link said "Letter of Offer
-- issued" the moment Issue Letter of Offer made the lines, before any letter.
--
-- WHAT IT CHANGES
--   * Trigger `client_documents_billing` refuses a Letter of Offer
--     (`client_documents` kind `offer`) for a client whose registered name,
--     BRN or billing address is empty or who has no billing contact
--     (chosen, else a live main contact), as `clients_active_billing` holds
--     Active (`needs-billing`). A letter already issued keeps its place.
--   * `quote_website_read` answers one `stage` for the page to draw:
--       quote        the quotation, nothing more yet
--       ready        the prospect said they are ready to proceed
--       billing      billing details are needed and a details form is open
--                    (`details_key`, the client's own /details/ link)
--       billing_sent the details form came back, the letter not issued yet
--       letter       a live Letter of Offer holds the quotation's lines
--       signed       its signed copy is in, not yet confirmed and Active
--       welcome      the letter is verified and the client is Active;
--                    `portal` says whether the prospect's address holds
--                    portal access (the page links to /client/ sign-in,
--                    never signs anybody in)
--       expired      past its validity with no letter
--     A letter counts only while it stands (not void, not replaced): lines
--     made by Issue Letter of Offer with no letter issued count for nothing.
--     `status` keeps answering `offer` for a page served before this file.
--
-- ORDER: this file (connector), then the pages. A page served before it
-- reads `status` as before; one served after it on the old function reads
-- no `stage` and draws as `quote`/`ready`.
--
-- ROLLBACK: pages first; then drop trigger client_documents_billing and its
-- function, and restore quote_website_read from QUOTATION WEBSITE FOLLOW-UP.
-- ===========================================================================

create or replace function public.client_documents_billing()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  c public.clients;
begin
  if new.kind is distinct from 'offer' then return new; end if;
  select * into c from public.clients where id = new.client_id;
  if c.id is null then return new; end if;
  if coalesce(btrim(c.legal_name), '') = ''
     or coalesce(btrim(c.company_no), '') = ''
     or coalesce(btrim(c.billing_address), '') = ''
     or not exists (select 1 from public.client_contacts k
                     where k.client_id = c.id and k.archived_at is null
                       and (k.id = c.bill_contact_id or k.is_primary)) then
    raise exception 'needs-billing';
  end if;
  return new;
end $$;
revoke all on function public.client_documents_billing() from public, anon, authenticated;
create or replace trigger client_documents_billing before insert on public.client_documents
  for each row execute function public.client_documents_billing();

create or replace function public.quote_website_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  c  public.clients;
  m  public.team_members;
  d  public.client_documents;
  f  public.client_detail_forms;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_stage text;
  v_portal boolean := false;
  v_billed boolean;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x
   where x.access_key = p_key and x.source = 'website' and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  select * into c from public.clients x where x.id = w.client_id;
  if nullif(btrim(coalesce(c.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = c.owner
     limit 1;
  end if;
  -- The letter that stands on the quotation's lines, the latest first.
  select dd.* into d from public.client_documents dd
   where dd.kind = 'offer' and dd.voided_at is null and dd.superseded_by is null
     and exists (select 1 from public.client_document_services ds
                   join public.client_services s on s.id = ds.service_id
                  where ds.document_id = dd.id and s.quotation_id = q.id)
   order by dd.created_at desc limit 1;
  v_billed := coalesce(btrim(c.legal_name), '') <> '' and coalesce(btrim(c.company_no), '') <> ''
              and coalesce(btrim(c.billing_address), '') <> '';

  if d.id is not null then
    if d.verified_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(w.contact->>'email', '')))) into v_portal;
    elsif d.signed_at is not null then v_stage := 'signed';
    else v_stage := 'letter';
    end if;
  elsif q.valid_until < v_today then
    v_stage := 'expired';
  elsif not v_billed then
    select * into f from public.client_detail_forms x
     where x.client_id = c.id and x.voided_at is null
     order by x.created_at desc limit 1;
    if f.id is not null and f.submitted_at is not null and f.used_at is null then v_stage := 'billing_sent';
    elsif f.id is not null and f.submitted_at is null and f.expires_at > now() then v_stage := 'billing';
    end if;
  elsif w.proceed_at is not null then
    v_stage := 'billing_sent';
  end if;
  if v_stage is null then
    v_stage := case when w.proceed_at is not null then 'ready' else 'quote' end;
  end if;

  return jsonb_build_object(
    'ref', q.ref, 'first_ref', w.ref, 'revised', q.id <> w.id,
    'brand', coalesce(w.contact->>'brand', w.brand), 'version', q.version,
    'issued_at', q.issued_at, 'valid_until', q.valid_until, 'lines', q.lines, 'totals', q.totals,
    'selection', w.selection, 'attention', w.contact->>'name',
    'stage', v_stage,
    'status', case when d.id is not null then 'offer' else q.status end,
    'details_key', case when v_stage = 'billing' then f.access_key end,
    'portal', v_portal,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

-- END OF QUOTATION TO CLIENT PORTAL -------------------------------------------

select public.functions_tidy();
