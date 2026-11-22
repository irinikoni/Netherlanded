-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 006_security_rls_and_scoping.sql
-- PostgreSQL 15+ (and Supabase-compatible).
-- Hardens least-privilege permissions, enables Row-Level Security on every table
-- in schema nl, adds ephemeral salted hourly rate limiting (using built-in sha256),
-- and provides per-institution tenant-scoped release JSON.

begin;

-- 1. Least privilege on schema nl and all existing objects
revoke all on schema nl from public;
revoke all on all tables in schema nl from public;
revoke all on all sequences in schema nl from public;
revoke all on all functions in schema nl from public;

-- Enable Row-Level Security on every table in nl (default-deny for non-owners)
alter table nl.institution      enable row level security;
alter table nl.step_vocab       enable row level security;
alter table nl.release_table    enable row level security;
alter table nl.snapshot         enable row level security;
alter table nl.raw_t1           enable row level security;
alter table nl.raw_t2           enable row level security;
alter table nl.unmapped_value   enable row level security;
alter table nl.accumulation_run enable row level security;
alter table nl.accumulated_cell enable row level security;
alter table nl.t1_cohort        enable row level security;
alter table nl.t2_base          enable row level security;
alter table nl.t2_region_base   enable row level security;
alter table nl.stage_cell       enable row level security;
alter table nl.published_cell   enable row level security;
alter table nl.suppressed_cell  enable row level security;
alter table nl.retention_policy enable row level security;

-- 2. Ephemeral salted hourly rate-limit buckets (built-in pg_catalog.sha256; zero raw IPs stored)
create table if not exists nl.ingest_rate_limits (
  bucket_hour timestamptz not null,
  client_hash text not null,
  tier        smallint not null check (tier in (1, 2)),
  req_count   integer not null default 1,
  primary key (bucket_hour, client_hash, tier)
);

alter table nl.ingest_rate_limits enable row level security;

