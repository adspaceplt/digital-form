-- ===========================================================================
-- CHECKLIST WRITER — Write with AI on the Pre-Advertising Checklist, and the
-- Meta Campaign Setup table (ver. r1.2-26) (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15: "b yes" to Write with AI on the Pre-Advertising
-- Checklist with the Meta setup table, from the team's client analysis
-- playbook; "the pre-advertising checklist is not AI integrated?")
--
-- WHAT CHANGED
--   * `checklist_template('pre_ads')` is ver. r1.2-26: Meta Campaign Setup
--     gains Campaign Setup, a table of Item, Details, Audience, CTA and
--     A/Spend (kind `table`). A checklist already started keeps the
--     template it began with; the onboarding checklist is unchanged.
--   * `client_checklist_set` takes a table's rows: twelve at most, each only
--     the item's own columns, each cell 400 characters at most (`bad-value`).
--   * Write with AI is its own count (`ai_drafts.purpose` `checklist`):
--     `checklist` (10) a colleague's a day and `checklist_admin` (20) an
--     admin's, settings in `ai_draft_limits`, claimed by
--     `ai_checklist_claim(p_client)` (Clients at Work, the client in scope)
--     and read by `ai_checklist_left()`; `ai_draft_usage` and
--     `ai_draft_set_limit` know them.
--
-- APPLYING: the purpose check (its two `alter table` lines) is run in the SQL
-- Editor; the rest through the connector. Until the check takes `checklist`
-- a claim fails and the page reads "This needs a database update".
--
-- ROLLBACK
--   Run CLIENT CHECKLISTS' checklist_template and client_checklist_set and
--   BRAND ANALYSIS' ai_draft_usage and ai_draft_set_limit again; in the SQL
--   Editor drop ai_checklist_claim and ai_checklist_left, delete the
--   checklist rows from ai_drafts and put the purpose check back to ('draft',
--   'check', 'caption', 'script', 'analysis'). A checklist started on r1.2
--   keeps its table.
--
-- Safe to run twice. Mirrored byte for byte in supabase/schema.sql under the
-- same banner.
-- ===========================================================================

alter table public.ai_drafts drop constraint if exists ai_drafts_purpose;
alter table public.ai_drafts add constraint ai_drafts_purpose check (purpose in ('draft', 'check', 'caption', 'script', 'analysis', 'checklist'));

