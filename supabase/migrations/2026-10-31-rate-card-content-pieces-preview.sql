-- The rate card, 2026-10-31: what the content pieces migration would change.
-- READ ONLY. Run this first, in the SQL editor, before
-- supabase/migrations/2026-10-31-rate-card-content-pieces.sql.
--
-- One row per package and field, with the value the line holds now (a long
-- inclusions text by its first seventy characters, the line that changes
-- where there is one), what it would take, and the outcome: `will change`
-- where the line still holds the seed's words, `already` where it holds the
-- new words, and `edited in the console, left alone` where somebody has
-- corrected it by hand since, because the card is the team's and a hand
-- correction outranks a list.

with want (slug, old_name, new_name) as (values
  ('pkg-a', 'Package A · 1 platform · 2 contents', 'Package A · 1 platform · 2 content pieces'),
  ('pkg-b', 'Package B · 2 platforms · 4 contents', 'Package B · 2 platforms · 4 content pieces'),
  ('pkg-c', 'Package C · 3 platforms · 8 contents', 'Package C · 3 platforms · 8 content pieces'),
  ('pkg-d', 'Package D · 1 platform · 4 contents · ads', 'Package D · 1 platform · 4 content pieces · ads'),
  ('pkg-e', 'Package E · 2 platforms · 6 contents · ads', 'Package E · 2 platforms · 6 content pieces · ads'),
  ('pkg-f', 'Package F · 3 platforms · 10 contents · ads', 'Package F · 3 platforms · 10 content pieces · ads')
)
select w.slug, 'name' as field, s.name as value_now, w.new_name as new_value,
       case when s.slug is null then 'row not on this card'
            when s.name = w.old_name then 'will change'
            when s.name = w.new_name then 'already'
            else 'edited in the console, left alone' end as outcome
  from want w
  left join public.services s on s.slug = w.slug

union all

select w.slug, 'detail',
       coalesce(substring(s.detail from '[0-9]+ content[^\n]*'), left(replace(s.detail, E'\n', ' / '), 70)),
       coalesce(regexp_replace(substring(s.detail from '[0-9]+ contents each month:[^\n]*'),
                               '^([0-9]+) contents each month:', '\1 content pieces each month:'),
                substring(s.detail from '[0-9]+ content pieces each month:[^\n]*')),
       case when s.slug is null then 'row not on this card'
            when s.detail is null then 'no inclusions, nothing to change'
            when s.detail ~ '(^|\n)[0-9]+ contents each month:' then 'will change'
            when s.detail ~ '(^|\n)[0-9]+ content pieces each month:' then 'already'
            else 'edited in the console, left alone' end
  from want w
  left join public.services s on s.slug = w.slug
order by 1, 2;
