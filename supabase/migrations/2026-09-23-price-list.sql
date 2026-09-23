-- The rate card, 2026-09-23 (v2.0.5, expiring 2026-12-31).
--
-- The price list handed over on 2026-09-23, against the card seeded into
-- this database from v2.0.2. Every rate, every package fee, and the KOC and
-- KOL programmes are unchanged, so no line's price moves. What moves is
-- wording, and two lines are new:
--
--   Account management, four lines: the unit is `Per month`. They were seeded
--   with the content units printed beside them on the old card (`Per post`,
--   `Per GIF`, `Per set`, `Per video, up to 30 seconds`) and flagged as wrong
--   the day they were seeded. The new card states what is included, so a
--   line with no inclusions yet takes them.
--   Account verifications, two lines: the new card states what is included
--   (the documents, one submission, the statutory documents the client
--   provides), and rednote Professional's platform fee is RMB 600.
--   Packages D, E and F: the covered advertising budget is RM 2,000, RM 4,000
--   and RM 8,000 a month (it read RM 4,000, RM 8,000 and nothing).
--   KOL management fee: the fee is tiered by talent fee, 18% down to 12% with
--   a minimum at each tier, and three or more KOLs are quoted as one.
--   Working files: `Per unit / asset`. Raw footage: `Per scene / shoot`.
--   Two new lines under Digital advertising: Meta advertising at RM 900 a
--   month for an ad budget up to RM 2,000, and RM 1,400 a month up to
--   RM 4,000, the budget billed separately.
--
-- The term commitment on the new card (one to three months +25%, four and
-- five +15%, twelve and more 5% off, twenty-four and more 10% off) is a rule
-- the pages hold in `js/money.js`, prefilled on a service line as a
-- percentage the person may change; nothing in this database carries it, so
-- nothing here touches it.
--
-- GUARDED, LINE BY LINE. The card is the team's: they edit it on the Services
-- page, and a correction made there outranks a list. So each update touches a
-- line only while it still holds the value the seed gave it, and the two new
-- lines are `on conflict (slug) do nothing`. Run twice, the second run changes
-- nothing. A line the team has deleted from the card is not put back.
--
-- PREVIEW FIRST: supabase/migrations/2026-09-23-price-list-preview.sql reads
-- and writes nothing and lists each line named here with its value now, the
-- value it would take, and whether it will change. The last statement of
-- this file lists the same lines after the run, which is what the SQL editor
-- shows when the whole file is run.
--
-- Rollback, the same guarded way (a line edited since is left alone):
--   update public.services set unit = 'Per post' where slug = 'mgmt-meta' and unit = 'Per month';
--   update public.services set unit = 'Per GIF' where slug = 'mgmt-tiktok' and unit = 'Per month';
--   update public.services set unit = 'Per set' where slug = 'mgmt-xhs' and unit = 'Per month';
--   update public.services set unit = 'Per video, up to 30 seconds' where slug = 'mgmt-linkedin' and unit = 'Per month';
--   update public.services set detail = null where slug like 'mgmt-%'
--     and detail = E'Dedicated account management and content posting\nProfessional copywriting for every planned deliverable, optional\nEnquiries passed to the client';
--   update public.services set detail = 'Meta subscription fee billed separately' where slug = 'verify-meta'
--     and detail like E'Preparation of the documents%Meta subscription fee billed separately';
--   update public.services set unit = 'Per account, RM 450 platform fee included', detail = 'RM 450 platform fee included'
--     where slug = 'verify-xhs' and unit = 'Per account, RMB 600 platform fee included';
--   update public.services set detail = replace(detail, 'up to RM 2,000 each month', 'up to RM 4,000 each month') where slug = 'pkg-d';
--   update public.services set detail = replace(detail, 'up to RM 4,000 each month', 'up to RM 8,000 each month') where slug = 'pkg-e';
--   update public.services set detail = replace(detail, E'Advertising budget up to RM 8,000 each month\n', '') where slug = 'pkg-f';
--   update public.services set detail = split_part(detail, E'\nManagement fee per talent', 1) where slug = 'kol-mgmt';
--   update public.services set unit = 'Per asset' where slug = 'working-files' and unit = 'Per unit / asset';
--   update public.services set unit = 'Per shoot' where slug = 'raw-footage' and unit = 'Per scene / shoot';
--   delete from public.services where slug in ('ads-meta-2k', 'ads-meta-4k')
--     and not exists (select 1 from public.client_services cs where cs.service_slug = public.services.slug);

-- Account management: monthly, and what the month includes.
update public.services set unit = 'Per month'
 where slug = 'mgmt-meta' and unit = 'Per post';
update public.services set unit = 'Per month'
 where slug = 'mgmt-tiktok' and unit = 'Per GIF';
update public.services set unit = 'Per month'
 where slug = 'mgmt-xhs' and unit = 'Per set';