create or replace function public.checklist_template(p_kind text)
returns jsonb
language sql immutable set search_path = public as $$
  select case p_kind
    when 'onboarding' then '{"kind": "onboarding", "title": "New Client Onboarding Checklist", "version": "r1.1-26", "lead": "Digital account and platform access setup, for internal project team use.", "sections": [{"key": "pre", "title": "Pre-Onboarding", "items": [{"key": "quotation", "kind": "tick", "label": "Quotation", "detail": "Issued to client and approved."}, {"key": "invoice", "kind": "tick", "label": "Invoice", "detail": "First invoice issued per agreed payment terms."}, {"key": "msa", "kind": "tick", "label": "Client MSA / NDA", "detail": "Formalisation completed, where applicable."}, {"key": "po", "kind": "tick", "label": "Client-Side PO", "detail": "Purchase order received from client, if applicable."}, {"key": "first_meeting", "kind": "tick", "label": "First Meeting (PM)", "detail": "Introductory meeting between client and assigned PM scheduled."}]}, {"key": "basics", "title": "Client & Contract Basics", "items": [{"key": "work_order", "kind": "tick", "label": "Work Order", "detail": "Deliverables, channels and retainer scope agreed in writing."}, {"key": "work_group", "kind": "tick", "label": "Client Work Group", "detail": "Authorised members all added into the work WhatsApp group."}, {"key": "pm", "kind": "tick", "label": "PM Assignment", "detail": "Internal point of contact confirmed and introduced to client."}, {"key": "kickoff", "kind": "tick", "label": "Kick-off Call", "detail": "Calendar invite sent, agenda shared in advance."}]}, {"key": "brand", "title": "Brand & Creative Assets", "items": [{"key": "guideline", "kind": "tick", "label": "Brand Guideline", "detail": "Logo usage, colour palette, typography and tone of voice."}, {"key": "logos", "kind": "tick", "label": "Logo Files (AI / EPS / SVG, PNG)", "detail": "Vector and raster formats in all colour variants."}, {"key": "assets", "kind": "tick", "label": "Product / Service Assets", "detail": "Photography, video and any existing creative library."}, {"key": "drive", "kind": "tick", "label": "Shared Drive (View) Access", "detail": "Google Drive / Dropbox folder created and shared both ways."}, {"key": "tone", "kind": "tick", "label": "Tone of Voice Brief", "detail": "Messaging pillars, dos and don''ts, English, Chinese and Malay preferences."}, {"key": "competitors", "kind": "tick", "label": "Competitor List", "detail": "Direct competitors and reference brands for positioning."}]}, {"key": "meta_page", "title": "Meta, Facebook & Instagram Page Access", "note": "Confirm Page and Business Manager access before ad account setup begins.", "platform": "meta", "items": [{"key": "fb_page", "kind": "tick", "label": "Facebook Page", "detail": "Page name and URL verified with client."}, {"key": "partner", "kind": "tick", "label": "ADspace Partner Access", "detail": "Client adds ADspace Business Manager as Partner via Meta Business Suite."}, {"key": "page_role", "kind": "tick", "label": "Page Admin Role", "detail": "ADspace team assigned appropriate Page role, not personal profile access."}, {"key": "ig_pro", "kind": "tick", "label": "Instagram Professional Account", "detail": "Business or Creator account type confirmed."}, {"key": "ig_link", "kind": "tick", "label": "Instagram, Facebook Page Link", "detail": "Verified in Meta Business Suite, Accounts tab."}, {"key": "otp", "kind": "tick", "label": "OTP / 2FA Verification", "detail": "Client''s registered mobile number verified for account security."}, {"key": "biz_verify", "kind": "tick", "label": "Meta Business Verification", "detail": "Business Manager verified where required for scaled ad spend."}]}, {"key": "meta_ads", "title": "Meta Ad Account Setup", "note": "Complete after Page and Business Manager access are confirmed above.", "platform": "meta", "items": [{"key": "ad_account", "kind": "tick", "label": "Ad Account", "detail": "New ad account or existing one linked to ADspace''s Business Manager."}, {"key": "roles", "kind": "tick", "label": "Ad Account Role Assignment", "detail": "Admin, Advertiser or Analyst role set per team member."}, {"key": "payment", "kind": "tick", "label": "Payment Method", "detail": "Card or local billing threshold set up, MYR or SGD billing."}, {"key": "billing", "kind": "tick", "label": "Billing Currency & Address", "detail": "Matches client''s registered business details."}, {"key": "wa_link", "kind": "tick", "label": "WhatsApp Business Link", "detail": "WhatsApp number linked to Page / ad account for click to WhatsApp ads."}, {"key": "leads_tos", "kind": "tick", "label": "Leads Terms of Service", "detail": "Client accepts in Meta Business Suite, Leads Center, before lead ads run."}, {"key": "special_ads", "kind": "tick", "label": "Locality Advertising Authorisation", "detail": "Special ad category authorisation (housing, employment, credit, social issue / electoral / political) applied where applicable."}, {"key": "phone", "kind": "tick", "label": "OTP / Phone Verification", "detail": "Ad account owner''s phone verified."}, {"key": "pixel", "kind": "tick", "label": "Meta Pixel / Conversions API", "detail": "Installed on client''s website, events verified in Events Manager."}, {"key": "domain", "kind": "tick", "label": "Domain Verification", "detail": "Required for iOS14+ event prioritisation and Aggregated Event Measurement."}, {"key": "pre_ads", "kind": "tick", "label": "Pre-Advertising Checklist", "detail": "Completed and signed off before the first campaign goes live."}]}, {"key": "linkedin", "title": "LinkedIn Business Manager", "platform": "linkedin", "items": [{"key": "company_page", "kind": "tick", "label": "LinkedIn Company Page", "detail": "Page name and URL verified with client."}, {"key": "page_admin", "kind": "tick", "label": "Page Admin Access", "detail": "Super Admin or Content Admin role granted on the Company Page."}]}, {"key": "tiktok", "title": "TikTok Business Manager", "platform": "tiktok", "items": [{"key": "account", "kind": "tick", "label": "TikTok Business Account", "detail": "Client''s Business Center account identified."}, {"key": "center", "kind": "tick", "label": "Business Center Access", "detail": "ADspace added as partner / member with correct role assignment."}, {"key": "ads_link", "kind": "tick", "label": "Ads Manager Account Link", "detail": "Ad account linked under the Business Center."}, {"key": "access", "kind": "tick", "label": "Ad Account Access", "detail": "Team members added with appropriate permission level."}, {"key": "payment", "kind": "tick", "label": "Payment Method", "detail": "Billing currency confirmed for MY / SG ad account."}, {"key": "verify", "kind": "tick", "label": "Business / Identity Verification", "detail": "Required for certain ad account types or spend thresholds."}, {"key": "pixel", "kind": "tick", "label": "TikTok Pixel / Events API", "detail": "Installed on website and verified as firing correctly."}]}, {"key": "rednote", "title": "rednote (小红书)", "note": "rednote has limited multi-user support.", "platform": "rednote", "items": [{"key": "enterprise", "kind": "tick", "label": "Enterprise Account (企业号)", "detail": "Registered and active, where applicable."}, {"key": "verify", "kind": "tick", "label": "Business Verification (企业认证)", "detail": "Completed with the correct business licence."}, {"key": "access", "kind": "tick", "label": "Access Arrangement", "detail": "Delegated access or shared login credentials logged securely."}, {"key": "ads", "kind": "tick", "label": "Ad Platform Access (聚光引擎 / 蒲公英)", "detail": "Set up if paid campaigns are in scope."}, {"key": "compliance", "kind": "tick", "label": "Content Compliance Brief", "detail": "Content briefed against XHS Safe Mode guidelines where applicable."}]}, {"key": "douyin", "title": "Douyin (抖音)", "platform": "douyin", "items": [{"key": "access", "kind": "tick", "label": "Access Arrangement", "detail": "Delegated access or shared login credentials logged securely."}]}, {"key": "content", "title": "Content Planning", "items": [{"key": "calendar_access", "kind": "tick", "label": "Content Calendar Access", "detail": "Client added as viewer / commenter for review and sign-off."}, {"key": "pillars", "kind": "tick", "label": "First Month Content Pillars", "detail": "Themes and campaign tie-ins agreed with client (refer to the initial pitch deck)."}, {"key": "calendar_brief", "kind": "tick", "label": "Content Calendar Brief", "detail": "Client walked through ADspace''s standard content calendar."}, {"key": "frequency", "kind": "tick", "label": "Posting Frequency", "detail": "Cadence agreed for each active channel."}, {"key": "approval", "kind": "tick", "label": "Content Approval Workflow", "detail": "Review rounds and turnaround time confirmed."}]}, {"key": "reporting", "title": "Reporting & Access", "items": [{"key": "cadence", "kind": "tick", "label": "Reporting Cadence", "detail": "Quarterly / Monthly / Weekly / Daily format."}, {"key": "credentials", "kind": "tick", "label": "Credentials Register", "detail": "All login credentials logged in the Content Calendar sheet."}, {"key": "handover", "kind": "tick", "label": "Internal Handover", "detail": "Onboarding PM briefs servicing team with full access list."}]}]}'::jsonb
    when 'pre_ads' then '{"kind": "pre_ads", "title": "Pre-Advertising Checklist", "version": "r1.2-26", "lead": "Campaign readiness check completed before ads go live.", "sections": [{"key": "details", "title": "Campaign Details", "items": [{"key": "entity", "kind": "text", "label": "Entity Name", "detail": "", "rows": 1}, {"key": "quotation", "kind": "text", "label": "Quotation Reference", "detail": "", "rows": 1}, {"key": "objective", "kind": "multi", "label": "Main Objective", "choices": ["Awareness", "Leads", "Sales", "Traffic"]}]}, {"key": "meta", "title": "Meta Campaign Setup", "platform": "meta", "items": [{"key": "setup", "kind": "tick", "label": "Ad Account Campaign Setup", "detail": "Campaign, ad set and ad structure built."}, {"key": "plan", "kind": "table", "label": "Campaign Setup", "detail": "One row an ad set: what it is, what it shows, who it reaches, its call to action and its ad spend.", "columns": [["item", "Item"], ["details", "Details"], ["audience", "Audience"], ["cta", "CTA"], ["spend", "A/Spend"]]}]}, {"key": "rednote", "title": "rednote Campaign Setup", "platform": "rednote", "items": [{"key": "billing", "kind": "tick", "label": "rednote Account Billing / Payment", "detail": "Payment method confirmed for 聚光引擎 / 蒲公英 ad spend."}, {"key": "setup", "kind": "tick", "label": "Ad Account Campaign Setup", "detail": "Campaign structure built and named."}]}, {"key": "tiktok", "title": "TikTok Campaign Setup", "platform": "tiktok", "items": [{"key": "setup", "kind": "tick", "label": "Ad Account Campaign Setup", "detail": "Campaign, ad group and ad structure built."}]}, {"key": "targeting", "title": "Targeting Information", "items": [{"key": "age", "kind": "text", "label": "Age Group", "detail": "", "rows": 1}, {"key": "ethnicity", "kind": "text", "label": "Ethnicity", "detail": "", "rows": 1}, {"key": "country", "kind": "multi", "label": "Country", "choices": ["Malaysia (Peninsular)", "Malaysia (Sabah & Sarawak)", "Singapore"]}, {"key": "frequency", "kind": "text", "label": "Ad Frequency", "detail": "", "rows": 1}, {"key": "scheduling", "kind": "text", "label": "Ad Scheduling", "detail": "", "rows": 1}, {"key": "placement", "kind": "text", "label": "Ad Placement", "detail": "", "rows": 1}, {"key": "retargeting", "kind": "multi", "label": "Ad Re-Targeting", "choices": ["Old", "New", "Lookalike"]}]}, {"key": "tracking", "title": "Tracking & Analytics (External)", "items": [{"key": "pixel", "kind": "multi", "label": "Pixel / Analytics Connection", "choices": ["Website", "App", "Landing Page", "External Site"]}, {"key": "pixel_site", "kind": "text", "label": "External Site", "detail": "", "rows": 1}, {"key": "relevance", "kind": "multi", "label": "Tracking Relevance", "choices": ["Page Views", "Purchases", "Contact Leads"]}, {"key": "schedule", "kind": "choice", "label": "Ads Reporting Schedule", "choices": ["Quarterly", "Monthly", "Weekly", "Daily"]}]}, {"key": "competitors", "title": "Competitor Analysis", "note": "List competitor names, then complete the SWOT and 4Ps to compare each competitor''s approach against the client''s position.", "items": [{"key": "direct", "kind": "text", "label": "Direct Competitors", "detail": "", "rows": 3}, {"key": "indirect", "kind": "text", "label": "Indirect Competitors", "detail": "", "rows": 3}, {"key": "legacy", "kind": "text", "label": "Legacy Competitors", "detail": "", "rows": 3}, {"key": "disruptor", "kind": "text", "label": "Disruptor Competitors", "detail": "", "rows": 3}, {"key": "strength", "kind": "text", "label": "Strengths", "detail": "", "rows": 3}, {"key": "weakness", "kind": "text", "label": "Weaknesses", "detail": "", "rows": 3}, {"key": "opportunities", "kind": "text", "label": "Opportunities", "detail": "", "rows": 3}, {"key": "threats", "kind": "text", "label": "Threats", "detail": "", "rows": 3}, {"key": "product", "kind": "text", "label": "Product", "detail": "", "rows": 3}, {"key": "price", "kind": "text", "label": "Price", "detail": "", "rows": 3}, {"key": "promotion", "kind": "text", "label": "Promotion", "detail": "", "rows": 3}, {"key": "place", "kind": "text", "label": "Place", "detail": "", "rows": 3}]}, {"key": "remarks", "title": "Other Remarks", "items": [{"key": "remarks", "kind": "text", "label": "Other Remarks", "detail": "", "rows": 4}]}]}'::jsonb
  end