create or replace function nl.check_ingest_rate_limit(
  p_tier         smallint,
  p_max_per_hour integer
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
  -- Nginx enforces per-IP limits in memory and strips IP headers before PostgREST;
  -- this database limit acts solely as a global per-tier safety circuit breaker.
  v_hash    text := encode(
    pg_catalog.sha256(convert_to('global::' || v_secret || '::' || v_hour::text, 'UTF8')),
    'hex'
  );
  v_cnt     integer;
  v_cap     integer := greatest(p_max_per_hour, 60000);
begin
  delete from nl.ingest_rate_limits
   where bucket_hour < (v_hour - interval '2 hours');

  insert into nl.ingest_rate_limits (bucket_hour, client_hash, tier, req_count)
  values (v_hour, v_hash, p_tier, 1)
  on conflict (bucket_hour, client_hash, tier)
  do update set req_count = nl.ingest_rate_limits.req_count + 1
  returning req_count into v_cnt;

  return v_cnt <= v_cap;
end;
$fn$;

-- Global circuit-breaker ingest RPC entrypoints (Nginx handles per-IP limits)
create or replace function nl.ingest_t1_rpc(p jsonb)
returns integer
language plpgsql
volatile
security definer
set search_path = nl, pg_temp
as $fn$
begin
  if not nl.check_ingest_rate_limit(1::smallint, 60000) then
    raise exception 'rate_limit_exceeded' using errcode = 'P0001';
  end if;
  return nl.ingest_t1(p);
end;
$fn$;

create or replace function nl.ingest_t2_rpc(p jsonb)
returns integer
language plpgsql
volatile
security definer
set search_path = nl, pg_temp
as $fn$
begin
  if not nl.check_ingest_rate_limit(2::smallint, 60000) then
    raise exception 'rate_limit_exceeded' using errcode = 'P0001';
  end if;
  return nl.ingest_t2(p);
end;
$fn$;

-- 3. Per-institution tenant-scoped release JSON (superseded/extended in 008_scoped_insights.sql)
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
     where row_axis = 'institution' or v_allow_pooled
     order by tier, table_id
  loop
    select coalesce(jsonb_agg(jsonb_build_object(
             'row', row_key,
             'row_label', nl.dim_label(r.row_axis, row_key),
             'col', col_key,
             'col_label', nl.dim_label(r.col_axis, col_key),
             'num', case when v_allow_pooled then num
                         when num < 5 or (denom - num) < 5 or rate <= 0.10 or rate >= 0.90 or denom < 50 then null
                         else num end,
             'denom', denom,
             'rate', case when v_allow_pooled then rate
                          when num < 5 or (denom - num) < 5 or rate <= 0.10 or rate >= 0.90 or denom < 50 then null
                          else rate end,
             'band', case when v_allow_pooled then band
                          when num < 5 or (denom - num) < 5 or rate <= 0.10 or rate >= 0.90 then null
                          else band end,
             'rate_display', case
               when num < 5 or rate <= 0.10 then '<= 10.0%'
               when (denom - num) < 5 or rate >= 0.90 then '>= 90.0%'
               when denom < 50 then band::text || '%'
               else round(rate * 100)::integer::text || '%'
             end) order by row_key, col_key), '[]'::jsonb)
      into v_cells
      from nl.published_cell
     where snapshot_id = v_snap
       and table_id = r.table_id
       and (r.row_axis <> 'institution' or row_key = p_institution);

    select coalesce(jsonb_agg(jsonb_build_object(
             'row', row_key,
             'row_label', nl.dim_label(r.row_axis, row_key),
             'col', col_key,
             'col_label', nl.dim_label(r.col_axis, col_key),
             'reason', case when v_allow_pooled then reason else null end,
             'bucket', bucket) order by row_key, col_key), '[]'::jsonb)
      into v_hidden
      from nl.suppressed_cell
     where snapshot_id = v_snap
       and table_id = r.table_id
       and (r.row_axis <> 'institution' or row_key = p_institution);

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

-- 4. Conditional role grants & complete helper revokes
revoke all on function nl.accumulate() from public;
revoke all on function nl.build_stage() from public;
revoke all on function nl.publish_snapshot(text) from public;
revoke all on function nl.purge_raw() from public;
revoke all on function nl.release_json(bigint) from public;
revoke all on function nl.stats_json() from public;
revoke all on function nl.check_ingest_rate_limit(smallint, integer) from public;
revoke all on function nl.ingest_t1(jsonb) from public;
revoke all on function nl.ingest_t2(jsonb) from public;
revoke all on function nl.ingest_t1_rpc(jsonb) from public;
revoke all on function nl.ingest_t2_rpc(jsonb) from public;
revoke all on function nl.release_json_for_institution(text, bigint) from public;
revoke all on function nl.health() from public;
revoke all on function nl.assert_release_safe(bigint) from public;
revoke all on function nl.bucket(bigint) from public;
revoke all on function nl.dim_label(text, text) from public;
revoke all on function nl.normalize_batch(jsonb) from public;
revoke all on function nl.reject_identity(jsonb) from public;
revoke all on function nl.check_hint(jsonb) from public;

do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant usage on schema nl to anon';
    execute 'grant execute on function nl.ingest_t1_rpc(jsonb), nl.ingest_t2_rpc(jsonb) to anon';
    execute 'revoke execute on function nl.accumulate(), nl.build_stage(), nl.publish_snapshot(text), nl.purge_raw(), nl.release_json(bigint), nl.stats_json(), nl.check_ingest_rate_limit(smallint, integer), nl.ingest_t1(jsonb), nl.ingest_t2(jsonb), nl.release_json_for_institution(text, bigint), nl.health(), nl.assert_release_safe(bigint), nl.bucket(bigint), nl.dim_label(text, text), nl.normalize_batch(jsonb), nl.reject_identity(jsonb), nl.check_hint(jsonb) from anon';
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant usage on schema nl to authenticated';
    execute 'grant execute on function nl.ingest_t1_rpc(jsonb), nl.ingest_t2_rpc(jsonb), nl.release_json_for_institution(text, bigint) to authenticated';
    execute 'revoke execute on function nl.accumulate(), nl.build_stage(), nl.publish_snapshot(text), nl.purge_raw(), nl.release_json(bigint), nl.stats_json(), nl.check_ingest_rate_limit(smallint, integer), nl.ingest_t1(jsonb), nl.ingest_t2(jsonb), nl.health(), nl.assert_release_safe(bigint), nl.bucket(bigint), nl.dim_label(text, text), nl.normalize_batch(jsonb), nl.reject_identity(jsonb), nl.check_hint(jsonb) from authenticated';
  end if;
end
$grants$;

commit;
