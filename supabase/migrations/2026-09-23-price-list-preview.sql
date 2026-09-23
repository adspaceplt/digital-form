-- The rate card, 2026-09-23: what the price list migration would change.
-- READ ONLY. Run this first, in the SQL editor, before
-- supabase/migrations/2026-09-23-price-list.sql.
--
-- One row per rate card line that migration names, with the value the line
-- holds now, what it would take, and the outcome: `will change` where the
-- line still holds the value the seed gave it, `already` where it holds the
-- new value, and `edited in the console, left alone` where somebody has
-- corrected it by hand since, because the card is the team's and a hand
-- correction outranks a list. The two new lines read `will be added` or
-- `already`. A long inclusions text is shown by its first seventy characters.

-- Units and short inclusions, matched whole.
with want (slug, field, old_value, new_value) as (values
  ('mgmt-meta',     'unit',   'Per post',                                   'Per month'),
  ('mgmt-tiktok',   'unit',   'Per GIF',                                    'Per month'),
  ('mgmt-xhs',      'unit',   'Per set',                                    'Per month'),
  ('mgmt-linkedin', 'unit',   'Per video, up to 30 seconds',                'Per month'),
  ('verify-xhs',    'unit',   'Per account, RM 450 platform fee included',  'Per account, RMB 600 platform fee included'),
  ('verify-xhs',    'detail', 'RM 450 platform fee included',               'Preparation of the documents the platform asks for … RMB 600 platform fee included'),
  ('verify-meta',   'detail', 'Meta subscription fee billed separately',    'Preparation of the documents the platform asks for … Meta subscription fee billed separately'),
  ('working-files', 'unit',   'Per asset',                                  'Per unit / asset'),
  ('raw-footage',   'unit',   'Per shoot',                                  'Per scene / shoot')
),
now_ (slug, field, value_now) as (
  select slug, 'unit',   unit   from public.services
  union all
  select slug, 'detail', detail from public.services
)
select w.slug, w.field, left(n.value_now, 70) as value_now, w.new_value,
       case when not exists (select 1 from public.services s where s.slug = w.slug) then 'row not on this card'
            when n.value_now is not distinct from w.old_value then 'will change'
            when w.field = 'detail' and n.value_now like 'Preparation of the documents%' then 'already'
            when n.value_now is not distinct from w.new_value then 'already'
            else 'edited in the console, left alone' end as outcome
  from want w
  left join now_ n on n.slug = w.slug and n.field = w.field

union all

-- Inclusions that gain or change one line, matched by the line.
select v.slug, 'detail', left(s.detail, 70), v.new_line,
       case when s.slug is null then 'row not on this card'
            when s.detail is null and v.slug like 'mgmt-%' then 'will change'
            when s.detail like v.has_new then 'already'
            when s.detail like v.has_old then 'will change'
            else 'edited in the console, left alone' end
  from (values
    ('mgmt-meta',     '%', '%Enquiries passed to the client%', 'the three inclusions'),
    ('mgmt-tiktok',   '%', '%Enquiries passed to the client%', 'the three inclusions'),
    ('mgmt-xhs',      '%', '%Enquiries passed to the client%', 'the three inclusions'),
    ('mgmt-linkedin', '%', '%Enquiries passed to the client%', 'the three inclusions'),
    ('pkg-d', '%Advertising budget up to RM 4,000 each month%', '%Advertising budget up to RM 2,000 each month%', 'Advertising budget up to RM 2,000 each month'),
    ('pkg-e', '%Advertising budget up to RM 8,000 each month%', '%Advertising budget up to RM 4,000 each month%', 'Advertising budget up to RM 4,000 each month'),
    ('pkg-f', E'%10 contents each month: 4 graphics and 6 reels up to 60s\n%', '%Advertising budget up to RM 8,000 each month%', 'Advertising budget up to RM 8,000 each month'),
    ('kol-mgmt', E'Talent fee passed through at the creator''s own rate, no markup\nCreator sourcing%', '%Management fee per talent%', 'the fee tiers, 18% down to 12%')
  ) as v(slug, has_old, has_new, new_line)
  left join public.services s on s.slug = v.slug

union all

-- The two new lines.
select v.slug, 'row', s.name, v.name,
       case when s.slug is null then 'will be added' else 'already' end
  from (values
    ('ads-meta-2k', 'Meta advertising · ad budget up to RM 2,000, RM 900 a month'),
    ('ads-meta-4k', 'Meta advertising · ad budget up to RM 4,000, RM 1,400 a month')
  ) as v(slug, name)
  left join public.services s on s.slug = v.slug
order by 1, 2;
