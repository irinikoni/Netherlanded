-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 008_scoped_insights.sql
-- PostgreSQL 15+ (applied after 007_seed_vocab.sql).
-- Closes the GDPR data-minimisation gap on collected Tier 2 fields
-- (region, step_opened, deadline_missed, scam_checked, high_risk) and adds
-- institution-scoped category, step, region, and scam-check release tables
-- protected by the full 6-rule disclosure-control pipeline and tenant RLS/scoping.

begin;

-- 1. Register 6 institution-scoped release tables
insert into nl.release_table (table_id, title, tier, row_axis, col_axis, metric) values
  ('t1_inst_category', 'Steps started and finished, by category (institution)',
   1, 'inst_category', 'intake', 'completed / started'),
  ('t2_inst_step', 'Journey steps finished, by step (institution)',
   2, 'inst_step', 'intake', 'completed / started'),
  ('t2_inst_opened', 'Journey steps opened, by step (institution)',
   2, 'inst_step', 'intake', 'opened / started'),
  ('t2_inst_missed', 'Deadlines missed, by step (institution)',
   2, 'inst_step', 'intake', 'missed / started'),
  ('t2_inst_region', 'Steps finished, by EU/non-EU region (institution)',
   2, 'inst_region', 'intake', 'completed / started'),
  ('t2_inst_scam', 'Housing scam checks flagged high risk (institution)',
   2, 'institution', 'intake', 'high_risk / checked')
on conflict (table_id) do nothing;

-- 2. Extend dimension label formatter for institution-prefixed row keys
create or replace function nl.dim_label(p_dim text, p_key text)
returns text
language sql
stable
as $fn$
  select case p_dim
           when 'institution' then
             coalesce((select i.display_name from nl.institution i
                        where i.institution = p_key), p_key)
           when 'intake' then
             case split_part(p_key, '-', 2)
               when 'sep' then 'Sep ' || split_part(p_key, '-', 1)
               when 'feb' then 'Feb ' || split_part(p_key, '-', 1)
               else p_key
             end
           when 'step' then
             coalesce((select initcap(replace(v.step, '_', ' ')) from nl.step_vocab v
                        where v.step = p_key),
                      initcap(replace(p_key, '_', ' ')))
           when 'inst_category' then
             initcap(replace(split_part(p_key, ':', 2), '_', ' '))
           when 'inst_step' then
             coalesce((select initcap(replace(v.step, '_', ' ')) from nl.step_vocab v
                        where v.step = split_part(p_key, ':', 2)),
                      initcap(replace(split_part(p_key, ':', 2), '_', ' ')))
           when 'inst_region' then
             case split_part(p_key, ':', 2)
               when 'eu_eea' then 'EU/EEA'
               when 'non_eu' then 'Non-EU/EEA'
               else initcap(replace(split_part(p_key, ':', 2), '_', ' '))
             end
           else initcap(replace(p_key, '_', ' '))
         end;
$fn$;

-- 3. Extend nl.accumulate() so every collected Tier 1 & Tier 2 field is folded safely
create or replace function nl.accumulate()
returns bigint
language plpgsql
volatile
as $fn$
declare
  v_run   bigint;
  v_max1  bigint;
  v_max2  bigint;
  v_cells bigint;
