-- ===========================================================================
-- CLIENT CHECKLISTS — the onboarding and pre-advertising checklists, kept on
-- the client's record item by item (2026-10-15)
-- ===========================================================================
-- WHY (the user, 2026-10-15, sharing the team's New Client Onboarding and
-- Pre-Advertising Checklist forms: "where do you think this could be added
-- and use digital way of recording this checklist"; once a client each)
--   A client's first month in My Work carried two ticks, Onboarding
--   checklist and Pre-advertising checklist; the forms themselves were paper.
--
-- WHAT CHANGED
--   * `client_checklists` (RLS on, no policy, no grant): one a client and
--     kind (`onboarding`, `pre_ads`), the form as it stood when started
--     (`template`, `version`), each item's answer (`answers`: state done or
--     na, a note, a value, who and when), sections not applicable
--     (`sections_na`), and the sign-off: open, prepared, signed.
--   * `checklist_template(p_kind)` (internal) is the forms, ver. r1.1-26.
--   * `client_checklist(p_client, p_kind)` reads one (Clients View, client
--     scope), with what the record already knows prefilled (the entity, the
--     latest quotation, the brief's competitors, the confirmed Brand
--     analysis's SWOT) and hinted (the quotation issued, the first meeting).
--   * `client_checklist_set(p_client, p_kind, p_item, p_state, p_note,
--     p_value)` records an item or marks a section not applicable (Clients
--     Work, client scope at Work), while the checklist is open.
--   * `client_checklist_step(p_client, p_kind, p_step)`: `prepare` (every
--     tick done or not applicable, `incomplete` with the count), `return`,
--     `review` (by someone other than who prepared it, `own`; signs it and
--     ticks the client's month's check of the same name), `reopen` (Clients
--     Manage; keeps the signed copy in `history` and unticks the month's
--     check). Each filed `client.edited` under the client.
--   * `client_checklists_due()` answers the Active clients in scope whose
--     checklist is not signed, where the month's check is not marked Not
--     needed (the Dashboard's Needs attention).
--   * `ops_engagement_set_check` refuses a tick by hand (`use-checklist`);
--     Not needed stays the month's own.
--
-- ORDER
--   This file, then the pages. A page from before ticks the month by hand
--   and is refused; its Not needed works as before.
--
-- ROLLBACK
--   Run ops_engagement_set_check from the schema's MONTH CHECKS section again
--   (the function before this file), then:
--   drop function if exists public.client_checklists_due();
--   drop function if exists public.client_checklist_step(uuid, text, text);
--   drop function if exists public.client_checklist_set(uuid, text, text, text, text, jsonb);
--   drop function if exists public.client_checklist(uuid, text);
--   drop function if exists public.checklist_template(text);
--   drop table if exists public.client_checklists;
--
-- Safe to run twice. Mirrored byte for byte in supabase/schema.sql under the
-- same banner.
-- ===========================================================================

create table if not exists public.client_checklists (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  kind          text not null check (kind in ('onboarding', 'pre_ads')),
  version       text not null,
  template      jsonb not null,
  answers       jsonb not null default '{}'::jsonb,
  sections_na   text[] not null default '{}',
  status        text not null default 'open' check (status in ('open', 'prepared', 'signed')),
  prepared_by   uuid references public.team_members(id) on delete set null,
  prepared_name text,
  prepared_at   timestamptz,
  reviewed_by   uuid references public.team_members(id) on delete set null,
  reviewed_name text,
  reviewed_at   timestamptz,
  history       jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (client_id, kind)
);
alter table public.client_checklists enable row level security;
revoke all on table public.client_checklists from public, anon, authenticated;

create or replace function public.checklist_template(p_kind text)
returns jsonb
language sql immutable set search_path = public as $$
  select case p_kind
    when 'onboarding' then '{"kind": "onboarding", "title": "New Client Onboarding Checklist", "version": "r1.1-26", "lead": "Digital account and platform access setup, for internal project team use.", "sections": [{"key": "pre", "title": "Pre-Onboarding", "items": [{"key": "quotation", "kind": "tick", "label": "Quotation", "detail": "Issued to client and approved."}, {"key": "invoice", "kind": "tick", "label": "Invoice", "detail": "First invoice issued per agreed payment terms."}, {"key": "msa", "kind": "tick", "label": "Client MSA / NDA", "detail": "Formalisation completed, where applicable."}, {"key": "po", "kind": "tick", "label": "Client-Side PO", "detail": "Purchase order received from client, if applicable."}, {"key": "first_meeting", "kind": "tick", "label": "First Meeting (PM)", "detail": "Introductory meeting between client and assigned PM scheduled."}]}, {"key": "basics", "title": "Client & Contract Basics", "items": [{"key": "work_order", "kind": "tick", "label": "Work Order", "detail": "Deliverables, channels and retainer scope agreed in writing."}, {"key": "work_group", "kind": "tick", "label": "Client Work Group", "detail": "Authorised members all added into the work WhatsApp group."}, {"key": "pm", "kind": "tick", "label": "PM Assignment", "detail": "Internal point of contact confirmed and introduced to client."}, {"key": "kickoff", "kind": "tick", "label": "Kick-off Call", "detail": "Calendar invite sent, agenda shared in advance."}]}, {"key": "brand", "title": "Brand & Creative Assets", "items": [{"key": "guideline", "kind": "tick", "label": "Brand Guideline", "detail": "Logo usage, colour palette, typography and tone of voice."}, {"key": "logos", "kind": "tick", "label": "Logo Files (AI / EPS / SVG, PNG)", "detail": "Vector and raster formats in all colour variants."}, {"key": "assets", "kind": "tick", "label": "Product / Service Assets", "detail": "Photography, video and any existing creative library."}, {"key": "drive", "kind": "tick", "label": "Shared Drive (View) Access", "detail": "Google Drive / Dropbox folder created and shared both ways."}, {"key": "tone", "kind": "tick", "label": "Tone of Voice Brief", "detail": "Messaging pillars, dos and don''ts, English, Chinese and Malay preferences."}, {"key": "competitors", "kind": "tick", "label": "Competitor List", "detail": "Direct competitors and reference brands for positioning."}]}, {"key": "meta_page", "title": "Meta, Facebook & Instagram Page Access", "note": "Confirm Page and Business Manager access before ad account setup begins.", "platform": "meta", "items": [{"key": "fb_page", "kind": "tick", "label": "Facebook Page", "detail": "Page name and URL verified with client."}, {"key": "partner", "kind": "tick", "label": "ADspace Partner Access", "detail": "Client adds ADspace Business Manager as Partner via Meta Business Suite."}, {"key": "page_role", "kind": "tick", "label": "Page Admin Role", "detail": "ADspace team assigned appropriate Page role, not personal profile access."}, {"key": "ig_pro", "kind": "tick", "label": "Instagram Professional Account", "detail": "Business or Creator account type confirmed."}, {"key": "ig_link", "kind": "tick", "label": "Instagram, Facebook Page Link", "detail": "Verified in Meta Business Suite, Accounts tab."}, {"key": "otp", "kind": "tick", "label": "OTP / 2FA Verification", "detail": "Client''s registered mobile number verified for account security."}, {"key": "biz_verify", "kind": "tick", "label": "Meta Business Verification", "detail": "Business Manager verified where required for scaled ad spend."}]}, {"key": "meta_ads", "title": "Meta Ad Account Setup", "note": "Complete after Page and Business Manager access are confirmed above.", "platform": "meta", "items": [{"key": "ad_account", "kind": "tick", "label": "Ad Account", "detail": "New ad account or existing one linked to ADspace''s Business Manager."}, {"key": "roles", "kind": "tick", "label": "Ad Account Role Assignment", "detail": "Admin, Advertiser or Analyst role set per team member."}, {"key": "payment", "kind": "tick", "label": "Payment Method", "detail": "Card or local billing threshold set up, MYR or SGD billing."}, {"key": "billing", "kind": "tick", "label": "Billing Currency & Address", "detail": "Matches client''s registered business details."}, {"key": "wa_link", "kind": "tick", "label": "WhatsApp Business Link", "detail": "WhatsApp number linked to Page / ad account for click to WhatsApp ads."}, {"key": "leads_tos", "kind": "tick", "label": "Leads Terms of Service", "detail": "Client accepts in Meta Business Suite, Leads Center, before lead ads run."}, {"key": "special_ads", "kind": "tick", "label": "Locality Advertising Authorisation", "detail": "Special ad category authorisation (housing, employment, credit, social issue / electoral / political) applied where applicable."}, {"key": "phone", "kind": "tick", "label": "OTP / Phone Verification", "detail": "Ad account owner''s phone verified."}, {"key": "pixel", "kind": "tick", "label": "Meta Pixel / Conversions API", "detail": "Installed on client''s website, events verified in Events Manager."}, {"key": "domain", "kind": "tick", "label": "Domain Verification", "detail": "Required for iOS14+ event prioritisation and Aggregated Event Measurement."}, {"key": "pre_ads", "kind": "tick", "label": "Pre-Advertising Checklist", "detail": "Completed and signed off before the first campaign goes live."}]}, {"key": "linkedin", "title": "LinkedIn Business Manager", "platform": "linkedin", "items": [{"key": "company_page", "kind": "tick", "label": "LinkedIn Company Page", "detail": "Page name and URL verified with client."}, {"key": "page_admin", "kind": "tick", "label": "Page Admin Access", "detail": "Super Admin or Content Admin role granted on the Company Page."}]}, {"key": "tiktok", "title": "TikTok Business Manager", "platform": "tiktok", "items": [{"key": "account", "kind": "tick", "label": "TikTok Business Account", "detail": "Client''s Business Center account identified."}, {"key": "center", "kind": "tick", "label": "Business Center Access", "detail": "ADspace added as partner / member with correct role assignment."}, {"key": "ads_link", "kind": "tick", "label": "Ads Manager Account Link", "detail": "Ad account linked under the Business Center."}, {"key": "access", "kind": "tick", "label": "Ad Account Access", "detail": "Team members added with appropriate permission level."}, {"key": "payment", "kind": "tick", "label": "Payment Method", "detail": "Billing currency confirmed for MY / SG ad account."}, {"key": "verify", "kind": "tick", "label": "Business / Identity Verification", "detail": "Required for certain ad account types or spend thresholds."}, {"key": "pixel", "kind": "tick", "label": "TikTok Pixel / Events API", "detail": "Installed on website and verified as firing correctly."}]}, {"key": "rednote", "title": "rednote (小红书)", "note": "rednote has limited multi-user support.", "platform": "rednote", "items": [{"key": "enterprise", "kind": "tick", "label": "Enterprise Account (企业号)", "detail": "Registered and active, where applicable."}, {"key": "verify", "kind": "tick", "label": "Business Verification (企业认证)", "detail": "Completed with the correct business licence."}, {"key": "access", "kind": "tick", "label": "Access Arrangement", "detail": "Delegated access or shared login credentials logged securely."}, {"key": "ads", "kind": "tick", "label": "Ad Platform Access (聚光引擎 / 蒲公英)", "detail": "Set up if paid campaigns are in scope."}, {"key": "compliance", "kind": "tick", "label": "Content Compliance Brief", "detail": "Content briefed against XHS Safe Mode guidelines where applicable."}]}, {"key": "douyin", "title": "Douyin (抖音)", "platform": "douyin", "items": [{"key": "access", "kind": "tick", "label": "Access Arrangement", "detail": "Delegated access or shared login credentials logged securely."}]}, {"key": "content", "title": "Content Planning", "items": [{"key": "calendar_access", "kind": "tick", "label": "Content Calendar Access", "detail": "Client added as viewer / commenter for review and sign-off."}, {"key": "pillars", "kind": "tick", "label": "First Month Content Pillars", "detail": "Themes and campaign tie-ins agreed with client (refer to the initial pitch deck)."}, {"key": "calendar_brief", "kind": "tick", "label": "Content Calendar Brief", "detail": "Client walked through ADspace''s standard content calendar."}, {"key": "frequency", "kind": "tick", "label": "Posting Frequency", "detail": "Cadence agreed for each active channel."}, {"key": "approval", "kind": "tick", "label": "Content Approval Workflow", "detail": "Review rounds and turnaround time confirmed."}]}, {"key": "reporting", "title": "Reporting & Access", "items": [{"key": "cadence", "kind": "tick", "label": "Reporting Cadence", "detail": "Quarterly / Monthly / Weekly / Daily format."}, {"key": "credentials", "kind": "tick", "label": "Credentials Register", "detail": "All login credentials logged in the Content Calendar sheet."}, {"key": "handover", "kind": "tick", "label": "Internal Handover", "detail": "Onboarding PM briefs servicing team with full access list."}]}]}'::jsonb
    when 'pre_ads' then '{"kind": "pre_ads", "title": "Pre-Advertising Checklist", "version": "r1.1-26", "lead": "Campaign readiness check completed before ads go live.", "sections": [{"key": "details", "title": "Campaign Details", "items": [{"key": "entity", "kind": "text", "label": "Entity Name", "detail": "", "rows": 1}, {"key": "quotation", "kind": "text", "label": "Quotation Reference", "detail": "", "rows": 1}, {"key": "objective", "kind": "multi", "label": "Main Objective", "choices": ["Awareness", "Leads", "Sales", "Traffic"]}]}, {"key": "meta", "title": "Meta Campaign Setup", "platform": "meta", "items": [{"key": "setup", "kind": "tick", "label": "Ad Account Campaign Setup", "detail": "Campaign, ad set and ad structure built."}]}, {"key": "rednote", "title": "rednote Campaign Setup", "platform": "rednote", "items": [{"key": "billing", "kind": "tick", "label": "rednote Account Billing / Payment", "detail": "Payment method confirmed for 聚光引擎 / 蒲公英 ad spend."}, {"key": "setup", "kind": "tick", "label": "Ad Account Campaign Setup", "detail": "Campaign structure built and named."}]}, {"key": "tiktok", "title": "TikTok Campaign Setup", "platform": "tiktok", "items": [{"key": "setup", "kind": "tick", "label": "Ad Account Campaign Setup", "detail": "Campaign, ad group and ad structure built."}]}, {"key": "targeting", "title": "Targeting Information", "items": [{"key": "age", "kind": "text", "label": "Age Group", "detail": "", "rows": 1}, {"key": "ethnicity", "kind": "text", "label": "Ethnicity", "detail": "", "rows": 1}, {"key": "country", "kind": "multi", "label": "Country", "choices": ["Malaysia (Peninsular)", "Malaysia (Sabah & Sarawak)", "Singapore"]}, {"key": "frequency", "kind": "text", "label": "Ad Frequency", "detail": "", "rows": 1}, {"key": "scheduling", "kind": "text", "label": "Ad Scheduling", "detail": "", "rows": 1}, {"key": "placement", "kind": "text", "label": "Ad Placement", "detail": "", "rows": 1}, {"key": "retargeting", "kind": "multi", "label": "Ad Re-Targeting", "choices": ["Old", "New", "Lookalike"]}]}, {"key": "tracking", "title": "Tracking & Analytics (External)", "items": [{"key": "pixel", "kind": "multi", "label": "Pixel / Analytics Connection", "choices": ["Website", "App", "Landing Page", "External Site"]}, {"key": "pixel_site", "kind": "text", "label": "External Site", "detail": "", "rows": 1}, {"key": "relevance", "kind": "multi", "label": "Tracking Relevance", "choices": ["Page Views", "Purchases", "Contact Leads"]}, {"key": "schedule", "kind": "choice", "label": "Ads Reporting Schedule", "choices": ["Quarterly", "Monthly", "Weekly", "Daily"]}]}, {"key": "competitors", "title": "Competitor Analysis", "note": "List competitor names, then complete the SWOT and 4Ps to compare each competitor''s approach against the client''s position.", "items": [{"key": "direct", "kind": "text", "label": "Direct Competitors", "detail": "", "rows": 3}, {"key": "indirect", "kind": "text", "label": "Indirect Competitors", "detail": "", "rows": 3}, {"key": "legacy", "kind": "text", "label": "Legacy Competitors", "detail": "", "rows": 3}, {"key": "disruptor", "kind": "text", "label": "Disruptor Competitors", "detail": "", "rows": 3}, {"key": "strength", "kind": "text", "label": "Strengths", "detail": "", "rows": 3}, {"key": "weakness", "kind": "text", "label": "Weaknesses", "detail": "", "rows": 3}, {"key": "opportunities", "kind": "text", "label": "Opportunities", "detail": "", "rows": 3}, {"key": "threats", "kind": "text", "label": "Threats", "detail": "", "rows": 3}, {"key": "product", "kind": "text", "label": "Product", "detail": "", "rows": 3}, {"key": "price", "kind": "text", "label": "Price", "detail": "", "rows": 3}, {"key": "promotion", "kind": "text", "label": "Promotion", "detail": "", "rows": 3}, {"key": "place", "kind": "text", "label": "Place", "detail": "", "rows": 3}]}, {"key": "remarks", "title": "Other Remarks", "items": [{"key": "remarks", "kind": "text", "label": "Other Remarks", "detail": "", "rows": 4}]}]}'::jsonb
  end
$$;
revoke all on function public.checklist_template(text) from public, anon, authenticated;

-- What the record already knows, for the fields a checklist asks.
create or replace function public.checklist_prefill(p_client uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients;
  q text;
  sw jsonb;
  j text := E'\n';
begin
  select * into c from public.clients where id = p_client;
  if c.id is null or p_kind <> 'pre_ads' then return '{}'::jsonb; end if;
  select x.ref into q from public.quotations x
   where x.client_id = p_client and x.removed_at is null order by x.issued_at desc limit 1;
  select b.analysis->'swot' into sw from public.brand_analyses b
   where b.client_id = p_client and b.confirmed_at is not null order by b.version desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    'details.entity', nullif(coalesce(nullif(btrim(c.legal_name), ''), c.name), ''),
    'details.quotation', q,
    'competitors.direct', nullif(btrim(coalesce(c.brief->>'competitors', '')), ''),
    'competitors.strength', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'strengths', '[]'::jsonb))), j), ''),
    'competitors.weakness', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'weaknesses', '[]'::jsonb))), j), ''),
    'competitors.opportunities', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'opportunities', '[]'::jsonb))), j), ''),
    'competitors.threats', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'threats', '[]'::jsonb))), j), '')));
