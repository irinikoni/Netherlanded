-- GENERATED from db/007_seed_vocab.sql by tools/sync_supabase.py. Edit the source, not this file.
-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 007_seed_vocab.sql
-- Generated directly from netherlanded-app.html embedded content.
-- Seeds all 29 participating institutions and 19 journey steps.

insert into nl.institution (institution, display_name, active) values
  ('eur', 'Erasmus University Rotterdam', true),
  ('fontys', 'Fontys University of Applied Sciences', true),
  ('fontys-tilburg', 'Fontys, Tilburg campus', true),
  ('fontys-venlo', 'Fontys, Venlo campus', true),
  ('hanze', 'Hanze University of Applied Sciences', true),
  ('hr', 'Rotterdam University of Applied Sciences (Hogeschool Rotterdam)', true),
  ('hu', 'HU University of Applied Sciences Utrecht', true),
  ('hva', 'Amsterdam University of Applied Sciences (HvA)', true),
  ('leiden', 'Leiden University', true),
  ('leiden-th', 'Leiden University - Campus The Hague', true),
  ('rug', 'University of Groningen', true),
  ('rug-leeuwarden', 'University of Groningen, Campus Fryslân', true),
  ('saxion', 'Saxion University of Applied Sciences', true),
  ('saxion-apeldoorn', 'Saxion, Apeldoorn campus', true),
  ('saxion-deventer', 'Saxion, Deventer campus', true),
  ('thuas', 'The Hague University of Applied Sciences', true),
  ('thuas-delft', 'THUAS, Delft campus', true),
  ('thuas-zoetermeer', 'THUAS, Zoetermeer campus', true),
  ('tud', 'Delft University of Technology', true),
  ('tue', 'Eindhoven University of Technology (TU/e)', true),
  ('um', 'Maastricht University', true),
  ('um-venlo', 'Maastricht University, Campus Venlo', true),
  ('utwente', 'University of Twente', true),
  ('uu', 'Utrecht University', true),
  ('uva', 'University of Amsterdam', true),
  ('vu', 'Vrije Universiteit Amsterdam', true),
  ('zuyd', 'Zuyd University of Applied Sciences', true),
  ('zuyd-heerlen', 'Zuyd, Heerlen location', true),
  ('zuyd-sittard', 'Zuyd, Sittard location', true)
on conflict (institution) do nothing;

insert into nl.step_vocab (step, ord, is_known) values
  ('residence_permit', 10, true),
  ('find_housing', 20, true),
  ('check_insurance', 30, true),
  ('open_bank', 40, true),
  ('book_registration', 50, true),
  ('plan_finances', 60, true),
  ('register_municipality', 70, true),
  ('collect_permit', 75, true),
  ('add_bsn_bank', 80, true),
  ('apply_digid', 90, true),
  ('register_gp', 100, true),
  ('tb_test', 105, true),
  ('find_job', 110, true),
  ('dutch_insurance', 120, true),
  ('student_finance', 130, true),
  ('intro_week', 150, true),
  ('join_community', 160, true),
  ('cak_letter', 165, true),
  ('wellbeing_checkin', 170, true)
on conflict (step) do nothing;
