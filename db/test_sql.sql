-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: test_sql.sql
-- Automated PostgreSQL 15+ smoke, security, suppression, and retention test suite.
-- Wrapped in BEGIN ... ROLLBACK so it leaves zero test data behind.
-- Run after applying 001..008:
--   psql -h localhost -U postgres -d postgres -v ON_ERROR_STOP=1 -f db/test_sql.sql

begin;

do $test$
declare
  v_cnt      integer;
  v_run      bigint;
  v_snap     bigint;
  v_json     jsonb;
  v_health   jsonb;
  v_t1_batch jsonb := '[]'::jsonb;
  v_t2_batch jsonb := '[]'::jsonb;
  i          integer;
begin
  -- 1. Seeded vocabulary check
  select count(*) into v_cnt from nl.institution where institution in ('thuas', 'uva');
  if v_cnt <> 2 then
    raise exception 'expected seeded institutions thuas and uva, got %', v_cnt;
  end if;

  -- 2. Single-object Tier 1 ingest
  v_cnt := nl.ingest_t1_rpc('{"institution":"thuas","intake":"2026-sep","event":"step_applies","category":"housing","app_version":"3b32b5914fb6bdfc"}'::jsonb);
  if v_cnt <> 1 then
    raise exception 'expected single ingest count 1, got %', v_cnt;
  end if;

  -- 3. Array batch Tier 1 & Tier 2 ingest (15 students: >= 15 contributor floor and <= 100 batch limit)
  for i in 1..15 loop
    v_t1_batch := v_t1_batch || jsonb_build_array(
      jsonb_build_object('institution', 'thuas', 'intake', '2026-sep', 'event', 'cohort_joined', 'app_version', '3b32b5914fb6bdfc'),
      jsonb_build_object('institution', 'thuas', 'intake', '2026-sep', 'event', 'step_applies', 'category', 'housing', 'app_version', '3b32b5914fb6bdfc'),
      jsonb_build_object('institution', 'thuas', 'intake', '2026-sep', 'event', 'step_completed', 'category', 'housing', 'app_version', '3b32b5914fb6bdfc')
    );
    v_t2_batch := v_t2_batch || jsonb_build_array(
      jsonb_build_object('institution', 'thuas', 'region', 'eu_eea', 'intake', '2026-sep', 'event', 'joined'),
      jsonb_build_object('institution', 'thuas', 'region', 'eu_eea', 'intake', '2026-sep', 'event', 'arrived'),
      jsonb_build_object('institution', 'thuas', 'region', 'eu_eea', 'intake', '2026-sep', 'event', 'step_applies', 'step', 'find_housing'),
      jsonb_build_object('institution', 'thuas', 'region', 'eu_eea', 'intake', '2026-sep', 'event', 'step_opened', 'step', 'find_housing'),
      jsonb_build_object('institution', 'thuas', 'region', 'eu_eea', 'intake', '2026-sep', 'event', 'step_completed', 'step', 'find_housing')
    );
    if i <= 3 then
      v_t2_batch := v_t2_batch || jsonb_build_array(
        jsonb_build_object('institution', 'thuas', 'region', 'eu_eea', 'intake', '2026-sep', 'event', 'deadline_missed', 'step', 'find_housing'),
        jsonb_build_object('institution', 'thuas', 'region', 'eu_eea', 'intake', '2026-sep', 'event', 'scam_checked', 'high_risk', (i = 1))
      );
    end if;
  end loop;

  v_cnt := nl.ingest_t1_rpc(v_t1_batch);
  if v_cnt <> 45 then
    raise exception 'expected 45 Tier 1 events, got %', v_cnt;
  end if;

  v_cnt := nl.ingest_t2_rpc(v_t2_batch);
  if v_cnt < 75 then
    raise exception 'expected >= 75 Tier 2 events, got %', v_cnt;
  end if;

  -- 4. Case-insensitive identity field rejection (22023)
  begin
    perform nl.ingest_t1_rpc('{"institution":"thuas","intake":"2026-sep","event":"step_applies","category":"housing","app_version":"3b32b5914fb6bdfc","Session_ID":"abc"}'::jsonb);
    raise exception 'expected 22023 on Session_ID';
  exception when sqlstate '22023' then
    null;
  end;

  -- 5. Unknown institution, invalid region, and unexpected T1 key rejection (22023)
  begin
    perform nl.ingest_t1_rpc('{"institution":"no_such_uni","intake":"2026-sep","event":"step_applies","category":"housing","app_version":"3b32b5914fb6bdfc"}'::jsonb);
    raise exception 'expected 22023 on unknown institution';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform nl.ingest_t2_rpc('{"institution":"thuas","region":"junk_region","intake":"2026-sep","event":"joined"}'::jsonb);
    raise exception 'expected 22023 on invalid region';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform nl.ingest_t1_rpc('{"institution":"thuas","intake":"2026-sep","event":"step_applies","category":"housing","app_version":"3b32b5914fb6bdfc","step":"find_housing"}'::jsonb);
    raise exception 'expected 22023 on unexpected T1 key';
  exception when sqlstate '22023' then
    null;
  end;

  -- 6. Delete-guard trigger on unfolded raw row within 48h (42501)
  begin
    delete from nl.raw_t1 where fold_run is null;
    raise exception 'expected 42501 from guard_raw_delete';
  exception when sqlstate '42501' then
    null;
  end;

  -- 7. Fold & verify scoped tables populated (plus unknown step collapses to 'other')
  perform nl.ingest_t2_rpc('{"institution":"thuas","region":"eu_eea","intake":"2026-sep","event":"step_applies","step":"unmapped_junk_step"}'::jsonb);
  v_run := nl.accumulate();
  if v_run is null then
    raise exception 'accumulate returned null';
  end if;

  if exists (select 1 from nl.accumulated_cell where row_key like '%unmapped_junk_step%') then
    raise exception 'unmapped step should collapse to other, not pollute accumulated_cell';
  end if;

  select count(*) into v_cnt
    from nl.accumulated_cell
   where table_id in ('t1_inst_category', 't2_inst_step', 't2_inst_opened', 't2_inst_missed', 't2_inst_region', 't2_inst_scam');
  if v_cnt < 6 then
    raise exception 'expected all 6 scoped tables populated, got %', v_cnt;
  end if;

  -- 8. Publish snapshot & verify scoped release JSON
  v_snap := nl.publish_snapshot('sql-test');
  if v_snap is null then
    raise exception 'publish_snapshot returned null';
  end if;

  v_json := nl.release_json_for_institution('thuas', v_snap);
  if (v_json -> 'meta' ->> 'institution') <> 'thuas' then
    raise exception 'unexpected institution in release_json_for_institution: %', v_json;
  end if;

  -- 9. Cross-institution & invalid-role JWT enforcement (42501)
  perform set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"role":"reader","institution_id":"uva"}}', true);
  begin
    perform nl.release_json_for_institution('thuas', v_snap);
    raise exception 'expected 42501 for cross-institution JWT';
  exception when sqlstate '42501' then
    null;
  end;
  perform set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"role":"student","institution_id":"thuas"}}', true);
  begin
    perform nl.release_json_for_institution('thuas', v_snap);
    raise exception 'expected 42501 for student role JWT';
  exception when sqlstate '42501' then
    null;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- 10. Purge & health check
  perform * from nl.purge_raw();
  v_health := nl.health();
  if coalesce((v_health ->> 'ok')::boolean, false) is not true then
    raise exception 'health check failed: %', v_health;
  end if;

  raise notice 'ALL SQL TESTS PASSED (run_id=%, snapshot_id=%)', v_run, v_snap;
end
$test$;

rollback;