begin
  perform pg_advisory_xact_lock(hashtext('nl.accumulate'));

  insert into nl.accumulation_run (max_t1, max_t2)
  values (0, 0)
  returning run_id into v_run;

  -- Stamp fold_run first under READ COMMITTED so late-committing rows are never skipped
  update nl.raw_t1 set fold_run = v_run where fold_run is null;
  update nl.raw_t2 set fold_run = v_run where fold_run is null;

  select coalesce(max(id), 0) into v_max1 from nl.raw_t1 where fold_run = v_run;
  select coalesce(max(id), 0) into v_max2 from nl.raw_t2 where fold_run = v_run;

  if v_max1 > 0 then
    insert into nl.t1_cohort (institution, intake, contributors, updated_at)
    select institution, intake, count(*) filter (where event = 'cohort_joined'), now()
      from nl.raw_t1
     where fold_run = v_run and event = 'cohort_joined'
     group by institution, intake
    on conflict (institution, intake) do update
       set contributors = nl.t1_cohort.contributors + excluded.contributors,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't1_institution_intake', institution, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           now()
      from nl.raw_t1
     where fold_run = v_run and event in ('step_applies', 'step_completed')
     group by institution, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't1_category_totals', category::text, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           now()
      from nl.raw_t1
     where fold_run = v_run
       and event in ('step_applies', 'step_completed')
       and category is not null
     group by category, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't1_inst_category', institution || ':' || category::text, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           now()
      from nl.raw_t1
     where fold_run = v_run
       and event in ('step_applies', 'step_completed')
       and category is not null
     group by institution, category, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't1_error_rate', institution, intake,
           count(*) filter (where event = 'technical_error'),
           count(*),
           now()
      from nl.raw_t1
     where fold_run = v_run
     group by institution, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();
  end if;

  if v_max2 > 0 then
    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't2_step_totals',
           case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'step_completed'),
           count(*) filter (where r.event = 'step_applies'),
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'step_completed')
     group by 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't2_inst_step',
           r.institution || ':' ||
             case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                  then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'step_completed'),
           count(*) filter (where r.event = 'step_applies'),
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'step_completed')
     group by r.institution, 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't2_inst_opened',
           r.institution || ':' ||
             case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                  then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'step_opened'),
           count(*) filter (where r.event = 'step_applies'),
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'step_opened')
     group by r.institution, 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't2_inst_missed',
           r.institution || ':' ||
             case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                  then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'deadline_missed'),
           count(*) filter (where r.event = 'step_applies'),
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'deadline_missed')
     group by r.institution, 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't2_inst_region', institution || ':' || region, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           now()
      from nl.raw_t2
     where fold_run = v_run
       and event in ('step_applies', 'step_completed')
     group by institution, region, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't2_inst_scam', institution, intake,
           count(*) filter (where event = 'scam_checked' and high_risk is true),
           count(*) filter (where event = 'scam_checked'),
           now()
      from nl.raw_t2
     where fold_run = v_run
       and event = 'scam_checked'
     group by institution, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           updated_at = now();

    insert into nl.t2_base (institution, intake, joined, arrived, updated_at)
    select institution, intake,
           count(*) filter (where event = 'joined'),
           count(*) filter (where event = 'arrived'),
           now()
      from nl.raw_t2
     where fold_run = v_run
       and event in ('joined', 'arrived')
     group by institution, intake
    on conflict (institution, intake) do update
       set joined = nl.t2_base.joined + excluded.joined,
           arrived = nl.t2_base.arrived + excluded.arrived,
           updated_at = now();

    insert into nl.t2_region_base (institution, region, intake, joined, updated_at)
    select institution, region, intake, count(*), now()
      from nl.raw_t2
     where fold_run = v_run
       and event = 'joined'
     group by institution, region, intake
    on conflict (institution, region, intake) do update
       set joined = nl.t2_region_base.joined + excluded.joined,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, updated_at)
    select 't2_institution_intake', t.institution, t.intake, b.arrived, b.joined, now()
      from (select distinct institution, intake
              from nl.raw_t2
             where fold_run = v_run) t
      join nl.t2_base b
        on b.institution = t.institution and b.intake = t.intake
    on conflict (table_id, row_key, col_key) do update
       set num = excluded.num,
           denom = excluded.denom,
           updated_at = now();

    insert into nl.unmapped_value (field, value, hits)
    select 't2.step', r.step, count(*)
      from nl.raw_t2 r
     where r.fold_run = v_run and r.step is not null
       and not exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
     group by r.step
    on conflict (field, value) do update
       set hits = nl.unmapped_value.hits + excluded.hits,
           last_seen = now();
  end if;

  select count(*) into v_cells from nl.accumulated_cell;

  update nl.accumulation_run
     set max_t1 = v_max1,
         max_t2 = v_max2,
         finished_at = now(),
         cells = v_cells
   where run_id = v_run;

  return v_run;
end;
$fn$;

