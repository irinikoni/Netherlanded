-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 011_security_hardening.sql
-- PostgreSQL 15+ (applied after 010_function_search_path.sql).
-- Hardens gateway enforcement on stats/editor RPCs, caps nl.unmapped_value,
-- tightens nl_content constraints and editor ownership/concurrency guards,
-- sets security_invoker on nl.retention_status, deactivates sub-campus ingest,
-- and schedules pg_cron jobs when available.

begin;

-- 1. Set security_invoker on nl.retention_status (Supabase linter 0010)
alter view nl.retention_status set (security_invoker = true);

-- 2. Roll-up enforcement: reject raw telemetry using sub-campus institution IDs
update nl.institution
   set active = false
 where institution in (
   'fontys-tilburg', 'fontys-venlo', 'leiden-th', 'rug-leeuwarden',
   'saxion-apeldoorn', 'saxion-deventer', 'thuas-delft', 'thuas-zoetermeer',
   'um-venlo', 'zuyd-heerlen', 'zuyd-sittard'
 );

-- 3. Remove per-call DELETE scan from nl.check_ingest_rate_limit (purge_raw() cleans expired buckets)
create or replace function nl.check_ingest_rate_limit(
  p_tier         smallint,
  p_max_per_hour integer,
  p_weight       integer default 1
)
returns boolean
language plpgsql
volatile
security definer
set search_path = nl, pg_temp
as $fn$
declare
  v_hour    timestamptz := date_trunc('hour', now());
  v_secret  text := coalesce(
    nullif(current_setting('nl.rate_limit_secret', true), ''),
    current_database() || ':' || pg_postmaster_start_time()::text
  );
  v_hash    text := encode(
    pg_catalog.sha256(convert_to('global::' || v_secret || '::' || v_hour::text, 'UTF8')),
    'hex'
  );
  v_cnt     integer;
  v_cap     integer := p_max_per_hour;
  v_weight  integer := greatest(1, least(coalesce(p_weight, 1), 100));
begin
  insert into nl.ingest_rate_limits (bucket_hour, client_hash, tier, req_count)
  values (v_hour, v_hash, p_tier, v_weight)
  on conflict (bucket_hour, client_hash, tier)
  do update set req_count = nl.ingest_rate_limits.req_count + v_weight
  returning req_count into v_cnt;

  return v_cnt <= v_cap;
end;
$fn$;

