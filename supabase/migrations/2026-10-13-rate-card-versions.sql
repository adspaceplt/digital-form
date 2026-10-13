-- ===========================================================================
-- RATE CARD VERSIONS — the rate card is edited as a draft and goes live as
-- a numbered version; each line carries what a quote needs to know of it.
-- 2026-10-13. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED (the user, 2026-10-13: the rate card "should run based on
-- versioning, so every version changed would proceed proper updates to the
-- site and export")
--   1. `services.spec`: what a quote reads of a line. A plan (its letter,
--      with or without ads, platforms and contents a month, the content
--      mixes it offers, the ad budget it covers, who it is for); a platform's
--      management fee; Meta advertising and an ad booster (the budget each
--      covers); translation (an added language); a content format; the KOL
--      management fee's tiers; a verification's own fee; an add-on's group
--      on the card. Checked by `service_spec_ok`. Seeded only where a line
--      holds none.
--   2. `rate_card_text`: the card's own words (What's Included, notes, the
--      KOC and KOL pages, the Terms of Service), one block a key, seeded
--      once from Rate Card v.2.0.6 and changed only by
--      `rate_card_text_save` (Services Full Access, filed
--      `service.changed` under Rate card wording).
--   3. `rate_card_versions`: each version published, whole
--      (`rate_card_publish(p_version, p_valid_until, p_note)`, Services
--      Full Access: the lines, the words, SST and the term percentages as
--      at that day; `bad-version`, `version-taken`, `bad-date`,
--      `no-change`; filed `service.published`). `rate_card_current()`
--      answers the latest. The live card is seeded once as v.2.0.6, valid
--      until 31 December 2026. A client's service lines are priced from the
--      version, never from the draft.
--
-- ORDER
--   This file, then the pages. A page from before reads the draft as it
--   always did.
--
-- ROLLBACK
--   The pages from before. The tables and the column may stay: nothing
--   from before reads them.
-- ===========================================================================

alter table public.services add column if not exists spec jsonb;

create or replace function public.service_spec_ok(p jsonb)
returns boolean
language sql immutable set search_path = public as $$
  select p is null or (
    jsonb_typeof(p) = 'object'
    and coalesce(p->>'role', '') in ('', 'plan', 'platform', 'ads', 'booster', 'language', 'content', 'kol', 'koc', 'verify', 'addon')
    and (p->>'role' is distinct from 'plan' or (
      coalesce(p->>'plan', '') ~ '^[A-Z]$'
      and coalesce(p->>'platforms', '') ~ '^[1-9][0-9]?$'
      and coalesce(p->>'contents', '') ~ '^[1-9][0-9]?$'
      and jsonb_typeof(coalesce(p->'mix', 'null'::jsonb)) = 'array'
      and jsonb_array_length(p->'mix') between 1 and 3
      and (p->>'ad_budget' is null or coalesce(p->>'ad_budget', '') ~ '^[0-9]+(\.[0-9]+)?$')))
    and (p->>'role' not in ('ads', 'booster') or coalesce(p->>'budget', '') ~ '^[1-9][0-9]*$')
    and (p->>'role' is distinct from 'platform' or p->>'platform' in ('meta', 'tiktok', 'rednote', 'linkedin')))
$$;

do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'services_spec_ok') then
    alter table public.services add constraint services_spec_ok check (public.service_spec_ok(spec));
  end if;
end $c$;