$$;
revoke all on function public.checklist_template(text) from public, anon, authenticated;

-- One item, or a section marked not applicable (p_item is the section's key);
-- a table item takes its rows (r1.2).
create or replace function public.client_checklist_set(p_client uuid, p_kind text, p_item text, p_state text,
                                                       p_note text, p_value jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.client_checklists;
  c public.clients;
  t jsonb;
  sec jsonb;
  it jsonb;
  a jsonb;
  was jsonb;
  v_sec text := split_part(coalesce(p_item, ''), '.', 1);
  v_key text := split_part(coalesce(p_item, ''), '.', 2);
  what text;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_kind not in ('onboarding', 'pre_ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select * into c from public.clients where id = p_client;
  if c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  insert into public.client_checklists (client_id, kind, version, template, answers)
  select p_client, p_kind, t0->>'version', t0,
         (select coalesce(jsonb_object_agg(k, jsonb_build_object('value', v)), '{}'::jsonb)
            from jsonb_each(public.checklist_prefill(p_client, p_kind)) e(k, v))
    from (select public.checklist_template(p_kind) t0) z
  on conflict (client_id, kind) do nothing;
  select * into r from public.client_checklists where client_id = p_client and kind = p_kind for update;
  if r.status <> 'open' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
  t := r.template;
  select s into sec from jsonb_array_elements(t->'sections') s where s->>'key' = v_sec;
  if sec is null then return jsonb_build_object('error', 'bad-item'); end if;

  if v_key = '' then
    if p_state = 'na' then
      update public.client_checklists set sections_na = array(select distinct unnest(sections_na || v_sec)),
             updated_at = now() where id = r.id;
      what := (sec->>'title') || ': not applicable';
    elsif coalesce(p_state, '') = '' then
      update public.client_checklists set sections_na = array_remove(sections_na, v_sec), updated_at = now() where id = r.id;
      what := (sec->>'title') || ': applicable';
    else return jsonb_build_object('error', 'bad-state'); end if;
  else
    select i into it from jsonb_array_elements(sec->'items') i where i->>'key' = v_key;
    if it is null then return jsonb_build_object('error', 'bad-item'); end if;
    was := coalesce(r.answers->p_item, '{}'::jsonb);
    a := was;
    if p_state is not null then
      if it->>'kind' <> 'tick' or p_state not in ('', 'done', 'na') then return jsonb_build_object('error', 'bad-state'); end if;
      a := (a - 'state' - 'by' - 'at') || case when p_state = '' then '{}'::jsonb
             else jsonb_build_object('state', p_state, 'by', me.name, 'at', now()) end;
      what := (it->>'label') || ': ' || case p_state when 'done' then 'done' when 'na' then 'not applicable' else 'not done' end;
    end if;
    if p_note is not null then
      if char_length(p_note) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
      a := (a - 'note') || case when btrim(p_note) = '' then '{}'::jsonb else jsonb_build_object('note', btrim(p_note)) end;
      what := coalesce(what, (it->>'label') || ': note changed');
    end if;
    if p_value is not null then
      if it->>'kind' = 'tick' then return jsonb_build_object('error', 'bad-value'); end if;
      if it->>'kind' = 'text' and (jsonb_typeof(p_value) <> 'string' or char_length(p_value #>> '{}') > 4000) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      if it->>'kind' = 'choice' and (jsonb_typeof(p_value) <> 'string' or
         (p_value #>> '{}' <> '' and not (it->'choices') ? (p_value #>> '{}'))) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      if it->>'kind' = 'multi' and (jsonb_typeof(p_value) <> 'array' or
         exists (select 1 from jsonb_array_elements(p_value) v where jsonb_typeof(v) <> 'string' or not (it->'choices') ? (v #>> '{}'))) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      /* A table (r1.2's Meta Campaign Setup): twelve rows at most, each
         row only the item's own columns, each cell words of 400 at most. */
      if it->>'kind' = 'table' and (jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) > 12 or
         exists (select 1 from jsonb_array_elements(p_value) rw where jsonb_typeof(rw) <> 'object' or
           exists (select 1 from jsonb_each(rw) e where jsonb_typeof(e.value) <> 'string' or char_length(e.value #>> '{}') > 400 or
             not exists (select 1 from jsonb_array_elements(it->'columns') col where col->>0 = e.key)))) then
        return jsonb_build_object('error', 'bad-value');
      end if;
      a := (a - 'value') || case when p_value in ('""'::jsonb, '[]'::jsonb) then '{}'::jsonb
             else jsonb_build_object('value', p_value) end;
      what := coalesce(what, (it->>'label') || ': ' || case when p_value in ('""'::jsonb, '[]'::jsonb) then 'cleared' else 'changed' end);
    end if;
    if a = was then return public.client_checklist(p_client, p_kind); end if;
    update public.client_checklists set answers = case when a = '{}'::jsonb then answers - p_item else jsonb_set(answers, array[p_item], a) end,
           updated_at = now() where id = r.id;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', c.name, (t->>'title') || ' · ' || what);
  return public.client_checklist(p_client, p_kind);
end $$;
revoke all on function public.client_checklist_set(uuid, text, text, text, text, jsonb) from public, anon;
grant execute on function public.client_checklist_set(uuid, text, text, text, text, jsonb) to authenticated;

-- Counted before Claude is asked: a colleague's checklist drafts a day,
-- apart from every other AI use (Clients at Work, the client in scope).
create or replace function public.ai_checklist_claim(p_client uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  n_used integer;
  lim integer;
  new_id uuid;
begin
  if not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not exists (select 1 from public.clients c where c.id = p_client) then return jsonb_build_object('error', 'not-found'); end if;
  if not public.client_scope_ok('client', p_client, 'work') then return jsonb_build_object('error', 'client-scope'); end if;
  perform pg_advisory_xact_lock(hashtext('ai_draft_claim'));
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('checklist_admin', 20) else public.ai_draft_limit('checklist', 10) end;
  if lim = 0 then return jsonb_build_object('error', 'ai-limit', 'scope', 'stopped', 'limit', 0); end if;
  select count(*) into n_used from public.ai_drafts d
   where d.team_member_id = m.id and d.purpose = 'checklist' and d.created_at >= since and d.outcome <> 'failed';
  if n_used >= lim then
    return jsonb_build_object('error', 'ai-limit', 'scope', 'checklist', 'limit', lim, 'next', since + interval '1 day');
  end if;
  insert into public.ai_drafts (team_member_id, client_id, purpose)
  values (m.id, p_client, 'checklist') returning id into new_id;
  return jsonb_build_object('id', new_id, 'left', lim - n_used - 1, 'limit', lim);
end $$;
revoke all on function public.ai_checklist_claim(uuid) from public, anon;
grant execute on function public.ai_checklist_claim(uuid) to authenticated;

-- What Write with AI on a checklist has left today, read without writing.
create or replace function public.ai_checklist_left()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m public.team_members;
  since timestamptz := public.ai_draft_day();
  lim integer;
begin
  if not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'denied'); end if;
  lim := case when coalesce(m.is_admin, false) or m.role = 'admin'
              then public.ai_draft_limit('checklist_admin', 20) else public.ai_draft_limit('checklist', 10) end;
  return jsonb_build_object('limit', lim, 'next', since + interval '1 day',
    'left', greatest(0, lim - (select count(*) from public.ai_drafts d
      where d.team_member_id = m.id and d.purpose = 'checklist' and d.created_at >= since and d.outcome <> 'failed')::integer));
end $$;
revoke all on function public.ai_checklist_left() from public, anon;
grant execute on function public.ai_checklist_left() to authenticated;

create or replace function public.ai_draft_usage()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_day timestamptz := public.ai_draft_day();
  v_month timestamptz := now() - interval '30 days';
  -- This calendar month in Malaysia, for what the calls cost.
  v_cal timestamptz := date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur';
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object(
    'person', public.ai_draft_limit('person', 10),
    'admin', public.ai_draft_limit('admin', 20),
    'report', public.ai_draft_limit('report', 1),
    'report_admin', public.ai_draft_limit('report_admin', 5),
    'check', public.ai_draft_limit('check', 1),
    'check_admin', public.ai_draft_limit('check_admin', 5),
    'caption', public.ai_draft_limit('caption', 20),
    'caption_admin', public.ai_draft_limit('caption_admin', 40),
    'script', public.ai_draft_limit('script', 10),
    'script_admin', public.ai_draft_limit('script_admin', 20),
    'analysis', public.ai_draft_limit('analysis', 3),
    'analysis_admin', public.ai_draft_limit('analysis_admin', 10),
    'checklist', public.ai_draft_limit('checklist', 10),
    'checklist_admin', public.ai_draft_limit('checklist_admin', 20),
    'cost', (select jsonb_build_object(
        'since', v_cal,
        'price_in', public.app_setting('ai_price_in', v_today),
        'price_out', public.app_setting('ai_price_out', v_today),
        'price_search', coalesce(public.app_setting('ai_price_search', v_today), 10),
        'uses', count(*),
        'untracked', count(*) filter (where c.input_tokens is null),
        'input', coalesce(sum(c.input_tokens), 0),
        'output', coalesce(sum(c.output_tokens), 0),
        'searches', coalesce(sum(c.web_searches), 0),
        'usd', round(coalesce(sum(c.usd), 0), 2),
        'by', coalesce((select jsonb_object_agg(p.purpose, p.x) from (
            select c2.purpose, jsonb_build_object('uses', count(*), 'input', coalesce(sum(c2.input_tokens), 0),
                     'output', coalesce(sum(c2.output_tokens), 0), 'searches', coalesce(sum(c2.web_searches), 0),
                     'usd', round(coalesce(sum(c2.usd), 0), 2)) as x
              from (select d.purpose, d.input_tokens, d.output_tokens, d.web_searches,
                           (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                          + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                          + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
                      from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c2
             group by c2.purpose) p), '{}'::jsonb))
      from (select d.input_tokens, d.output_tokens, d.web_searches,
                   (coalesce(d.input_tokens, 0) * public.app_setting('ai_price_in', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)
                  + coalesce(d.output_tokens, 0) * public.app_setting('ai_price_out', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date)) / 1000000.0
                  + coalesce(d.web_searches, 0) * coalesce(public.app_setting('ai_price_search', (d.created_at at time zone 'Asia/Kuala_Lumpur')::date), 10) / 1000.0 as usd
              from public.ai_drafts d where d.created_at >= v_cal and (d.outcome <> 'failed' or d.input_tokens is not null)) c),
    'resets_at', v_day + interval '1 day',
    'people', coalesce((select jsonb_agg(s.x order by s.x ->> 'name') from (
      select jsonb_build_object(
        'id', t.id, 'name', t.name, 'code', t.staff_code, 'group', g.name, 'group_slug', t.role,
        'admin', coalesce(t.is_admin, false) or t.role = 'admin',
        'day', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose in ('draft', 'check')),
        'captions', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'caption'),
        'caption_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                            then public.ai_draft_limit('caption_admin', 40) else public.ai_draft_limit('caption', 20) end,
        'scripts', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'script'),
        'script_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                           then public.ai_draft_limit('script_admin', 20) else public.ai_draft_limit('script', 10) end,
        'analyses', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'analysis'),
        'analysis_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                             then public.ai_draft_limit('analysis_admin', 10) else public.ai_draft_limit('analysis', 3) end,
        'checklists', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at >= v_day and d.outcome <> 'failed' and d.purpose = 'checklist'),
        'checklist_cap', case when coalesce(t.is_admin, false) or t.role = 'admin'
                              then public.ai_draft_limit('checklist_admin', 20) else public.ai_draft_limit('checklist', 10) end,
        'month', (select count(*) from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month and d.outcome <> 'failed'),
        'limit', (select l.daily from public.ai_draft_limits l where l.scope = t.id::text),
        'cap', public.ai_day_cap(t)) as x
        from public.team_members t
        left join public.team_roles g on g.slug = t.role
       where t.active
         and (coalesce(t.is_admin, false) or t.role = 'admin'
              or public.level_rank(coalesce(t.access ->> 'reports', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'review', 'none')) >= public.level_rank('work')
              or public.level_rank(coalesce(t.access ->> 'scripts', 'none')) >= public.level_rank('work')
              or exists (select 1 from public.ai_drafts d where d.team_member_id = t.id and d.created_at > v_month))
    ) s), '[]'::jsonb));
end $$;
revoke all on function public.ai_draft_usage() from public, anon, authenticated;
grant execute on function public.ai_draft_usage() to authenticated;

create or replace function public.ai_draft_set_limit(p_scope text, p_daily integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_name text;
  v_was integer;
  v_def integer;
  v_unit text := ' a day';
  v_scope text := btrim(coalesce(p_scope, ''));
  t public.team_members;
begin
  if not public.ops_granted('reports.ai', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_daily is not null and (p_daily < 0 or p_daily > 500) then
    return jsonb_build_object('error', 'bad-limit');
  end if;
  if v_scope = 'person' then
    v_name := 'Each colleague'; v_def := 10;
  elsif v_scope = 'admin' then
    v_name := 'Each admin'; v_def := 20;
  elsif v_scope = 'report' then
    v_name := 'Drafts per report, each colleague'; v_def := 1;
  elsif v_scope = 'report_admin' then
    v_name := 'Drafts per report, each admin'; v_def := 5;
  elsif v_scope = 'check' then
    v_name := 'Figures checks per report, each colleague'; v_def := 1;
  elsif v_scope = 'check_admin' then
    v_name := 'Figures checks per report, each admin'; v_def := 5;
  elsif v_scope = 'caption' then
    v_name := 'Captions, each colleague'; v_def := 20;
  elsif v_scope = 'caption_admin' then
    v_name := 'Captions, each admin'; v_def := 40;
  elsif v_scope = 'script' then
    v_name := 'Scripts, each colleague'; v_def := 10;
  elsif v_scope = 'script_admin' then
    v_name := 'Scripts, each admin'; v_def := 20;
  elsif v_scope = 'analysis' then
    v_name := 'Brand analyses, each colleague'; v_def := 3;
  elsif v_scope = 'analysis_admin' then
    v_name := 'Brand analyses, each admin'; v_def := 10;
  elsif v_scope = 'checklist' then
    v_name := 'Checklists, each colleague'; v_def := 10;
  elsif v_scope = 'checklist_admin' then
    v_name := 'Checklists, each admin'; v_def := 20;
  elsif v_scope = 'team' then
    return jsonb_build_object('error', 'bad-scope');
  else
    select * into t from public.team_members x where x.id::text = v_scope;
    if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_name := t.name;
    v_def := case when coalesce(t.is_admin, false) or t.role = 'admin'
                  then public.ai_draft_limit('admin', 20) else public.ai_draft_limit('person', 10) end;
  end if;
  select l.daily into v_was from public.ai_draft_limits l where l.scope = v_scope;
  if v_was is not distinct from p_daily then return jsonb_build_object('ok', true, 'same', true); end if;
  select coalesce(x.name, x.email) into v_who from public.team_members x
   where lower(x.email) = lower(auth.jwt() ->> 'email') and x.active limit 1;
  insert into public.ai_draft_limits (scope, daily, set_by, set_at)
  values (v_scope, p_daily, v_who, now())
  on conflict (scope) do update set daily = excluded.daily, set_by = excluded.set_by, set_at = excluded.set_at;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'AI',
          v_name || ': ' ||
          case when v_was is null then 'standard, ' || v_def || v_unit when v_was = 0 then 'stopped' else v_was || v_unit end ||
          ' → ' ||
          case when p_daily is null then 'standard, ' || v_def || v_unit when p_daily = 0 then 'stopped' else p_daily || v_unit end);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.ai_draft_set_limit(text, integer) from public, anon, authenticated;
grant execute on function public.ai_draft_set_limit(text, integer) to authenticated;

-- END OF CHECKLIST WRITER ----------------------------------------------------

select public.functions_tidy();