-- 4. Cap nl.unmapped_value cardinality at 500 rows in nl.accumulate()
create or replace function nl.accumulate()
returns bigint
language plpgsql
volatile
set search_path = nl, pg_temp
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

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't1_institution_intake', institution, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           coalesce(sum(rkey) filter (where event = 'step_completed'), 0) % 252,
           coalesce(sum(rkey) filter (where event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t1
     where fold_run = v_run and event in ('step_applies', 'step_completed')
     group by institution, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't1_category_totals', category::text, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           coalesce(sum(rkey) filter (where event = 'step_completed'), 0) % 252,
           coalesce(sum(rkey) filter (where event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t1
     where fold_run = v_run
       and event in ('step_applies', 'step_completed')
       and category is not null
     group by category, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't1_inst_category', institution || ':' || category::text, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           coalesce(sum(rkey) filter (where event = 'step_completed'), 0) % 252,
           coalesce(sum(rkey) filter (where event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t1
     where fold_run = v_run
       and event in ('step_applies', 'step_completed')
       and category is not null
     group by institution, category, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't1_error_rate', institution, intake,
           count(*) filter (where event = 'technical_error'),
           count(*),
           coalesce(sum(rkey) filter (where event = 'technical_error'), 0) % 252,
           coalesce(sum(rkey), 0) % 252,
           now()
      from nl.raw_t1
     where fold_run = v_run
     group by institution, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();
  end if;

  if v_max2 > 0 then
    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't2_step_totals',
           case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'step_completed'),
           count(*) filter (where r.event = 'step_applies'),
           coalesce(sum(r.rkey) filter (where r.event = 'step_completed'), 0) % 252,
           coalesce(sum(r.rkey) filter (where r.event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'step_completed')
     group by 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't2_inst_step',
           r.institution || ':' ||
             case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                  then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'step_completed'),
           count(*) filter (where r.event = 'step_applies'),
           coalesce(sum(r.rkey) filter (where r.event = 'step_completed'), 0) % 252,
           coalesce(sum(r.rkey) filter (where r.event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'step_completed')
     group by r.institution, 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't2_inst_opened',
           r.institution || ':' ||
             case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                  then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'step_opened'),
           count(*) filter (where r.event = 'step_applies'),
           coalesce(sum(r.rkey) filter (where r.event = 'step_opened'), 0) % 252,
           coalesce(sum(r.rkey) filter (where r.event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'step_opened')
     group by r.institution, 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't2_inst_missed',
           r.institution || ':' ||
             case when exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
                  then r.step else 'other' end,
           r.intake,
           count(*) filter (where r.event = 'deadline_missed'),
           count(*) filter (where r.event = 'step_applies'),
           coalesce(sum(r.rkey) filter (where r.event = 'deadline_missed'), 0) % 252,
           coalesce(sum(r.rkey) filter (where r.event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t2 r
     where r.fold_run = v_run
       and r.event in ('step_applies', 'deadline_missed')
     group by r.institution, 2, r.intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't2_inst_region', institution || ':' || region, intake,
           count(*) filter (where event = 'step_completed'),
           count(*) filter (where event = 'step_applies'),
           coalesce(sum(rkey) filter (where event = 'step_completed'), 0) % 252,
           coalesce(sum(rkey) filter (where event = 'step_applies'), 0) % 252,
           now()
      from nl.raw_t2
     where fold_run = v_run
       and event in ('step_applies', 'step_completed')
     group by institution, region, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't2_inst_scam', institution, intake,
           count(*) filter (where event = 'scam_checked' and high_risk is true),
           count(*) filter (where event = 'scam_checked'),
           coalesce(sum(rkey) filter (where event = 'scam_checked' and high_risk is true), 0) % 252,
           coalesce(sum(rkey) filter (where event = 'scam_checked'), 0) % 252,
           now()
      from nl.raw_t2
     where fold_run = v_run
       and event = 'scam_checked'
     group by institution, intake
    on conflict (table_id, row_key, col_key) do update
       set num = nl.accumulated_cell.num + excluded.num,
           denom = nl.accumulated_cell.denom + excluded.denom,
           num_key = (nl.accumulated_cell.num_key + excluded.num_key) % 252,
           denom_key = (nl.accumulated_cell.denom_key + excluded.denom_key) % 252,
           updated_at = now();

    insert into nl.t2_base (institution, intake, joined, arrived, joined_key, arrived_key, updated_at)
    select institution, intake,
           count(*) filter (where event = 'joined'),
           count(*) filter (where event = 'arrived'),
           coalesce(sum(rkey) filter (where event = 'joined'), 0) % 252,
           coalesce(sum(rkey) filter (where event = 'arrived'), 0) % 252,
           now()
      from nl.raw_t2
     where fold_run = v_run
       and event in ('joined', 'arrived')
     group by institution, intake
    on conflict (institution, intake) do update
       set joined = nl.t2_base.joined + excluded.joined,
           arrived = nl.t2_base.arrived + excluded.arrived,
           joined_key = (nl.t2_base.joined_key + excluded.joined_key) % 252,
           arrived_key = (nl.t2_base.arrived_key + excluded.arrived_key) % 252,
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

    insert into nl.accumulated_cell (table_id, row_key, col_key, num, denom, num_key, denom_key, updated_at)
    select 't2_institution_intake', t.institution, t.intake, b.arrived, b.joined, b.arrived_key, b.joined_key, now()
      from (select distinct institution, intake
              from nl.raw_t2
             where fold_run = v_run) t
      join nl.t2_base b
        on b.institution = t.institution and b.intake = t.intake
    on conflict (table_id, row_key, col_key) do update
       set num = excluded.num,
           denom = excluded.denom,
           num_key = excluded.num_key,
           denom_key = excluded.denom_key,
           updated_at = now();

    update nl.unmapped_value uv
       set hits = uv.hits + s.cnt,
           last_seen = now()
      from (select r.step as val, count(*) as cnt
              from nl.raw_t2 r
             where r.fold_run = v_run and r.step is not null
               and not exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
             group by r.step) s
     where uv.field = 't2.step'
       and uv.value = s.val;

    insert into nl.unmapped_value (field, value, hits)
    select 't2.step', r.step, count(*)
      from nl.raw_t2 r
     where r.fold_run = v_run and r.step is not null
       and not exists (select 1 from nl.step_vocab v where v.step = r.step and v.is_known)
       and not exists (select 1 from nl.unmapped_value uv where uv.field = 't2.step' and uv.value = r.step)
     group by r.step
     order by count(*) desc, r.step
     limit greatest(0, 500 - (select count(*) from nl.unmapped_value))
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

-- 5. Enforce gateway secret and service_role/authenticator exclusion on stats RPC
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
  v_is_privileged boolean := (v_caller not in ('anon', 'authenticated', 'service_role', 'authenticator'))
                             and (session_user not in ('anon', 'authenticated', 'service_role', 'authenticator'))
                             and (not v_has_jwt);
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
    perform nl.check_ingest_gateway();
    if v_app_role not in ('super_admin', 'reader', 'editor')
       or (v_app_role <> 'super_admin' and v_app_inst <> p_institution) then
      raise exception 'forbidden institution scope' using errcode = '42501';
    end if;
  end if;

  if p_institution is null
     or not exists (select 1 from nl.institution i where i.institution = p_institution) then
    raise exception 'unknown institution %', p_institution using errcode = '22023';
  end if;

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
               when num <= 5 then 'fewer than 12 of ' || denom::text
               when (denom - num) <= 5 then 'almost all of ' || denom::text
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

-- 6. Tighten nl_content table constraints (length bounds, enum checks, no markup in facts)
alter table nl_content.staff_change drop constraint if exists staff_change_reason_check;
alter table nl_content.staff_change add constraint staff_change_reason_check
  check (length(trim(reason)) between 3 and 500);

alter table nl_content.service drop constraint if exists service_accepting_students_check;
alter table nl_content.service add constraint service_accepting_students_check
  check (accepting_students is null or accepting_students in ('yes', 'limited', 'no'));

alter table nl_content.service drop constraint if exists service_related_step_id_check;
alter table nl_content.service add constraint service_related_step_id_check
  check (related_step_id is null or related_step_id ~ '^[a-z0-9_-]{2,64}$');

alter table nl_content.service drop constraint if exists service_source_id_check;
alter table nl_content.service add constraint service_source_id_check
  check (source_id is null or source_id ~ '^[a-z0-9_-]{2,64}$');

alter table nl_content.fact drop constraint if exists fact_unit_check;
alter table nl_content.fact add constraint fact_unit_check
  check (unit is null or (length(trim(unit)) between 1 and 64 and unit !~ '[<>]'));

alter table nl_content.fact drop constraint if exists fact_step_id_check;
alter table nl_content.fact add constraint fact_step_id_check
  check (step_id is null or step_id ~ '^[a-z0-9_-]{2,64}$');

alter table nl_content.fact drop constraint if exists fact_no_markup_check;
alter table nl_content.fact add constraint fact_no_markup_check
  check (label !~ '[<>]' and value !~ '[<>]');

-- 7. Harden nl_content._caller_context() and all 5 editor RPCs
create or replace function nl_content._caller_context()
returns table (
  is_privileged  boolean,
  role           text,
  institution_id text,
  actor_sub      text
)
language plpgsql
stable
set search_path = nl_content, public, pg_temp
as $fn$
declare
  v_claims  jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
  v_has_jwt boolean := (v_claims ? 'role') or (v_claims ? 'app_metadata') or (v_claims ? 'sub');
  v_caller  text := coalesce(nullif(nullif(current_setting('role', true), 'none'), ''), session_user);
  v_priv    boolean := (v_caller not in ('anon', 'authenticated', 'service_role', 'authenticator'))
                       and (session_user not in ('anon', 'authenticated', 'service_role', 'authenticator'))
                       and (not v_has_jwt);
begin
  is_privileged := v_priv;
  if v_priv then
    role := 'super_admin';
    institution_id := '';
    actor_sub := session_user;
  else
    role := coalesce(v_claims -> 'app_metadata' ->> 'role', '');
    institution_id := coalesce(v_claims -> 'app_metadata' ->> 'institution_id', '');
    actor_sub := coalesce(nullif(v_claims ->> 'sub', ''), 'unknown-staff');
  end if;
  return next;
end;
$fn$;

create or replace function nl_content.editor_list(p_institution text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = nl_content, public, pg_temp
as $fn$
declare
  v_ctx            record;
  v_target_inst    text;
  v_campus_city    jsonb;
  v_editable_city  jsonb;
  v_shared_city    jsonb;
  v_services       jsonb;
  v_step_local     jsonb;
  v_facts          jsonb;
  v_changes        jsonb;
  v_stale_count    integer;
begin
  select * into v_ctx from nl_content._caller_context();
  if not v_ctx.is_privileged then
    perform nl.check_ingest_gateway();
    if v_ctx.role not in ('super_admin', 'editor') then
      raise exception 'forbidden editor role' using errcode = '42501';
    end if;
    if v_ctx.role <> 'super_admin' and (v_ctx.institution_id = '' or (p_institution is not null and p_institution <> v_ctx.institution_id)) then
      raise exception 'forbidden institution scope' using errcode = '42501';
    end if;
  end if;

  v_target_inst := coalesce(nullif(trim(p_institution), ''), nullif(v_ctx.institution_id, ''));

  select coalesce(jsonb_agg(c.city_id order by c.city_id), '[]'::jsonb)
    into v_campus_city
    from (
      select distinct ic.city_id
        from public.institution_campuses ic
       where v_ctx.role = 'super_admin'
          or ic.institution_id = v_target_inst
    ) c;

  select coalesce(jsonb_agg(c.city_id order by c.city_id), '[]'::jsonb)
    into v_editable_city
    from (
      select distinct ic.city_id
        from public.institution_campuses ic
       where v_ctx.role = 'super_admin'
          or (ic.institution_id = v_target_inst and public.can_edit_city(ic.city_id))
    ) c;

  select coalesce(jsonb_agg(c.city_id order by c.city_id), '[]'::jsonb)
    into v_shared_city
    from (
      select ic.city_id
        from public.institution_campuses ic
       group by ic.city_id
      having count(distinct ic.institution_id) > 1
    ) c;

  select coalesce(jsonb_agg(
           to_jsonb(s) || jsonb_build_object(
             'editable',
             coalesce(
               v_ctx.role = 'super_admin'
               or s.for_institution_id = v_ctx.institution_id
               or (s.for_institution_id is null and public.can_edit_city(s.municipality_id) and public.can_edit_city(s.city_id)),
               false
             )
           )
           order by s.city_id, s.service_type, s.name
         ), '[]'::jsonb)
    into v_services
    from nl_content.service s
   where v_ctx.role = 'super_admin'
      or s.for_institution_id = v_ctx.institution_id
      or (s.for_institution_id is null and exists (
            select 1 from public.institution_campuses ic
             where ic.institution_id = v_ctx.institution_id
               and ic.city_id = s.municipality_id
         ));

  select coalesce(jsonb_agg(
           to_jsonb(sl) || jsonb_build_object(
             'editable',
             (v_ctx.role = 'super_admin'
              or sl.for_institution_id = v_ctx.institution_id
              or (sl.for_institution_id = '' and public.can_edit_city(sl.municipality_id)))
           )
           order by sl.municipality_id, sl.step_id, sl.for_institution_id
         ), '[]'::jsonb)
    into v_step_local
    from nl_content.step_local sl
   where v_ctx.role = 'super_admin'
      or sl.for_institution_id = v_ctx.institution_id
      or (sl.for_institution_id = '' and exists (
            select 1 from public.institution_campuses ic
             where ic.institution_id = v_ctx.institution_id
               and ic.city_id = sl.municipality_id
         ));

  select coalesce(jsonb_agg(
           to_jsonb(f) || jsonb_build_object('editable', (v_ctx.role = 'super_admin'))
           order by f.fact_key
         ), '[]'::jsonb)
    into v_facts
    from nl_content.fact f
   where f.valid_to is null;

  select coalesce(jsonb_agg(to_jsonb(ch) order by ch.change_id desc), '[]'::jsonb)
    into v_changes
    from (
      select *
        from nl_content.staff_change c
       where v_ctx.role = 'super_admin'
          or c.actor_institution = v_ctx.institution_id
       order by c.change_id desc
       limit 100
    ) ch;

  select (
    (select count(*) from nl_content.service s
      where s.last_verified < current_date - 180
        and (v_ctx.role = 'super_admin'
             or s.for_institution_id = v_ctx.institution_id
             or (s.for_institution_id is null and exists (
                   select 1 from public.institution_campuses ic
                    where ic.institution_id = v_ctx.institution_id
                      and ic.city_id = s.municipality_id
                 ))))
    + (select count(*) from nl_content.step_local sl
        where sl.last_verified < current_date - 180
          and (v_ctx.role = 'super_admin'
               or sl.for_institution_id = v_ctx.institution_id
               or (sl.for_institution_id = '' and exists (
                     select 1 from public.institution_campuses ic
                      where ic.institution_id = v_ctx.institution_id
                        and ic.city_id = sl.municipality_id
                   ))))
    + (case when v_ctx.role = 'super_admin' then
         (select count(*) from nl_content.fact f where f.valid_to is null and f.last_verified < current_date - 180)
       else 0 end)
  )::integer into v_stale_count;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'role', v_ctx.role,
      'institution_id', nullif(v_target_inst, ''),
      'campus_cities', v_campus_city,
      'editable_cities', v_editable_city,
      'shared_cities', v_shared_city,
      'stale_count', v_stale_count
    ),
    'services', v_services,
    'step_local', v_step_local,
    'facts', v_facts,
    'changes', v_changes
  );
end;
$fn$;

create or replace function nl_content.editor_upsert_service(p_payload jsonb, p_reason text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = nl_content, public, pg_temp
as $fn$
declare
  v_ctx         record;
  v_service_id  text;
  v_name        text;
  v_type        text;
  v_city        text;
  v_muni        text;
  v_for_inst    text;
  v_desc        text;
  v_url         text;
  v_accepting   text;
  v_step_id     text;
  v_source_id   text;
  v_verified    date;
  v_existing    nl_content.service%rowtype;
  v_has_old     boolean := false;
  v_before_json jsonb := null;
  v_saved       nl_content.service%rowtype;
begin
  select * into v_ctx from nl_content._caller_context();
  if not v_ctx.is_privileged then
    perform nl.check_ingest_gateway();
    if v_ctx.role not in ('super_admin', 'editor') then
      raise exception 'forbidden editor role' using errcode = '42501';
    end if;
    if v_ctx.role <> 'super_admin' and v_ctx.institution_id = '' then
      raise exception 'missing institution scope' using errcode = '42501';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 500 then
    raise exception 'change reason must be 3..500 characters' using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;

  v_service_id := nullif(trim(p_payload ->> 'service_id'), '');
  v_name       := nullif(trim(p_payload ->> 'name'), '');
  v_type       := nullif(trim(p_payload ->> 'service_type'), '');
  v_city       := nullif(trim(p_payload ->> 'city_id'), '');
  v_muni       := coalesce(nullif(trim(p_payload ->> 'municipality_id'), ''), v_city);
  v_for_inst   := nullif(trim(p_payload ->> 'for_institution_id'), '');
  v_desc       := nullif(trim(p_payload ->> 'description'), '');
  v_url        := nullif(trim(p_payload ->> 'url'), '');
  v_accepting  := nullif(trim(p_payload ->> 'accepting_students'), '');
  v_step_id    := nullif(trim(p_payload ->> 'related_step_id'), '');
  v_source_id  := nullif(trim(p_payload ->> 'source_id'), '');
  v_verified   := coalesce(nl_content._parse_date(p_payload ->> 'last_verified', 'last_verified'), current_date);
  if v_verified > current_date then
    raise exception 'last_verified cannot be in the future' using errcode = '22023';
  end if;

  if v_service_id is null or v_service_id !~ '^[a-z0-9_-]{2,64}$' then
    raise exception 'invalid service_id' using errcode = '22023';
  end if;
  if v_name is null or length(v_name) not between 2 and 200
     or v_type is null or v_type not in ('gp', 'housing', 'support', 'community', 'government', 'banking', 'legal', 'municipal', 'other')
     or v_city is null or v_city !~ '^[a-z0-9-]{2,64}$'
     or v_muni is null or v_muni !~ '^[a-z0-9-]{2,64}$'
     or v_desc is null or length(v_desc) not between 2 and 2000
     or v_url is null then
    raise exception 'invalid or missing service fields' using errcode = '22023';
  end if;
  if v_url !~ '^https://[^\s"''<>\\]+$' then
    raise exception 'invalid url (https only)' using errcode = '22023';
  end if;
  if v_accepting is not null and v_accepting not in ('yes', 'limited', 'no') then
    raise exception 'invalid accepting_students value' using errcode = '22023';
  end if;
  if v_step_id is not null and v_step_id !~ '^[a-z0-9_-]{2,64}$' then
    raise exception 'invalid related_step_id' using errcode = '22023';
  end if;
  if v_source_id is not null and v_source_id !~ '^[a-z0-9_-]{2,64}$' then
    raise exception 'invalid source_id' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('nl_content.service:' || v_service_id));
  select * into v_existing from nl_content.service where service_id = v_service_id for update;
  v_has_old := found;
  if v_has_old then
    v_before_json := to_jsonb(v_existing);
    if v_ctx.role <> 'super_admin' then
      if not coalesce(
        v_existing.for_institution_id = v_ctx.institution_id
        or (v_existing.for_institution_id is null
            and public.can_edit_city(v_existing.municipality_id)
            and public.can_edit_city(v_existing.city_id)),
        false
      ) then
        raise exception 'forbidden: cannot modify existing service outside institution scope' using errcode = '42501';
      end if;
      if v_for_inst is distinct from v_existing.for_institution_id
         or v_city is distinct from v_existing.city_id
         or v_muni is distinct from v_existing.municipality_id then
        raise exception 'forbidden: cannot change service scope or city' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_ctx.role <> 'super_admin' then
    if v_for_inst = v_ctx.institution_id then
      if not (
        exists (select 1 from public.institution_campuses ic
                 where ic.institution_id = v_ctx.institution_id and ic.city_id = v_city)
        and exists (select 1 from public.institution_campuses ic
                     where ic.institution_id = v_ctx.institution_id and ic.city_id = v_muni)
      ) then
        raise exception 'forbidden: override city outside institution scope' using errcode = '42501';
      end if;
    elsif not coalesce(v_for_inst is null and public.can_edit_city(v_muni) and public.can_edit_city(v_city), false) then
      raise exception 'forbidden: shared city or foreign institution requires super_admin or institution override' using errcode = '42501';
    end if;
  end if;

  insert into nl_content.service (
    service_id, name, service_type, city_id, municipality_id, for_institution_id,
    description, url, accepting_students, related_step_id, source_id,
    last_verified, updated_at, updated_by
  ) values (
    v_service_id, v_name, v_type, v_city, v_muni, v_for_inst,
    v_desc, v_url, v_accepting, v_step_id, v_source_id,
    v_verified, now(), v_ctx.actor_sub
  )
  on conflict (service_id) do update
     set name = excluded.name,
         service_type = excluded.service_type,
         city_id = excluded.city_id,
         municipality_id = excluded.municipality_id,
         for_institution_id = excluded.for_institution_id,
         description = excluded.description,
         url = excluded.url,
         accepting_students = excluded.accepting_students,
         related_step_id = excluded.related_step_id,
         source_id = excluded.source_id,
         last_verified = excluded.last_verified,
         updated_at = now(),
         updated_by = excluded.updated_by
  returning * into v_saved;

  insert into nl_content.staff_change (
    actor_sub, actor_role, actor_institution, entity_type, entity_key,
    action, before_json, after_json, reason
  ) values (
    v_ctx.actor_sub, v_ctx.role, nullif(v_ctx.institution_id, ''),
    'service', v_service_id,
    case when v_has_old then 'update' else 'create' end,
    v_before_json, to_jsonb(v_saved), trim(p_reason)
  );

  return to_jsonb(v_saved) || jsonb_build_object('editable', true);
end;
$fn$;

create or replace function nl_content.editor_upsert_step_local(p_payload jsonb, p_reason text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = nl_content, public, pg_temp
as $fn$
declare
  v_ctx         record;
  v_step_id     text;
  v_muni        text;
  v_for_inst    text;
  v_body        text;
  v_links       jsonb;
  v_verified    date;
  v_existing    nl_content.step_local%rowtype;
  v_has_old     boolean := false;
  v_before_json jsonb := null;
  v_saved       nl_content.step_local%rowtype;
begin
  select * into v_ctx from nl_content._caller_context();
  if not v_ctx.is_privileged then
    perform nl.check_ingest_gateway();
    if v_ctx.role not in ('super_admin', 'editor') then
      raise exception 'forbidden editor role' using errcode = '42501';
    end if;
    if v_ctx.role <> 'super_admin' and v_ctx.institution_id = '' then
      raise exception 'missing institution scope' using errcode = '42501';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 500 then
    raise exception 'change reason must be 3..500 characters' using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;

  v_step_id  := nullif(trim(p_payload ->> 'step_id'), '');
  v_muni     := nullif(trim(p_payload ->> 'municipality_id'), '');
  v_for_inst := coalesce(nullif(trim(p_payload ->> 'for_institution_id'), ''), '');
  v_body     := nullif(trim(p_payload ->> 'body'), '');
  v_links    := nl_content._validate_links(p_payload -> 'links');
  v_verified := coalesce(nl_content._parse_date(p_payload ->> 'last_verified', 'last_verified'), current_date);
  if v_verified > current_date then
    raise exception 'last_verified cannot be in the future' using errcode = '22023';
  end if;

  if v_step_id is null or v_step_id !~ '^[a-z0-9_-]{2,64}$'
     or v_muni is null or v_muni !~ '^[a-z0-9-]{2,64}$'
     or v_body is null or length(v_body) not between 2 and 4000 then
    raise exception 'invalid or missing step_local fields' using errcode = '22023';
  end if;

  if v_ctx.role <> 'super_admin' then
    if v_for_inst = v_ctx.institution_id then
      if not exists (select 1 from public.institution_campuses ic
                      where ic.institution_id = v_ctx.institution_id and ic.city_id = v_muni) then
        raise exception 'forbidden: override city outside institution scope' using errcode = '42501';
      end if;
    elsif not (v_for_inst = '' and public.can_edit_city(v_muni)) then
      raise exception 'forbidden: shared city step_local requires institution override or super_admin' using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtext('nl_content.step_local:' || v_step_id || '|' || v_muni || '|' || v_for_inst));
  select * into v_existing
    from nl_content.step_local
   where step_id = v_step_id
     and municipality_id = v_muni
     and for_institution_id = v_for_inst
   for update;
  v_has_old := found;
  if v_has_old then
    v_before_json := to_jsonb(v_existing);
  end if;

  insert into nl_content.step_local (
    step_id, municipality_id, for_institution_id, body, links,
    last_verified, updated_at, updated_by
  ) values (
    v_step_id, v_muni, v_for_inst, v_body, v_links,
    v_verified, now(), v_ctx.actor_sub
  )
  on conflict (step_id, municipality_id, for_institution_id) do update
     set body = excluded.body,
         links = excluded.links,
         last_verified = excluded.last_verified,
         updated_at = now(),
         updated_by = excluded.updated_by
  returning * into v_saved;

  insert into nl_content.staff_change (
    actor_sub, actor_role, actor_institution, entity_type, entity_key,
    action, before_json, after_json, reason
  ) values (
    v_ctx.actor_sub, v_ctx.role, nullif(v_ctx.institution_id, ''),
    'step_local', v_step_id || '|' || v_muni || '|' || v_for_inst,
    case when v_has_old then 'update' else 'create' end,
    v_before_json, to_jsonb(v_saved), trim(p_reason)
  );

  return to_jsonb(v_saved) || jsonb_build_object('editable', true);
end;
$fn$;

create or replace function nl_content.editor_publish_fact(p_payload jsonb, p_reason text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = nl_content, public, pg_temp
as $fn$
declare
  v_ctx         record;
  v_fact_key    text;
  v_label       text;
  v_value       text;
  v_unit        text;
  v_source_id   text;
  v_step_id     text;
  v_valid_from  date;
  v_verified    date;
  v_old_fact    nl_content.fact%rowtype;
  v_old_json    jsonb := null;
  v_saved       nl_content.fact%rowtype;
begin
  select * into v_ctx from nl_content._caller_context();
  if not v_ctx.is_privileged then
    perform nl.check_ingest_gateway();
    if v_ctx.role <> 'super_admin' then
      raise exception 'forbidden: only super_admin may publish national facts' using errcode = '42501';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 500 then
    raise exception 'change reason must be 3..500 characters' using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;

  v_fact_key   := nullif(trim(p_payload ->> 'fact_key'), '');
  v_label      := nullif(trim(p_payload ->> 'label'), '');
  v_value      := nullif(trim(p_payload ->> 'value'), '');
  v_unit       := nullif(trim(p_payload ->> 'unit'), '');
  v_source_id  := nullif(trim(p_payload ->> 'source_id'), '');
  v_step_id    := nullif(trim(p_payload ->> 'step_id'), '');
  v_valid_from := coalesce(nl_content._parse_date(p_payload ->> 'valid_from', 'valid_from'), current_date);
  v_verified   := coalesce(nl_content._parse_date(p_payload ->> 'last_verified', 'last_verified'), current_date);
  if v_verified > current_date then
    raise exception 'last_verified cannot be in the future' using errcode = '22023';
  end if;

  if v_fact_key is null or v_fact_key !~ '^[a-z0-9_]{2,64}$'
     or v_label is null or length(v_label) not between 2 and 200 or v_label ~ '[<>]'
     or v_value is null or length(v_value) not between 1 and 200 or v_value ~ '[<>]'
     or v_source_id is null or length(v_source_id) not between 2 and 64 then
    raise exception 'invalid or missing fact fields' using errcode = '22023';
  end if;
  if v_unit is not null and (length(v_unit) > 64 or v_unit ~ '[<>]') then
    raise exception 'invalid fact unit' using errcode = '22023';
  end if;
  if v_step_id is not null and v_step_id !~ '^[a-z0-9_-]{2,64}$' then
    raise exception 'invalid step_id' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtext('nl_content.fact:' || v_fact_key));
  select * into v_old_fact
    from nl_content.fact f
   where f.fact_key = v_fact_key and f.valid_to is null
   for update;
  if found then
    v_old_json := to_jsonb(v_old_fact);
  end if;

  insert into nl_content.fact (
    fact_key, label, value, unit, source_id, step_id,
    valid_from, last_verified, updated_at, updated_by
  ) values (
    v_fact_key, v_label, v_value, v_unit, v_source_id, v_step_id,
    v_valid_from, v_verified, now(), v_ctx.actor_sub
  )
  returning * into v_saved;

  insert into nl_content.staff_change (
    actor_sub, actor_role, actor_institution, entity_type, entity_key,
    action, before_json, after_json, reason
  ) values (
    v_ctx.actor_sub, v_ctx.role, nullif(v_ctx.institution_id, ''),
    'fact', v_fact_key, 'publish',
    v_old_json, to_jsonb(v_saved), trim(p_reason)
  );

  return to_jsonb(v_saved) || jsonb_build_object('editable', true);
end;
$fn$;

create or replace function nl_content.editor_mark_verified(
  p_entity_type text,
  p_entity_key  text,
  p_reason      text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = nl_content, public, pg_temp
as $fn$
declare
  v_ctx         record;
  v_old_json    jsonb;
  v_new_json    jsonb;
  v_svc         nl_content.service%rowtype;
  v_sl          nl_content.step_local%rowtype;
  v_fact        nl_content.fact%rowtype;
  v_step        text;
  v_muni        text;
  v_inst        text;
  v_parts       text[];
  v_canon_key   text;
begin
  select * into v_ctx from nl_content._caller_context();
  if not v_ctx.is_privileged then
    perform nl.check_ingest_gateway();
    if v_ctx.role not in ('super_admin', 'editor') then
      raise exception 'forbidden editor role' using errcode = '42501';
    end if;
    if v_ctx.role <> 'super_admin' and v_ctx.institution_id = '' then
      raise exception 'missing institution scope' using errcode = '42501';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 500 then
    raise exception 'verification reason must be 3..500 characters' using errcode = '22023';
  end if;
  if p_entity_key is null or length(trim(p_entity_key)) = 0 then
    raise exception 'entity_key is required' using errcode = '22023';
  end if;

  if p_entity_type = 'service' then
    perform pg_advisory_xact_lock(hashtext('nl_content.service:' || p_entity_key));
    select * into v_svc from nl_content.service where service_id = p_entity_key for update;
    if not found then
      raise exception 'unknown service %', p_entity_key using errcode = '22023';
    end if;
    if v_ctx.role <> 'super_admin' and not coalesce(
      v_svc.for_institution_id = v_ctx.institution_id
      or (v_svc.for_institution_id is null and public.can_edit_city(v_svc.municipality_id) and public.can_edit_city(v_svc.city_id)),
      false
    ) then
      raise exception 'forbidden service scope' using errcode = '42501';
    end if;
    v_old_json := to_jsonb(v_svc);
    update nl_content.service
       set last_verified = current_date, updated_at = now(), updated_by = v_ctx.actor_sub
     where service_id = p_entity_key
     returning * into v_svc;
    v_new_json := to_jsonb(v_svc);
    v_canon_key := p_entity_key;

  elsif p_entity_type = 'step_local' then
    v_parts := string_to_array(p_entity_key, '|');
    if coalesce(array_length(v_parts, 1), 0) not in (2, 3) then
      raise exception 'invalid step_local entity_key' using errcode = '22023';
    end if;
    v_step := v_parts[1];
    v_muni := v_parts[2];
    v_inst := coalesce(v_parts[3], '');
    v_canon_key := v_step || '|' || v_muni || '|' || v_inst;
    perform pg_advisory_xact_lock(hashtext('nl_content.step_local:' || v_canon_key));
    select * into v_sl
      from nl_content.step_local
     where step_id = v_step and municipality_id = v_muni and for_institution_id = v_inst
     for update;
    if not found then
      raise exception 'unknown step_local %', p_entity_key using errcode = '22023';
    end if;
    if v_ctx.role <> 'super_admin' and not (
      v_sl.for_institution_id = v_ctx.institution_id
      or (v_sl.for_institution_id = '' and public.can_edit_city(v_sl.municipality_id))
    ) then
      raise exception 'forbidden step_local scope' using errcode = '42501';
    end if;
    v_old_json := to_jsonb(v_sl);
    update nl_content.step_local
       set last_verified = current_date, updated_at = now(), updated_by = v_ctx.actor_sub
     where step_id = v_step and municipality_id = v_muni and for_institution_id = v_inst
     returning * into v_sl;
    v_new_json := to_jsonb(v_sl);

  elsif p_entity_type = 'fact' then
    if not v_ctx.is_privileged and v_ctx.role <> 'super_admin' then
      raise exception 'forbidden: only super_admin may verify national facts' using errcode = '42501';
    end if;
    perform pg_advisory_xact_lock(hashtext('nl_content.fact:' || p_entity_key));
    select * into v_fact from nl_content.fact where fact_key = p_entity_key and valid_to is null for update;
    if not found then
      raise exception 'unknown active fact %', p_entity_key using errcode = '22023';
    end if;
    v_old_json := to_jsonb(v_fact);
    update nl_content.fact
       set last_verified = current_date, updated_at = now(), updated_by = v_ctx.actor_sub
     where fact_id = v_fact.fact_id
     returning * into v_fact;
    v_new_json := to_jsonb(v_fact);
    v_canon_key := p_entity_key;

  else
    raise exception 'unknown entity_type %', p_entity_type using errcode = '22023';
  end if;

  insert into nl_content.staff_change (
    actor_sub, actor_role, actor_institution, entity_type, entity_key,
    action, before_json, after_json, reason
  ) values (
    v_ctx.actor_sub, v_ctx.role, nullif(v_ctx.institution_id, ''),
    p_entity_type, v_canon_key, 'verify',
    v_old_json, v_new_json, trim(p_reason)
  );

  return v_new_json || jsonb_build_object('editable', true);
end;
$fn$;

-- 8. Re-apply least-privilege permissions on replaced functions
revoke all on function nl.check_ingest_rate_limit(smallint, integer, integer) from public;
revoke all on function nl.accumulate() from public;
revoke all on function nl.release_json_for_institution(text, bigint) from public;
revoke all on function nl_content._caller_context() from public;
revoke all on function nl_content.editor_list(text) from public;
revoke all on function nl_content.editor_upsert_service(jsonb, text) from public;
revoke all on function nl_content.editor_upsert_step_local(jsonb, text) from public;
revoke all on function nl_content.editor_publish_fact(jsonb, text) from public;
revoke all on function nl_content.editor_mark_verified(text, text, text) from public;

do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function nl.check_ingest_rate_limit(smallint, integer, integer), nl.accumulate(), nl.release_json_for_institution(text, bigint) from anon';
    execute 'revoke execute on all functions in schema nl_content from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke execute on function nl.check_ingest_rate_limit(smallint, integer, integer), nl.accumulate() from authenticated';
    execute 'grant execute on function nl.release_json_for_institution(text, bigint) to authenticated';
    execute 'revoke execute on function nl_content._caller_context() from authenticated';
    execute 'grant execute on function nl_content.editor_list(text) to authenticated';
    execute 'grant execute on function nl_content.editor_upsert_service(jsonb, text) to authenticated';
    execute 'grant execute on function nl_content.editor_upsert_step_local(jsonb, text) to authenticated';
    execute 'grant execute on function nl_content.editor_publish_fact(jsonb, text) to authenticated';
    execute 'grant execute on function nl_content.editor_mark_verified(text, text, text) to authenticated';
  end if;
end
$grants$;

-- 9. Schedule pg_cron jobs automatically when pg_cron is enabled
do $cron$
declare
  v_jid bigint;
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    for v_jid in
      select jobid from cron.job where jobname in ('nl-fold', 'nl-release', 'nl-purge')
    loop
      perform cron.unschedule(v_jid);
    end loop;
    perform cron.schedule('nl-fold', '7 * * * *', $$select nl.accumulate()$$);
    perform cron.schedule('nl-release', '17 6 1 * *', $$select nl.publish_snapshot('monthly')$$);
    perform cron.schedule('nl-purge', '43 * * * *', $$select nl.purge_raw()$$);
  end if;
end
$cron$;

commit;