-- What a quote reads of each line on the card, from Rate Card v.2.0.6.
update public.services s set spec = v.spec::jsonb
  from (values
    ('pkg-a', '{"role":"plan","plan":"A","ads":false,"platforms":1,"contents":2,"mix":[{"graphic":1,"reel":1}],"best_for":"Ideal for brands beginning their social media journey"}'),
    ('pkg-b', '{"role":"plan","plan":"B","ads":false,"platforms":2,"contents":4,"mix":[{"graphic":1,"reel":3},{"reel":4}],"best_for":"Ideal for brands building sustained momentum"}'),
    ('pkg-c', '{"role":"plan","plan":"C","ads":false,"platforms":3,"contents":8,"mix":[{"graphic":3,"reel":4},{"reel":8}],"best_for":"Ideal for brands scaling their full digital presence"}'),
    ('pkg-d', '{"role":"plan","plan":"D","ads":true,"platforms":1,"contents":4,"mix":[{"graphic":2,"reel":2}],"ad_budget":2000,"best_for":"Ideal for brands launching their first paid push"}'),
    ('pkg-e', '{"role":"plan","plan":"E","ads":true,"platforms":2,"contents":6,"mix":[{"graphic":2,"reel":4}],"ad_budget":4000,"best_for":"Ideal for brands sustaining steady momentum"}'),
    ('pkg-f', '{"role":"plan","plan":"F","ads":true,"platforms":3,"contents":10,"mix":[{"graphic":4,"reel":6}],"ad_budget":8000,"best_for":"Ideal for brands pursuing aggressive growth"}'),
    ('mgmt-meta', '{"role":"platform","platform":"meta"}'),
    ('mgmt-tiktok', '{"role":"platform","platform":"tiktok"}'),
    ('mgmt-xhs', '{"role":"platform","platform":"rednote"}'),
    ('mgmt-linkedin', '{"role":"platform","platform":"linkedin"}'),
    ('ads-meta-2k', '{"role":"ads","budget":2000}'),
    ('ads-meta-4k', '{"role":"ads","budget":4000}'),
    ('ads-8k', '{"role":"booster","budget":8000}'),
    ('ads-14k', '{"role":"booster","budget":14000}'),
    ('ads-20k', '{"role":"booster","budget":20000}'),
    ('static-graphic', '{"role":"content","kind":"graphic"}'),
    ('gif', '{"role":"content","kind":"gif"}'),
    ('carousel', '{"role":"content","kind":"carousel"}'),
    ('reels-30', '{"role":"content","kind":"reel30"}'),
    ('reels-60', '{"role":"content","kind":"reel"}'),
    ('short-video-120', '{"role":"content","kind":"video120"}'),
    ('verify-meta', '{"role":"verify","fee":"Meta Subscription Fee"}'),
    ('verify-xhs', '{"role":"verify","fee":"Includes 600 RMB Platform Fee"}'),
    ('koc-10', '{"role":"koc","creators":10}'),
    ('koc-15', '{"role":"koc","creators":15}'),
    ('koc-20', '{"role":"koc","creators":20}'),
    ('koc-custom', '{"role":"koc"}'),
    ('kol-mgmt', '{"role":"kol","tiers":[{"upto":3000,"pct":18,"min":500},{"upto":15000,"pct":16,"min":800},{"upto":30000,"pct":14,"min":2500},{"upto":null,"pct":12,"min":4000}]}'),
    ('rev-minor', '{"role":"addon","group":"Revisions & Turnaround"}'),
    ('rev-major', '{"role":"addon","group":"Revisions & Turnaround"}'),
    ('urgent', '{"role":"addon","group":"Revisions & Turnaround"}'),
    ('translation', '{"role":"language","group":"Localisation & Formats"}'),
    ('resize', '{"role":"addon","group":"Localisation & Formats"}'),
    ('shoot', '{"role":"addon","group":"Production"}'),
    ('working-files', '{"role":"addon","group":"File Release"}'),
    ('raw-footage', '{"role":"addon","group":"File Release"}')
  ) as v(slug, spec)
 where s.slug = v.slug and s.spec is null;

-- The card's own words, a block a key. Seeded once; changed only through
-- rate_card_text_save.
create table if not exists public.rate_card_text (
  key        text primary key,
  label      text not null,
  page       text not null,
  position   int not null default 0,
  value      text not null default '',
  updated_at timestamptz not null default now(),
  updated_by text
);
alter table public.rate_card_text enable row level security;
do $p$
begin
  if not exists (select 1 from pg_policies where tablename = 'rate_card_text' and policyname = 'rate_card_text_read') then
    create policy rate_card_text_read on public.rate_card_text for select to authenticated
      using (public.allowed('services', 'view'));
  end if;
end $p$;