update public.services set unit = 'Per month'
 where slug = 'mgmt-linkedin' and unit = 'Per video, up to 30 seconds';
update public.services
   set detail = E'Dedicated account management and content posting\nProfessional copywriting for every planned deliverable, optional\nEnquiries passed to the client'
 where slug in ('mgmt-meta', 'mgmt-tiktok', 'mgmt-xhs', 'mgmt-linkedin') and detail is null;

-- Account verifications: what is included, and the rednote fee in RMB.
update public.services
   set detail = E'Preparation of the documents the platform asks for\nOne submission of the application to the platform\nStatutory documents provided by the client, such as the SSM certificate and Section 14\nMeta subscription fee billed separately'
 where slug = 'verify-meta' and detail = 'Meta subscription fee billed separately';
update public.services set unit = 'Per account, RMB 600 platform fee included'
 where slug = 'verify-xhs' and unit = 'Per account, RM 450 platform fee included';
update public.services
   set detail = E'Preparation of the documents the platform asks for\nOne submission of the application to the platform\nStatutory documents provided by the client, such as the SSM certificate and Section 14\nRMB 600 platform fee included'
 where slug = 'verify-xhs' and detail = 'RM 450 platform fee included';

-- Packages with ads: the covered budget each package carries.
update public.services
   set detail = replace(detail, 'Advertising budget up to RM 4,000 each month', 'Advertising budget up to RM 2,000 each month')
 where slug = 'pkg-d' and detail like '%Advertising budget up to RM 4,000 each month%';
update public.services
   set detail = replace(detail, 'Advertising budget up to RM 8,000 each month', 'Advertising budget up to RM 4,000 each month')
 where slug = 'pkg-e' and detail like '%Advertising budget up to RM 8,000 each month%';
update public.services
   set detail = replace(detail,
        E'10 contents each month: 4 graphics and 6 reels up to 60s\n',
        E'10 contents each month: 4 graphics and 6 reels up to 60s\nAdvertising budget up to RM 8,000 each month\n')
 where slug = 'pkg-f' and detail like E'%10 contents each month: 4 graphics and 6 reels up to 60s\n%'
   and detail not like '%Advertising budget%';

-- KOL management fee: the tiers, appended to the inclusions the seed gave.
update public.services
   set detail = detail || E'\nManagement fee per talent: 18% up to RM 3,000 (minimum RM 500), 16% from RM 3,001 to RM 15,000 (minimum RM 800), 14% from RM 15,001 to RM 30,000 (minimum RM 2,500), 12% above RM 30,000 (minimum RM 4,000)\nThree or more KOLs in one campaign are quoted separately with one consolidated management fee'
 where slug = 'kol-mgmt'
   and detail = E'Talent fee passed through at the creator''s own rate, no markup\nCreator sourcing and shortlisting\nRate negotiation and quotation handling\nCampaign briefing and content direction\nScheduling and posting coordination\nContent review and revision cycles\nPublication verification and reporting';

-- File release.
update public.services set unit = 'Per unit / asset'
 where slug = 'working-files' and unit = 'Per asset';
update public.services set unit = 'Per scene / shoot'
 where slug = 'raw-footage' and unit = 'Per shoot';

/* The two new lines. Inserted only into a card that has neither, and only
   while the card exists at all: a database whose card was never seeded is
   seeded whole by supabase/schema.sql, and a list of two here would put a
   partial card in front of it. */
insert into public.services (slug, category, name, rate, unit, position, detail)
select v.slug, v.category, v.name, v.rate, v.unit, v.position, v.detail
  from (values
    ('ads-meta-2k', 'Digital advertising', 'Meta advertising · ad budget up to RM 2,000', 900,  'Per month, ad budget billed separately', 35,
     E'Full advertising campaign setup and ongoing management\nWeekly advertising performance snapshot\nComprehensive monthly performance report\nAdvertising budget is billed separately from the service fee'),
    ('ads-meta-4k', 'Digital advertising', 'Meta advertising · ad budget up to RM 4,000', 1400, 'Per month, ad budget billed separately', 36,
     E'Full advertising campaign setup and ongoing management\nWeekly advertising performance snapshot\nComprehensive monthly performance report\nAdvertising budget is billed separately from the service fee')
  ) as v(slug, category, name, rate, unit, position, detail)
 where exists (select 1 from public.services)
on conflict (slug) do nothing;

-- What the lines named above hold now.
select slug, category, name, rate, unit, detail, active
  from public.services
 where slug in ('mgmt-meta', 'mgmt-tiktok', 'mgmt-xhs', 'mgmt-linkedin',
                'verify-meta', 'verify-xhs', 'pkg-d', 'pkg-e', 'pkg-f', 'kol-mgmt',
                'working-files', 'raw-footage', 'ads-meta-2k', 'ads-meta-4k')
 order by position;
