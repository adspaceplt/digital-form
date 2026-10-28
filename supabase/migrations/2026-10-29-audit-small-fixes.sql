-- ===========================================================================
-- AUDIT SMALL FIXES — a draft ruled on only while with the client, a
-- representative's WhatsApp only while their card is on, an email cut off
-- mid-send no longer Sending (2026-10-29)
-- ===========================================================================
-- WHY (the whole-repo audit of 2026-10-29):
--   2. `review_draft` took a decision on a draft at Changes requested too,
--      without holding the booking: a selection page left open from before
--      the client asked for changes could approve the unrevised draft, and
--      the creator was told it was cleared to post.
--   4. An email whose function stopped between its filing and its close
--      read Sending for ever (the supplier's and the overdue reminder's).
--   7. The quotation website named a colleague's WhatsApp while their
--      namecard was off.
--
-- WHAT IT CHANGES
--   * `review_draft` (restated whole from its last definition): Reviewing
--     alone, the booking read `for update`.
--   * `quote_website_read` (restated whole from QUOTATION WEBSITE GUARDS):
--     the representative's WhatsApp only with `card_on` and `card_mobile`.
--   * `mail_sweep()` (the owner's alone) marks an email still Sending ten
--     minutes after it was filed as Not confirmed (`unknown`), which a
--     colleague reads as check before sending again; pg_cron `mail-sweep`
--     every fifteen minutes.
--
-- ORDER: this file (connector). No page changes with it. Safe to run twice.
--
-- ROLLBACK: review_draft and quote_website_read from their last definitions
-- before this banner; then in the SQL Editor:
--   select cron.unschedule(jobid) from cron.job where jobname = 'mail-sweep';
--   drop function if exists public.mail_sweep();
-- ===========================================================================

create or replace function public.review_draft(
  p_token text, p_option uuid, p_decision text, p_note text default null,
  p_reviewer text default null, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c campaigns%rowtype;
  o campaign_options%rowtype;
  n integer;
begin
  select * into c from campaigns where access_token = p_token;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  -- A past client's link acts on nothing, as it reads nothing (second
  -- audit, item 7): answered as a key nobody knows, before the passcode.
  if exists (select 1 from public.clients cl where cl.id = c.client_id and cl.stage = 'past') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4).
  case public.link_passcode('selection', c.access_token, c.passcode, p_passcode)
    when 'locked' then return public.link_locked('selection', c.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode');
    else null;
  end case;
  if p_decision not in ('approved', 'changes') then
    return jsonb_build_object('error', 'bad-decision');
  end if;
  -- What a client types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_reviewer, '')) > 80 or length(coalesce(p_note, '')) > 2000 then
    return jsonb_build_object('error', 'too-long');
  end if;

  -- The booking is held while it is ruled on, so two decisions at once
  -- are taken one after the other (audit 2026-10-29, 2).
  select * into o from campaign_options
   where id = p_option and campaign_id = c.id
   for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;

  /* Only a draft that is with the client can be ruled on: Reviewing, as
     the selection page draws the decision. A draft already sent back for
     changes is with the creator, so a page left open from before can no
     longer approve it unrevised (audit 2026-10-29, 2; the team's send-back
     too, audit B, 2026-10-17). */
  if o.state <> 'reviewing' then
    return jsonb_build_object('error', 'not-reviewing');
  end if;

  n := coalesce(o.revision_round, 0);

  insert into option_reviews (option_id, round, decision, note, reviewer)
  values (p_option, greatest(n, 1), p_decision, nullif(trim(coalesce(p_note, '')), ''), p_reviewer);

  if p_decision = 'approved' then
    update campaign_options set state = 'scheduled' where id = p_option;
  else
    update campaign_options
       set state = 'changes', revision_round = greatest(n, 1) + 1,
           changes_by = 'client'
     where id = p_option;
  end if;

  /* The client's decision is the one event on a campaign that nobody on the
     team witnesses, and it was the only one the activity record never held:
     a draft went to Reviewing and appeared as Scheduled with nothing in
     between saying who had said yes. The reviewer's own name is the actor,
     because a person decided it. */
  insert into activity_log (actor, action, subject, detail)
  select coalesce(nullif(trim(coalesce(p_reviewer, '')), ''), 'Client'),
         'campaign.review', c.title,
         cr.name || ' · ' ||
         case when p_decision = 'approved' then 'Approved' else 'Changes requested' end ||
         coalesce(': ' || nullif(trim(coalesce(p_note, '')), ''), '')
    from creators cr where cr.id = o.creator_id;

  return jsonb_build_object('ok', true, 'decision', p_decision);
end $$;
revoke all on function public.review_draft(text, uuid, text, text, text, text) from public;
grant execute on function public.review_draft(text, uuid, text, text, text, text) to anon, authenticated;

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
  v_own boolean;
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
  -- The client's details form is offered only on the quotation that made
  -- the lead: a later website quotation that matched an existing lead's
  -- email and number never opens that lead's form (2026-10-26, audit).
  v_own := c.created_at >= w.issued_at - interval '1 minute'
           and not exists (select 1 from public.quotations o
                            where o.client_id = c.id and o.issued_at < w.issued_at and o.id <> w.id);
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
  elsif w.status = 'not_proceeding' or q.status = 'not_proceeding' then
    v_stage := 'closed';
  elsif q.valid_until < v_today then
    v_stage := 'expired';
  elsif not v_billed and v_own then
    select * into f from public.client_detail_forms x
     where x.client_id = c.id and x.voided_at is null
     order by x.created_at desc limit 1;
    if f.id is not null and f.submitted_at is not null and f.used_at is null then v_stage := 'billing_sent';
    elsif f.id is not null and f.submitted_at is null and f.expires_at > now() then v_stage := 'billing';
    end if;
  elsif v_billed and w.proceed_at is not null then
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
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

create or replace function public.mail_sweep()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.invoice_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_sweep() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: an email cut off mid-send reads Sending until swept by hand.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'mail-sweep';
  perform cron.schedule('mail-sweep', '*/15 * * * *', 'select public.mail_sweep()');
end $$;

-- END OF AUDIT SMALL FIXES --------------------------------------------------

select public.functions_tidy();