insert into public.rate_card_text (key, label, page, position, value) values
  ('cover_title', 'Cover title', 'Cover', 1, 'Rate Card & Packages'),
  ('accounts_included', 'Social Media Accounts: What''s Included', 'Ala Carté', 10,
   E'Dedicated account management and content posting\nProfessional copywriting for every planned deliverable (optional)\nEnquiries passing to clients'),
  ('verify_included', 'Account Verifications: What''s Included', 'Ala Carté', 11,
   E'Preparation of necessary documents for verification#\nOne-time submission of application to platform\nClient must provide statutory documents (eg. SSM Cert, Section 14)'),
  ('ads_included', 'Digital Advertising: What''s Included', 'Ala Carté', 12,
   E'Full advertising campaign setup and ongoing management\nWeekly advertising performance snapshot\nComprehensive monthly performance report'),
  ('alacarte_note', 'Ala Carté: Note', 'Ala Carté', 13,
   E'One on-site shoot is included in all video rates; additional shoots are quoted separately based on location.\nTwo revision rounds are included per deliverable, covering corrections, captions, tagging, trims and sequence adjustments.'),
  ('verify_footnote', 'Ala Carté: Verification footnote', 'Ala Carté', 14,
   '#Verification eligibility will be conducted pre-confirmation. Subjects to platform''s approval.'),
  ('plans_included', 'Without Ads: What''s Included', 'Social Media Services', 20,
   E'Dedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nBasic accounts analytics report'),
  ('plans_ads_included', 'With Ads: What''s Included', 'Social Media Services', 21,
   E'Dedicated account management and content posting\nStrategic content planning for every deliverable\nProfessional copywriting for every planned deliverable\nOne-time on-site shoot for Reels content\nFull advertising campaign setup and ongoing management\nWeekly advertising performance snapshot\nComprehensive monthly performance report'),
  ('custom_pricing', 'Custom Pricing', 'Social Media Services', 22,
   'Have something specific in mind? We''ll tailor it exactly to your brand.'),
  ('plans_note', 'Social Media Services: Note', 'Social Media Services', 23,
   E'Monthly services require a minimum commitment of six (6) months.\n*Advertising budget is not included in the service fee. Recommend: Payment to be paid by client''s card.'),
  ('koc_intro', 'KOC Programmes: Opening', 'KOC Programmes', 30,
   E'KOC | everyday users and micro-creators. Relatable, first-person content at accessible cost.\nKOL | established influencers and industry voices. Existing reach and audience trust.'),
  ('koc_formats', 'Push Formats (Format | What It Involves | Best For)', 'KOC Programmes', 31,
   E'Site-Visit | Creators visit the outlet and post on-location content. | F&B, retail, malls and precincts\nEvent | Creators attend the launch and publish same-day coverage. | Openings, festive activations, media days\nProduct Seeding | Product sent to creator. Unboxing or review filmed at home. | Consumer products, no fixed location\nTenant Trail | One creator covers several tenants in a single visit. | Malls, mixed-use developments\nPre-Launch Teaser | Coordinated posting ahead of opening or launch day. | New outlets, product launches\nAlways-On Review | Steady flow of reviews across the month | Platforms high discovery and visibility'),
  ('koc_package_included', 'I – Package: What''s Included', 'KOC Programmes', 32,
   E'We source and book from our own KOC pool with fixed rate\nMatched to your industry and campaign goal\nMinimum 2,000 followers per creator'),
  ('koc_custom_included', 'II – Custom: What''s Included', 'KOC Programmes', 33,
   E'You select the creators you want to engage\nWe issue a costed list of available KOCs\nProfile and individual rate shown for each'),
  ('koc_custom_price', 'II – Custom: Pricing', 'KOC Programmes', 34, 'Ad hoc pricing list to be provided'),
  ('koc_lead_time', 'Lead time (Package | Custom)', 'KOC Programmes', 35, '3 to 4 weeks | 4 to 5 weeks'),
  ('koc_best_for', 'Best For (Package | Custom)', 'KOC Programmes', 36, 'Quick and broad pushes. | Detailed vetting of creators fit.'),
  ('koc_timeline', 'Timeline (Step | When)', 'KOC Programmes', 37,
   E'Brief In | Day 0\nSource + Vet | Days 1–7\nConfirm | Days 8–10\nBrief + Visit | Week 2 – 3\nDraft + Amend | Week 3 – 4\nLive + Report | Week 4 – 5'),
  ('koc_note', 'KOC Programmes: Note', 'KOC Programmes', 38,
   E'Two revision rounds per deliverable: corrections, captions, tagging, trims and sequence adjustments.\nFor content in the creator''s own style, revisions exclude reshoots and changes to video structure, editing style, pacing or music. Structural rework is quoted separately.'),
  ('kol_intro', 'KOL Programmes: Opening', 'KOL Programmes', 40,
   'Talent fees are passed through at the rate the creator quotes, with no markup applied.'),
  ('kol_tiers', 'Tiers (Tier | Followers | Indicative Talent Fee)', 'KOL Programmes', 41,
   E'Micro | 50K to 200K | RM 3,000 to RM 10,000\nMacro | 200K and above | From RM 10,000'),
  ('kol_tiers_note', 'Tiers: Footnote', 'KOL Programmes', 42,
   '**Indicative talent fees are market estimates only and do not constitute a quotation. Final fees are confirmed by each creator at the time of booking and may fall outside the ranges shown, depending on deliverables, exclusivity, usage rights and campaign period.'),
  ('kol_included', 'Management Fee: What''s Included', 'KOL Programmes', 43,
   E'Creator sourcing and shortlisting\nRate negotiation and quotation handling\nCampaign briefing and content direction\nScheduling and posting coordination\nContent review and revision cycles\nPublication verification and reporting'),
  ('kol_fee_note', 'Management Fee: Note', 'KOL Programmes', 44,
   'Engagements of three (3) or more KOLs in a single campaign are quoted separately, with a consolidated management fee in place of the per-talent rates above.'),
  ('terms', 'Terms of Service', 'Add-ons', 50,
   E'All rates are quoted in Ringgit Malaysia (RM) and exclude the applicable 8% Service Tax (SST).\nPayment terms will be pre-approved for seven days (NET 7). Credit terms are provided upon request.\nFor term commitment discounts are only applicable to Service Fee. If there are more than one discount rules apply, the discounts value will be capped at a maximum of 15% of total package value.\nAdvertising budget is not included in the Service Fee and are quoted or billed/disbursed separately. Payable in advance before every advertising cycle. Any third-party charges by the advertising platforms and any relevant taxes and royalties are borne by the Client.\nDuring festive and peak period, there may be longer lead times apply for our service or creator engagements.\nContent will only be licensed to Client''s organic use on own platforms or channels only. Any additional usage or publications may be charged separately.\nAll working files and raw footages are available for purchase within 3 months upon approval with extra charges.\nFor advertising and performance related services are provided on a best endeavours basis. ADspace does not guarantee any level of reach, impressions, engagement or conversions.\nThese Terms of Service are to be read in conjunction with our full service terms available at go.adspace.me/svc-terms. In the event of any conflict, the service terms prevail.\nThis rate card is valid until {valid until}.')
