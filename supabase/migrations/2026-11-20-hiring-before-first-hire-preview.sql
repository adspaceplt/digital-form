-- HIRING BEFORE THE FIRST HIRE: what the Welcome Kit's words update will do.
-- Reads and writes nothing; reports each line as `will change`, `already`,
-- or `edited in the console, left alone`.
with k as (select sections from public.welcome_kit where id = 1),
lines(section, seed, now_words) as (values
  ('Welcome', 'We would rather you start sharp than start fast.', 'ADspace would rather you start well than start fast.'),
  ('How we work', 'Zoom: Video meetings and client calls', 'Google Meet: Video meetings and client calls'),
  ('Your first weeks', 'Months 1 to 3: Your probation, with weekly check-ins and a confirmation review', 'Probation: As set in your contract, with weekly check-ins and a confirmation review'),
  ('Key policies', 'Work days: Monday to Friday; Saturday and Sunday on demand', 'Work days: Monday to Friday'))
select l.section, l.seed,
  case when exists (select 1 from k, jsonb_array_elements(k.sections) e where e->>'body' like '%' || l.seed || '%') then 'will change'
       when exists (select 1 from k, jsonb_array_elements(k.sections) e where e->>'body' like '%' || l.now_words || '%') then 'already'
       else 'edited in the console, left alone' end as outcome
  from lines l;