-- 4. Update tenant-scoped JSON exporter (exact split_part match, fail-closed auth, tail capping & reason redaction)
create or replace function nl.release_json_for_institution(
  p_institution text,
  p_snapshot    bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = nl, pg_temp
as $fn$
declare
  v_claims        jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  v_has_jwt       boolean := (v_claims ? 'role') or (v_claims ? 'app_metadata');
  v_caller        text := coalesce(nullif(nullif(current_setting('role', true), 'none'), ''), session_user);
  v_is_privileged boolean := (v_caller not in ('anon', 'authenticated')) and (session_user not in ('anon', 'authenticated')) and (not v_has_jwt);
  v_app_role      text := coalesce(v_claims -> 'app_metadata' ->> 'role', '');
  v_app_inst      text := coalesce(v_claims -> 'app_metadata' ->> 'institution_id', '');
  v_allow_pooled  boolean := v_is_privileged or (v_app_role = 'super_admin');
  v_snap          bigint;
  v_tables        jsonb := '[]'::jsonb;
  v_cells         jsonb;
  v_hidden        jsonb;
  v_pub           integer := 0;
  v_hide          integer := 0;
  r               record;
begin
  if not v_is_privileged then
    if v_app_role not in ('super_admin', 'reader', 'editor')
       or (v_app_role <> 'super_admin' and v_app_inst <> p_institution) then
      raise exception 'forbidden institution scope' using errcode = '42501';
    end if;
  end if;

  if p_institution is null
     or not exists (select 1 from nl.institution i where i.institution = p_institution) then
    raise exception 'unknown institution %', p_institution using errcode = '22023';
  end if;

  -- Scoped (non-pooled) readers only ever see the latest published snapshot:
  -- comparing older releases would allow differencing across snapshots.
  if p_snapshot is not null and not v_allow_pooled
     and p_snapshot is distinct from (select max(snapshot_id) from nl.snapshot where published) then
    raise exception 'historic snapshots require pooled access' using errcode = '42501';
  end if;
  v_snap := p_snapshot;
  if v_snap is null then
    select snapshot_id into v_snap
      from nl.snapshot where published
     order by snapshot_id desc limit 1;
  end if;

  if v_snap is null
     or not exists (select 1 from nl.snapshot
                     where snapshot_id = v_snap and published) then
    return jsonb_build_object(
      'tables', '[]'::jsonb,
      'meta', jsonb_build_object(
        'snapshot_id', null,
        'built_at', null,
        'published', false,
        'state', 'empty',
        'published_cells', 0,
        'withheld', 0,
        'institution', p_institution
      )
    );
  end if;

  for r in
    select *
      from nl.release_table
     where row_axis in ('institution', 'inst_category', 'inst_step', 'inst_region')
        or v_allow_pooled
     order by tier, table_id
  loop
    select coalesce(jsonb_agg(jsonb_build_object(
             'row', row_key,
             'row_label', nl.dim_label(r.row_axis, row_key),
             'col', col_key,
             'col_label', nl.dim_label(r.col_axis, col_key),
             'num', case when v_allow_pooled then num
                         when num <= 5 or (denom - num) <= 5 or rate <= 0.10 or rate >= 0.90 or denom < 50 then null
                         else num end,
             'denom', denom,
             'rate', case when v_allow_pooled then rate
                          when num <= 5 or (denom - num) <= 5 or rate <= 0.10 or rate >= 0.90 or denom < 50 then null
                          else rate end,
             'band', case when v_allow_pooled then band
                          when num <= 5 or (denom - num) <= 5 or rate <= 0.10 or rate >= 0.90 then null
                          else band end,
             'rate_display', case
               -- published counts are rounded to the nearest 5, so a published 0 or 5 means 0..7 true
               when num <= 5 then 'fewer than 8 of ' || denom::text
               when (denom - num) <= 5 then 'all but fewer than 8 of ' || denom::text
               when rate <= 0.10 then '<= 10.0%'
               when rate >= 0.90 then '>= 90.0%'
               when denom < 50 then band::text || '%'
               else round(rate * 100)::integer::text || '%'
             end) order by row_key, col_key), '[]'::jsonb)
      into v_cells
      from nl.published_cell
     where snapshot_id = v_snap
       and table_id = r.table_id
       and (
         (r.row_axis = 'institution' and row_key = p_institution)
         or (r.row_axis in ('inst_category', 'inst_step', 'inst_region') and split_part(row_key, ':', 1) = p_institution)
         or (r.row_axis not in ('institution', 'inst_category', 'inst_step', 'inst_region'))
       );

    select coalesce(jsonb_agg(jsonb_build_object(
             'row', row_key,
             'row_label', nl.dim_label(r.row_axis, row_key),
             'col', col_key,
             'col_label', nl.dim_label(r.col_axis, col_key),
             'reason', case when v_allow_pooled then reason else null end,
             'bucket', case when v_allow_pooled then bucket else null end) order by row_key, col_key), '[]'::jsonb)
      into v_hidden
      from nl.suppressed_cell
     where snapshot_id = v_snap
       and table_id = r.table_id
       and (
         (r.row_axis = 'institution' and row_key = p_institution)
         or (r.row_axis in ('inst_category', 'inst_step', 'inst_region') and split_part(row_key, ':', 1) = p_institution)
         or (r.row_axis not in ('institution', 'inst_category', 'inst_step', 'inst_region'))
       );

    v_pub  := v_pub  + jsonb_array_length(v_cells);
    v_hide := v_hide + jsonb_array_length(v_hidden);

    v_tables := v_tables || jsonb_build_array(jsonb_build_object(
      'table_id', r.table_id,
      'title', r.title,
      'tier', r.tier,
      'row_axis', r.row_axis,
      'col_axis', r.col_axis,
      'metric', r.metric,
      'cells', v_cells,
      'withheld', v_hidden,
      'published_count', jsonb_array_length(v_cells),
      'withheld_count', jsonb_array_length(v_hidden)
    ));
  end loop;

  return jsonb_build_object(
    'tables', v_tables,
    'meta', jsonb_build_object(
      'snapshot_id', v_snap,
      'built_at', (select built_at from nl.snapshot where snapshot_id = v_snap),
      'published', true,
      'state', case when v_pub = 0 then 'withheld' else 'ok' end,
      'published_cells', v_pub,
      'withheld', v_hide,
      'institution', p_institution,
      'note', 'Scoped disclosure-controlled aggregates only. No individual, no account, no link between tier 1 and tier 2.'
    )
  );
end;
$fn$;

revoke all on function nl.accumulate() from public;
revoke all on function nl.release_json_for_institution(text, bigint) from public;

do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function nl.accumulate(), nl.release_json_for_institution(text, bigint) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function nl.release_json_for_institution(text, bigint) to authenticated';
    execute 'revoke execute on function nl.accumulate() from authenticated';
  end if;
end
$grants$;

commit;