on conflict (key) do nothing;

create or replace function public.rate_card_text_save(p_key text, p_value text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_row public.rate_card_text;
  v_val text := btrim(coalesce(p_value, ''));
begin
  if me.id is null or not public.allowed('services', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_row from public.rate_card_text t where t.key = p_key;
  if v_row.key is null then return jsonb_build_object('error', 'bad-key'); end if;
  if length(v_val) > 4000 then return jsonb_build_object('error', 'too-long'); end if;
  if v_val = v_row.value then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.rate_card_text t set value = v_val, updated_at = now(), updated_by = me.name where t.key = p_key;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'service.changed', 'Rate card wording', v_row.label || ' changed');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.rate_card_text_save(text, text) from public, anon;
grant execute on function public.rate_card_text_save(text, text) to authenticated;

-- Each version as it went live, whole.
create table if not exists public.rate_card_versions (
  id           uuid primary key default gen_random_uuid(),
  version      text not null unique,
  valid_until  date,
  note         text,
  snapshot     jsonb not null,
  published_at timestamptz not null default now(),
  published_by text
);
alter table public.rate_card_versions enable row level security;
do $p$
begin
  if not exists (select 1 from pg_policies where tablename = 'rate_card_versions' and policyname = 'rate_card_versions_read') then
    create policy rate_card_versions_read on public.rate_card_versions for select to authenticated
      using (public.allowed('services', 'view'));
  end if;
end $p$;

-- The draft as it stands: every line, the words, SST and the terms today.
create or replace function public.rate_card_draft()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'services', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', s.slug, 'category', s.category, 'name', s.name, 'rate', s.rate, 'unit', s.unit,
        'position', s.position, 'active', s.active, 'note', s.note, 'detail', s.detail,
        'min_months', s.min_months, 'spec', s.spec) order by s.position, s.slug)
      from public.services s), '[]'::jsonb),
    'text', coalesce((select jsonb_object_agg(t.key, t.value) from public.rate_card_text t), '{}'::jsonb),
    'settings', (select jsonb_object_agg(k, public.app_setting(k, (now() at time zone 'Asia/Kuala_Lumpur')::date))
      from unnest(array['sst_pct', 'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24']) k))
