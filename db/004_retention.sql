-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 004_retention.sql
-- Retention policy, the purge routine, guard triggers and a health check.

begin;

create table if not exists nl.retention_policy (
  store      text primary key,
  keep_hours integer,
  keep_days  integer,
  note       text not null,
  updated_at timestamptz not null default now()
);

insert into nl.retention_policy (store, keep_hours, keep_days, note) values
  ('raw_t1', 48, null,
   'Folded hourly. Deleted an hour after the fold that captured it, and never kept past 48 hours.'),
  ('raw_t2', 48, null,
   'Folded hourly. Deleted an hour after the fold that captured it, and never kept past 48 hours.'),
  ('stage_cell', null, 90, 'Rebuilt in full on every release; kept a quarter for debugging.'),
  ('snapshot', null, 1095, 'Published aggregate snapshots, three years.'),
  ('accumulated_cell', null, null, 'Aggregates only. Retained indefinitely.'),
  ('unmapped_value', null, 400, 'Dictionary of step keys not yet recognised; 400 days.')
on conflict (store) do nothing;

create or replace function nl.guard_raw_delete()
returns trigger
language plpgsql
as $fn$
begin
  if coalesce(current_setting('nl.allow_maintenance', true), 'off') = 'on' then
    return old;
  end if;
  if old.fold_run is null and old.received_at > now() - interval '48 hours' then
    raise exception 'refusing to delete unfolded row % before the 48 hour ceiling', old.id
      using errcode = '42501';
  end if;
  return old;
end;
$fn$;

drop trigger if exists guard_raw_delete on nl.raw_t1;
create trigger guard_raw_delete before delete on nl.raw_t1
  for each row execute function nl.guard_raw_delete();

drop trigger if exists guard_raw_delete on nl.raw_t2;
create trigger guard_raw_delete before delete on nl.raw_t2
  for each row execute function nl.guard_raw_delete();

create or replace function nl.purge_raw()
returns table (store text, removed bigint)
language plpgsql
volatile
as $fn$
declare
  v1 bigint := 0;
  v2 bigint := 0;
  v3 bigint := 0;
  v4 bigint := 0;
  v5 bigint := 0;
  v6 bigint := 0;
  v7 bigint := 0;
begin
  perform set_config('nl.allow_maintenance', 'on', true);

  delete from nl.raw_t1 r
   where r.received_at < now() - interval '48 hours'
      or (r.fold_run is not null and exists (
            select 1 from nl.accumulation_run ar
             where ar.run_id = r.fold_run
               and ar.finished_at is not null
               and ar.finished_at < now() - interval '1 hour'));
  get diagnostics v1 = row_count;

  delete from nl.raw_t2 r
   where r.received_at < now() - interval '48 hours'
      or (r.fold_run is not null and exists (
            select 1 from nl.accumulation_run ar
             where ar.run_id = r.fold_run
               and ar.finished_at is not null
               and ar.finished_at < now() - interval '1 hour'));
  get diagnostics v2 = row_count;

  delete from nl.stage_cell where built_at < now() - interval '90 days';
  get diagnostics v3 = row_count;

  delete from nl.snapshot where built_at < now() - interval '1095 days';
  get diagnostics v4 = row_count;

  delete from nl.unmapped_value where last_seen < now() - interval '400 days';
  get diagnostics v5 = row_count;

  delete from nl.accumulation_run where finished_at < now() - interval '90 days';
  get diagnostics v6 = row_count;

  if to_regclass('nl.ingest_rate_limits') is not null then
    execute 'delete from nl.ingest_rate_limits where bucket_hour < now() - interval ''2 hours''';
    get diagnostics v7 = row_count;
  end if;

  perform set_config('nl.allow_maintenance', 'off', true);

  store := 'raw_t1';             removed := v1; return next;
  store := 'raw_t2';             removed := v2; return next;
  store := 'stage_cell';         removed := v3; return next;
  store := 'snapshot';           removed := v4; return next;
  store := 'unmapped_value';     removed := v5; return next;
  store := 'accumulation_run';   removed := v6; return next;
  store := 'ingest_rate_limits'; removed := v7; return next;
  return;
end;
$fn$;

create or replace view nl.retention_status as
select 'raw_t1'::text as store,
       count(*) as rows_kept,
       count(*) filter (where fold_run is null) as unfolded,
       min(received_at) as oldest,
       max(received_at) as newest
  from nl.raw_t1
union all
select 'raw_t2', count(*), count(*) filter (where fold_run is null),
       min(received_at), max(received_at)
  from nl.raw_t2
union all
select 'snapshot', count(*), count(*) filter (where not published),
       min(built_at), max(built_at)
  from nl.snapshot
union all
select 'accumulated_cell', count(*), null::bigint,
       min(updated_at), max(updated_at)
  from nl.accumulated_cell;

create or replace function nl.health()
returns jsonb
language sql
stable
as $fn$
  with oldest as (
    select least(
      (select min(received_at) from nl.raw_t1),
      (select min(received_at) from nl.raw_t2)
    ) as oldest_ts
  ),
  age as (
    select round(extract(epoch from (now() - oldest_ts)) / 3600.0, 1) as oldest_hours
      from oldest
  )
  select jsonb_build_object(
    'ok', (select coalesce(oldest_hours, 0) < 48.0 from age),
    'checked_at', now(),
    'raw_t1_unfolded', (select count(*) from nl.raw_t1 where fold_run is null),
    'raw_t2_unfolded', (select count(*) from nl.raw_t2 where fold_run is null),
    'raw_oldest_hours', (select oldest_hours from age),
    'accumulated_cells', (select count(*) from nl.accumulated_cell),
    'snapshots', (select count(*) from nl.snapshot),
    'last_snapshot', (select max(snapshot_id) from nl.snapshot),
    'last_published', (select max(snapshot_id) from nl.snapshot where published));
$fn$;

-- Scheduling. Uncomment once pg_cron is available in the database.
--
-- select cron.schedule('nl-fold', '7 * * * *', $$select nl.accumulate()$$);
-- select cron.schedule('nl-release', '17 6 1 * *', $$select nl.publish_snapshot('monthly')$$);
-- select cron.schedule('nl-purge', '43 * * * *', $$select nl.purge_raw()$$);

commit;