end $$;
revoke all on function public.checklist_prefill(uuid, text) from public, anon, authenticated;

create or replace function public.client_checklist(p_client uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.client_checklists;
  t jsonb;
  pre jsonb;
  hints jsonb := '{}'::jsonb;
  q record;
  m timestamptz;
begin
  if me.id is null or not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_kind not in ('onboarding', 'pre_ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select * into r from public.client_checklists where client_id = p_client and kind = p_kind;
  t := coalesce(r.template, public.checklist_template(p_kind));
  if r.id is null then pre := public.checklist_prefill(p_client, p_kind); end if;
  if p_kind = 'onboarding' then
    select x.ref, x.issued_at into q from public.quotations x
     where x.client_id = p_client and x.removed_at is null order by x.issued_at desc limit 1;
    if q.ref is not null then
      hints := hints || jsonb_build_object('pre.quotation', 'Quotation ' || q.ref || ' issued ' ||
        to_char(q.issued_at at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY'));
    end if;
    select min(e.meeting_at) into m from public.ops_engagements e where e.client_id = p_client and e.meeting_at is not null;
    if m is not null then
      hints := hints || jsonb_build_object('pre.first_meeting', 'Meeting set for ' ||
        to_char(m at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY, FMHH12:MIam'));
    end if;
  end if;
  return jsonb_build_object(
    'kind', p_kind, 'title', t->>'title', 'version', t->>'version', 'lead', t->>'lead', 'sections', t->'sections',
    'started', r.id is not null, 'answers', coalesce(r.answers, '{}'::jsonb), 'prefill', coalesce(pre, '{}'::jsonb),
    'sections_na', to_jsonb(coalesce(r.sections_na, '{}'::text[])), 'status', coalesce(r.status, 'open'),
    'prepared', case when r.prepared_at is not null then jsonb_build_object('id', r.prepared_by, 'name', r.prepared_name, 'at', r.prepared_at) end,
    'reviewed', case when r.reviewed_at is not null then jsonb_build_object('id', r.reviewed_by, 'name', r.reviewed_name, 'at', r.reviewed_at) end,
    'history', jsonb_array_length(coalesce(r.history, '[]'::jsonb)),
    'hints', hints, 'me', me.id,
    'can_work', public.allowed('clients', 'work') and public.client_scope_ok('client', p_client, 'work'),
    'can_manage', public.allowed('clients', 'manage') and public.client_scope_ok('client', p_client, 'manage'),
    'updated_at', r.updated_at);
end $$;
revoke all on function public.client_checklist(uuid, text) from public, anon;
grant execute on function public.client_checklist(uuid, text) to authenticated;

-- One item, or a section marked not applicable (p_item is the section's key).
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

create or replace function public.client_checklist_step(p_client uuid, p_kind text, p_step text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.client_checklists;
  c public.clients;
  n int;
  word text;
begin
  if me.id is null or not public.allowed('clients', case when p_step = 'reopen' then 'manage' else 'work' end) then
    return jsonb_build_object('error', 'denied');
  end if;
  if not public.client_scope_ok('client', p_client, case when p_step = 'reopen' then 'manage' else 'work' end) then
    return jsonb_build_object('error', 'client-scope');
  end if;
  select * into c from public.clients where id = p_client;
  select * into r from public.client_checklists where client_id = p_client and kind = p_kind for update;
  if c.id is null or r.id is null then return jsonb_build_object('error', 'not-started'); end if;
  if p_step = 'prepare' then
    if r.status <> 'open' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    select count(*) into n
      from jsonb_array_elements(r.template->'sections') s, jsonb_array_elements(s->'items') i
     where i->>'kind' = 'tick' and not ((s->>'key') = any(r.sections_na))
       and coalesce(r.answers->((s->>'key') || '.' || (i->>'key'))->>'state', '') not in ('done', 'na');
    if n > 0 then return jsonb_build_object('error', 'incomplete', 'left', n); end if;
    update public.client_checklists set status = 'prepared', prepared_by = me.id, prepared_name = me.name,
           prepared_at = now(), updated_at = now() where id = r.id;
    word := 'prepared for review';
  elsif p_step = 'return' then
    if r.status <> 'prepared' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    update public.client_checklists set status = 'open', prepared_by = null, prepared_name = null, prepared_at = null,
           updated_at = now() where id = r.id;
    word := 'sent back';
  elsif p_step = 'review' then
    if r.status <> 'prepared' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    if r.prepared_by = me.id then return jsonb_build_object('error', 'own'); end if;
    update public.client_checklists set status = 'signed', reviewed_by = me.id, reviewed_name = me.name,
           reviewed_at = now(), updated_at = now() where id = r.id;
    update public.ops_engagement_checks k set state = 'ready', owner_id = me.id, updated_by = me.id, updated_at = now()
      from public.ops_engagements e
     where e.id = k.engagement_id and e.client_id = p_client and k.key = p_kind and k.state <> 'na';
    word := 'reviewed and signed off';
  elsif p_step = 'reopen' then
    if r.status <> 'signed' then return jsonb_build_object('error', 'locked', 'status', r.status); end if;
    update public.client_checklists set status = 'open',
           history = history || jsonb_build_array(jsonb_build_object('answers', r.answers, 'sections_na', to_jsonb(r.sections_na),
             'version', r.version, 'prepared', r.prepared_name, 'prepared_at', r.prepared_at,
             'reviewed', r.reviewed_name, 'reviewed_at', r.reviewed_at, 'reopened_by', me.name, 'reopened_at', now())),
           prepared_by = null, prepared_name = null, prepared_at = null,
           reviewed_by = null, reviewed_name = null, reviewed_at = null, updated_at = now() where id = r.id;
    update public.ops_engagement_checks k set state = 'not_started', owner_id = null, updated_by = me.id, updated_at = now()
      from public.ops_engagements e
     where e.id = k.engagement_id and e.client_id = p_client and k.key = p_kind and k.state = 'ready';
    word := 'reopened';
  else
    return jsonb_build_object('error', 'bad-step');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.edited', c.name, (r.template->>'title') || ' · ' || word);
  return public.client_checklist(p_client, p_kind);
end $$;
revoke all on function public.client_checklist_step(uuid, text, text) from public, anon;
grant execute on function public.client_checklist_step(uuid, text, text) to authenticated;

-- What the Dashboard lists: an Active client's checklist not signed, unless
-- its month marks it Not needed.
create or replace function public.client_checklists_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null or not public.allowed('clients', 'view') then '[]'::jsonb else
    coalesce((select jsonb_agg(jsonb_build_object('client_id', c.id, 'name', c.name, 'slug', c.slug, 'owner', c.owner,
              'kind', k.kind, 'status', coalesce(r.status, 'open'), 'started', r.id is not null,
              'since', coalesce(c.stage_since, c.created_at)) order by coalesce(c.stage_since, c.created_at))
       from public.clients c
       cross join (values ('onboarding'), ('pre_ads')) k(kind)
       left join public.client_checklists r on r.client_id = c.id and r.kind = k.kind
      where c.stage = 'active'
        and coalesce(r.status, 'open') <> 'signed'
        and public.client_scope_ok('client', c.id, 'view')
        and not exists (select 1 from public.ops_engagement_checks x join public.ops_engagements e on e.id = x.engagement_id
                         where e.client_id = c.id and x.key = k.kind and x.state = 'na')), '[]'::jsonb) end
$$;
revoke all on function public.client_checklists_due() from public, anon;
grant execute on function public.client_checklists_due() to authenticated;

-- A month's check is ticked by its checklist's sign-off, never by hand.
create or replace function public.ops_engagement_set_check(
  p_engagement uuid, p_key text, p_state text, p_owner uuid default null, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; was text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  if p_state not in ('not_started', 'waiting_client', 'in_progress', 'ready', 'na') then
    return jsonb_build_object('error', 'bad-state');
  end if;
  select state into was from public.ops_engagement_checks
   where engagement_id = p_engagement and key = p_key;
  if was is null then return jsonb_build_object('error', 'no-such-check'); end if;
  if p_state = 'ready' and was <> 'ready' then return jsonb_build_object('error', 'use-checklist'); end if;
  if was = 'ready' and p_state <> 'ready' and exists (select 1 from public.client_checklists r
       join public.ops_engagements e on e.client_id = r.client_id
      where e.id = p_engagement and r.kind = p_key and r.status = 'signed') then
    return jsonb_build_object('error', 'use-checklist');
  end if;
  if was = p_state and p_note is null then return public.ops_engagement_json(p_engagement); end if;
  update public.ops_engagement_checks
     set state = p_state, owner_id = m.id,
         note = case when p_note is null then note else nullif(btrim(p_note), '') end,
         updated_by = m.id, updated_at = now()
   where engagement_id = p_engagement and key = p_key;
  perform public.ops_engagement_log(p_engagement, 'check_changed',
    jsonb_build_object('key', p_key, 'from', was, 'to', p_state));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_check(uuid, text, text, uuid, text) to authenticated;

-- END OF CLIENT CHECKLISTS ---------------------------------------------------

select public.functions_tidy();