$$;
revoke all on function public.rate_card_draft() from public, anon, authenticated;

create or replace function public.rate_card_publish(p_version text, p_valid_until date, p_note text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_ver  text := btrim(coalesce(p_version, ''));
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_snap jsonb := public.rate_card_draft();
  v_last jsonb;
  v_id   uuid;
begin
  if me.id is null or not public.allowed('services', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if v_ver !~ '^[0-9]{1,3}(\.[0-9]{1,3}){1,3}$' then return jsonb_build_object('error', 'bad-version'); end if;
  if exists (select 1 from public.rate_card_versions v where v.version = v_ver) then
    return jsonb_build_object('error', 'version-taken');
  end if;
  if p_valid_until is not null and p_valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'bad-date');
  end if;
  if v_note is not null and length(v_note) > 500 then return jsonb_build_object('error', 'too-long'); end if;
  select v.snapshot into v_last from public.rate_card_versions v order by v.published_at desc limit 1;
  if v_last is not null and v_last->'services' = v_snap->'services' and v_last->'text' = v_snap->'text'
     and v_last->'settings' = v_snap->'settings' then
    return jsonb_build_object('error', 'no-change');
  end if;
  insert into public.rate_card_versions (version, valid_until, note, snapshot, published_by)
  values (v_ver, p_valid_until, v_note, v_snap, me.name)
  returning id into v_id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'service.published', 'Rate card',
          'v.' || v_ver || case when p_valid_until is not null then ' · valid until ' || public.register_day(p_valid_until) else '' end ||
          coalesce(' · ' || v_note, ''));
  return jsonb_build_object('ok', true, 'id', v_id, 'version', v_ver);
end $$;
revoke all on function public.rate_card_publish(text, date, text) from public, anon;
grant execute on function public.rate_card_publish(text, date, text) to authenticated;

-- The version a quote is priced from: the latest published.
create or replace function public.rate_card_current()
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', v.id, 'version', v.version, 'valid_until', v.valid_until,
           'published_at', v.published_at, 'published_by', v.published_by, 'snapshot', v.snapshot)
    from public.rate_card_versions v
   where public.is_team()
   order by v.published_at desc
   limit 1
$$;
revoke all on function public.rate_card_current() from public, anon;
grant execute on function public.rate_card_current() to authenticated;

-- The card live today is v.2.0.6, valid until 31 December 2026.
insert into public.rate_card_versions (version, valid_until, note, snapshot, published_by)
select '2.0.6', date '2026-12-31', 'Rate Card & Packages as issued', public.rate_card_draft(), 'ADspace'
 where not exists (select 1 from public.rate_card_versions);

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.file_deleted', 'campaign.file_hidden',
                    'campaign.file_shown', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.whatsapp', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_deleted', 'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('wa.sent', 'wa.template') then 'whatsapp'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
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
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- END OF RATE CARD VERSIONS ------------------------------------------------

select public.functions_tidy();
