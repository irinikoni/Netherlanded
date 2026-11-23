-- GENERATED from db/003_release.sql by tools/sync_supabase.py. Edit the source, not this file.
-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 003_release.sql
-- Fold raw events into aggregate cells, run the disclosure-control chain,
-- then publish. The rules implemented here are mirrored, and executed, in
-- tools/suppress_reference.py.

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

create or replace function nl.build_stage()
returns integer
language plpgsql
volatile
as $fn$
declare
  v_prev1   bigint;
  v_hit_row integer := 0;
  v_hit_col integer := 0;
  v_hit_sec integer := 0;
  v_pass    integer := 0;
  v_out     integer := 0;
begin
  perform pg_advisory_xact_lock(hashtext('nl.release'));

  delete from nl.stage_cell;

  insert into nl.stage_cell (table_id, row_key, col_key, num_true, denom_true,
                             num_pub, denom_pub, num_basis, denom_basis)
  select table_id, row_key, col_key, num, denom,
         least(greatest(0, round((num + nl.cell_noise(num_key)) / 5.0) * 5),
               greatest(15, round((denom + nl.cell_noise(denom_key)) / 5.0) * 5))::bigint,
         greatest(15, round((denom + nl.cell_noise(denom_key)) / 5.0) * 5)::bigint,
         num, denom
    from nl.accumulated_cell;

  -- 1. floor: fewer than fifteen true respondents (or < 15 distinct student contributors) is never published
  update nl.stage_cell set reason = 'floor' where denom_true < 15;

  update nl.stage_cell s
     set reason = 'floor'
   where s.reason is null
     and s.table_id in ('t1_institution_intake', 't1_inst_category', 't1_error_rate')
     and coalesce((select c.contributors
                     from nl.t1_cohort c
                    where c.institution = split_part(s.row_key, ':', 1)
                      and c.intake = s.col_key), 0) < 15;

  update nl.stage_cell s
     set reason = 'floor'
   where s.reason is null
     and s.table_id = 't1_category_totals'
     and coalesce((select sum(c.contributors)
                     from nl.t1_cohort c
                    where c.intake = s.col_key), 0) < 15;

  update nl.stage_cell s
     set reason = 'floor'
   where s.reason is null
     and s.table_id in ('t2_institution_intake', 't2_inst_step', 't2_inst_opened',
                        't2_inst_missed', 't2_inst_scam')
     and coalesce((select b.joined
                     from nl.t2_base b
                    where b.institution = split_part(s.row_key, ':', 1)
                      and b.intake = s.col_key), 0) < 15;

  update nl.stage_cell s
     set reason = 'floor'
   where s.reason is null
     and s.table_id = 't2_inst_region'
     and coalesce((select r.joined
                     from nl.t2_region_base r
                    where r.institution = split_part(s.row_key, ':', 1)
                      and r.region = split_part(s.row_key, ':', 2)
                      and r.intake = s.col_key), 0) < 15;

  update nl.stage_cell s
     set reason = 'floor'
   where s.reason is null
     and s.table_id = 't2_step_totals'
     and coalesce((select sum(b.joined)
                     from nl.t2_base b
                    where b.intake = s.col_key), 0) < 15;

  -- 1b. benchmark (pooled) cells: an institution that subtracts its own figures from a pooled
  --     cell must not recover another school's. Publish only with at least 3 contributing
  --     institutions and when no institution dominates what is left after removing the second
  --     largest (largest > 70 % of total minus second largest), on both counts.
  update nl.stage_cell s
     set reason = 'floor'
    from nl.stage_cell s0
    left join (with parts as (
            select case a.table_id when 't1_inst_category' then 't1_category_totals' else 't2_step_totals' end as pooled_table,
                   split_part(a.row_key, ':', 2) as pooled_row, a.col_key, a.num, a.denom
              from nl.accumulated_cell a
             where a.table_id in ('t1_inst_category', 't2_inst_step')
          ),
          shares as (
            select pooled_table, pooled_row, col_key,
                   count(*) filter (where denom > 0) as n_inst,
                   sum(denom) as t_d, sum(num) as t_n,
                   (array_agg(denom order by denom desc))[1] as d1,
                   coalesce((array_agg(denom order by denom desc))[2], 0) as d2,
                   (array_agg(num order by num desc))[1] as n1,
                   coalesce((array_agg(num order by num desc))[2], 0) as n2
              from parts
             group by pooled_table, pooled_row, col_key
          )
               select * from shares) sh
      on sh.pooled_table = s0.table_id and sh.pooled_row = s0.row_key and sh.col_key = s0.col_key
   where s.table_id = s0.table_id and s.row_key = s0.row_key and s.col_key = s0.col_key
     and s.reason is null
     and s.table_id in ('t1_category_totals', 't2_step_totals')
     and (sh.pooled_table is null
            or sh.n_inst < 3
            or sh.d1 > 0.7 * (sh.t_d - sh.d2)
            or (sh.t_n > 0 and sh.n1 > 0.7 * (sh.t_n - sh.n2)));

  -- 2. perturb by the cell key (-4..+4, fixed per cell contents, secret to clients), round to the
  --    nearest multiple of five, then derive the rate and its five point band. Published denominators
  --    are clamped to at least 15 (only cells whose true denominator passed the floor are published).
  update nl.stage_cell
     set rate = least(1.000, greatest(0.000, round(num_pub::numeric / denom_pub, 3))),
         band = least(100, greatest(0, (round(num_pub::numeric * 20 / denom_pub) * 5)::integer))
   where reason is null and denom_pub > 0;

  select snapshot_id into v_prev1
    from nl.snapshot where published
   order by snapshot_id desc limit 1;

  -- 3. carry-forward (DISCLOSURE_CONTROL.md §5): if a cell's true counts moved by fewer than
  --    5 contributions since the counts behind its most recent published value, republish that
  --    previous value unchanged. Nothing observable changes, so small changes cannot be
  --    differenced, and the cell is not withheld (a withheld cell would itself signal a change).
  --    The basis counts are carried too, so many small monthly changes add up and are published
  --    once they reach 5. This replaces the former rate-based 'delta' rule and the 'sticky' rule;
  --    sticky could livelock two cells of one column into permanent suppression, and cell-key
  --    noise (±6 per published cell) now covers the subtraction risk sticky was guarding.
  if v_prev1 is not null then
    update nl.stage_cell s
       set num_pub = p.num, denom_pub = p.denom, rate = p.rate, band = p.band,
           num_basis = p.num_true, denom_basis = p.denom_true, carried = true
      from (select distinct on (p.table_id, p.row_key, p.col_key)
                   p.table_id, p.row_key, p.col_key, p.num, p.denom, p.rate, p.band, p.num_true, p.denom_true
              from nl.published_cell p
              join nl.snapshot sn on sn.snapshot_id = p.snapshot_id and sn.published
             order by p.table_id, p.row_key, p.col_key, p.snapshot_id desc) p
     where p.table_id = s.table_id
       and p.row_key = s.row_key
       and p.col_key = s.col_key
       and s.reason is null
       and p.num_true is not null
       and greatest(abs(s.num_true - p.num_true), abs(s.denom_true - p.denom_true)) between 1 and 4;
  end if;

  -- 5. complementary: never leave exactly one published cell in a row or institution-scoped column
  for v_pass in 1..20 loop
    v_hit_row := 0;
    v_hit_col := 0;

    update nl.stage_cell s
       set reason = 'complementary', rate = null, band = null
      from (select s2.table_id as table_id,
                   s2.row_key as row_key,
                   count(*) as total,
                   count(*) filter (where s2.reason is null) as npub
              from nl.stage_cell s2
             group by s2.table_id, s2.row_key) g
     where g.table_id = s.table_id
       and g.row_key = s.row_key
       and s.reason is null
       and g.total > 1
       and g.npub = 1;
    get diagnostics v_hit_row = row_count;

    update nl.stage_cell s
       set reason = 'complementary', rate = null, band = null
      from nl.release_table rt_s,
           (select s2.table_id as table_id,
                   case when rt.row_axis in ('inst_category', 'inst_step', 'inst_region')
                        then split_part(s2.row_key, ':', 1)
                        else '' end as scope_key,
                   s2.col_key as col_key,
                   count(*) as total,
                   count(*) filter (where s2.reason is null) as npub
              from nl.stage_cell s2
              join nl.release_table rt on rt.table_id = s2.table_id
             group by s2.table_id, 2, s2.col_key) g
     where rt_s.table_id = s.table_id
       and g.table_id = s.table_id
       and g.scope_key = (case when rt_s.row_axis in ('inst_category', 'inst_step', 'inst_region')
                               then split_part(s.row_key, ':', 1)
                               else '' end)
       and g.col_key = s.col_key
       and s.reason is null
       and g.total > 1
       and g.npub = 1;
    get diagnostics v_hit_col = row_count;

    -- 5b. secondary: a lone withheld cell in an institution-scoped column can be
    -- recovered from the institution total minus its siblings, so also withhold
    -- the smallest published sibling in that group.
    --     (one grouped pass, then a hash join: linear in the number of cells; the earlier
    --     correlated subquery rescanned the table per candidate and was quadratic)
    update nl.stage_cell s
       set reason = 'complementary', rate = null, band = null
      from (select distinct on (g.table_id, g.scope_key, g.col_key)
                   s2.table_id, s2.row_key, s2.col_key
              from (select s3.table_id, split_part(s3.row_key, ':', 1) as scope_key, s3.col_key
                      from nl.stage_cell s3
                      join nl.release_table rt on rt.table_id = s3.table_id
                     where rt.row_axis in ('inst_category', 'inst_step', 'inst_region')
                     group by s3.table_id, split_part(s3.row_key, ':', 1), s3.col_key
                    having count(*) filter (where s3.reason is not null) = 1) g
              join nl.stage_cell s2
                on s2.table_id = g.table_id
               and split_part(s2.row_key, ':', 1) = g.scope_key
               and s2.col_key = g.col_key
               and s2.reason is null
             order by g.table_id, g.scope_key, g.col_key, s2.denom_true, s2.row_key) v
     where s.table_id = v.table_id
       and s.row_key = v.row_key
       and s.col_key = v.col_key;
    get diagnostics v_hit_sec = row_count;

    exit when v_hit_row = 0 and v_hit_col = 0 and v_hit_sec = 0;
  end loop;

  -- 6. over_suppression: defensive sweep across both axes
  update nl.stage_cell s
     set reason = 'over_suppression', rate = null, band = null
    from (select s2.table_id, s2.row_key,
                 count(*) as total,
                 count(*) filter (where s2.reason is null) as npub
            from nl.stage_cell s2
           group by s2.table_id, s2.row_key) g
   where g.table_id = s.table_id
     and g.row_key = s.row_key
     and s.reason is null
     and g.total > 1
     and g.npub = 1;

  update nl.stage_cell s
     set reason = 'over_suppression', rate = null, band = null
    from nl.release_table rt_s,
         (select s2.table_id as table_id,
                 case when rt.row_axis in ('inst_category', 'inst_step', 'inst_region')
                      then split_part(s2.row_key, ':', 1)
                      else '' end as scope_key,
                 s2.col_key as col_key,
                 count(*) as total,
                 count(*) filter (where s2.reason is null) as npub
            from nl.stage_cell s2
            join nl.release_table rt on rt.table_id = s2.table_id
           group by s2.table_id, 2, s2.col_key) g
   where rt_s.table_id = s.table_id
     and g.table_id = s.table_id
     and g.scope_key = (case when rt_s.row_axis in ('inst_category', 'inst_step', 'inst_region')
                             then split_part(s.row_key, ':', 1)
                             else '' end)
     and g.col_key = s.col_key
     and s.reason is null
     and g.total > 1
     and g.npub = 1;

  select count(*) into v_out from nl.stage_cell where reason is null;
  return v_out;
end;
$fn$;

create or replace function nl.assert_release_safe(p_snapshot bigint)
returns void
language plpgsql
stable
as $fn$
declare
  r record;
begin
  for r in select * from nl.published_cell where snapshot_id = p_snapshot loop
    if r.denom < 15 then
      raise exception 'cell %/%/% published with denom % below the floor',
        r.table_id, r.row_key, r.col_key, r.denom using errcode = '23514';
    end if;
    if r.denom % 5 <> 0 or r.num % 5 <> 0 then
      raise exception 'cell %/%/% is not rounded to five',
        r.table_id, r.row_key, r.col_key using errcode = '23514';
    end if;
    if r.num > r.denom then
      raise exception 'cell %/%/% has num above denom',
        r.table_id, r.row_key, r.col_key using errcode = '23514';
    end if;
    if r.rate < 0 or r.rate > 1 then
      raise exception 'cell %/%/% has a rate outside 0..1',
        r.table_id, r.row_key, r.col_key using errcode = '23514';
    end if;
    if not exists (select 1 from nl.release_table t where t.table_id = r.table_id) then
      raise exception 'cell %/%/% belongs to an undeclared table',
        r.table_id, r.row_key, r.col_key using errcode = '23514';
    end if;
  end loop;

  if exists (select 1
               from nl.published_cell p
               join nl.suppressed_cell s
                 on s.snapshot_id = p.snapshot_id
                and s.table_id = p.table_id
                and s.row_key = p.row_key
                and s.col_key = p.col_key
              where p.snapshot_id = p_snapshot) then
    raise exception 'snapshot % has a cell both published and suppressed', p_snapshot
      using errcode = '23514';
  end if;

  if exists (select 1 from (
               select table_id, row_key,
                      count(*) as total,
                      count(*) filter (where src = 'p') as npub
                 from (select snapshot_id, table_id, row_key, col_key, 'p' as src
                         from nl.published_cell where snapshot_id = p_snapshot
                       union all
                       select snapshot_id, table_id, row_key, col_key, 's'
                         from nl.suppressed_cell where snapshot_id = p_snapshot) u
                group by table_id, row_key) g
              where g.total > 1 and g.npub = 1) then
    raise exception 'snapshot % exposes a lone published cell along a row', p_snapshot
      using errcode = '23514';
  end if;

  if exists (select 1 from (
               select u.table_id,
                      case when rt.row_axis in ('inst_category', 'inst_step', 'inst_region')
                           then split_part(u.row_key, ':', 1)
                           else '' end as scope_key,
                      u.col_key,
                      count(*) as total,
                      count(*) filter (where u.src = 'p') as npub
                 from (select snapshot_id, table_id, row_key, col_key, 'p' as src
                         from nl.published_cell where snapshot_id = p_snapshot
                       union all
                       select snapshot_id, table_id, row_key, col_key, 's'
                         from nl.suppressed_cell where snapshot_id = p_snapshot) u
                 join nl.release_table rt on rt.table_id = u.table_id
                group by u.table_id, 2, u.col_key) g
              where g.total > 1 and g.npub = 1) then
    raise exception 'snapshot % exposes a lone published cell along a column', p_snapshot
      using errcode = '23514';
  end if;
  if exists (select 1 from (
               select u.table_id, split_part(u.row_key, ':', 1) as scope_key, u.col_key,
                      count(*) as total,
                      count(*) filter (where u.src = 's') as nsup
                 from (select table_id, row_key, col_key, 'p' as src
                         from nl.published_cell where snapshot_id = p_snapshot
                       union all
                       select table_id, row_key, col_key, 's'
                         from nl.suppressed_cell where snapshot_id = p_snapshot) u
                 join nl.release_table rt on rt.table_id = u.table_id
                where rt.row_axis in ('inst_category', 'inst_step', 'inst_region')
                group by u.table_id, 2, u.col_key) g
              where g.total > 1 and g.nsup = 1) then
    raise exception 'snapshot % leaves a lone withheld cell in an institution-scoped column', p_snapshot
      using errcode = '23514';
  end if;
  if exists (with parts as (
         select case a.table_id when 't1_inst_category' then 't1_category_totals' else 't2_step_totals' end as pooled_table,
                split_part(a.row_key, ':', 2) as pooled_row, a.col_key, a.num, a.denom
           from nl.accumulated_cell a
          where a.table_id in ('t1_inst_category', 't2_inst_step')
       ),
       shares as (
         select pooled_table, pooled_row, col_key,
                count(*) filter (where denom > 0) as n_inst,
                sum(denom) as t_d, sum(num) as t_n,
                (array_agg(denom order by denom desc))[1] as d1,
                coalesce((array_agg(denom order by denom desc))[2], 0) as d2,
                (array_agg(num order by num desc))[1] as n1,
                coalesce((array_agg(num order by num desc))[2], 0) as n2
           from parts
          group by pooled_table, pooled_row, col_key
       )
             select 1
               from nl.published_cell p
               left join shares sh
                 on sh.pooled_table = p.table_id and sh.pooled_row = p.row_key and sh.col_key = p.col_key
              where p.snapshot_id = p_snapshot
                and p.table_id in ('t1_category_totals', 't2_step_totals')
                and (sh.pooled_table is null
            or sh.n_inst < 3
            or sh.d1 > 0.7 * (sh.t_d - sh.d2)
            or (sh.t_n > 0 and sh.n1 > 0.7 * (sh.t_n - sh.n2)))) then
    raise exception 'snapshot % publishes a benchmark cell with < 3 institutions or a dominant institution', p_snapshot
      using errcode = '23514';
  end if;
end;
$fn$;

create or replace function nl.publish_snapshot(p_note text default null)
returns bigint
language plpgsql
volatile
as $fn$
declare
  v_snap bigint;
  v_open integer;
begin
  perform pg_advisory_xact_lock(hashtext('nl.release'));

  v_open := nl.build_stage();

  insert into nl.snapshot (note, published) values (p_note, false)
  returning snapshot_id into v_snap;

  insert into nl.published_cell (snapshot_id, table_id, row_key, col_key,
                                 num, denom, rate, rate_true, band, num_true, denom_true, carried)
  select v_snap, table_id, row_key, col_key, num_pub, denom_pub, rate,
         least(1.00000, greatest(0.00000, round(num_basis::numeric / denom_basis, 5))), band,
         num_basis, denom_basis, carried
    from nl.stage_cell
   where reason is null;

  insert into nl.suppressed_cell (snapshot_id, table_id, row_key, col_key, reason, bucket)
  select v_snap, table_id, row_key, col_key, reason, nl.bucket(denom_true)
    from nl.stage_cell
   where reason is not null;

  update nl.snapshot
     set published = true, published_at = now()
   where snapshot_id = v_snap;

  perform nl.assert_release_safe(v_snap);

  return v_snap;
exception
  when others then
    delete from nl.snapshot where snapshot_id = v_snap;
    raise;
end;
$fn$;

create or replace function nl.release_json(p_snapshot bigint default null)
returns jsonb
language plpgsql
stable
as $fn$
declare
  v_snap   bigint;
  v_tables jsonb := '[]'::jsonb;
  v_cells  jsonb;
  v_hidden jsonb;
  v_pub    integer;
  v_hide   integer;
  r        record;
begin
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
                'withheld', 0));
  end if;

  for r in select * from nl.release_table order by tier, table_id loop

    select coalesce(jsonb_agg(jsonb_build_object(
             'row', row_key,
             'row_label', nl.dim_label(r.row_axis, row_key),
             'col', col_key,
             'col_label', nl.dim_label(r.col_axis, col_key),
             'num', num,
             'denom', denom,
             'rate', rate,
             'band', band) order by row_key, col_key), '[]'::jsonb)
      into v_cells
      from nl.published_cell
     where snapshot_id = v_snap and table_id = r.table_id;

    select coalesce(jsonb_agg(jsonb_build_object(
             'row', row_key,
             'row_label', nl.dim_label(r.row_axis, row_key),
             'col', col_key,
             'col_label', nl.dim_label(r.col_axis, col_key),
             'reason', reason,
             'bucket', bucket) order by row_key, col_key), '[]'::jsonb)
      into v_hidden
      from nl.suppressed_cell
     where snapshot_id = v_snap and table_id = r.table_id;

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
      'withheld_count', jsonb_array_length(v_hidden)));
  end loop;

  select count(*) into v_pub from nl.published_cell where snapshot_id = v_snap;
  select count(*) into v_hide from nl.suppressed_cell where snapshot_id = v_snap;

  return jsonb_build_object(
    'tables', v_tables,
    'meta', jsonb_build_object(
              'snapshot_id', v_snap,
              'built_at', (select built_at from nl.snapshot where snapshot_id = v_snap),
              'published', true,
              'state', case when v_pub = 0 then 'withheld' else 'ok' end,
              'published_cells', v_pub,
              'withheld', v_hide,
              'note', 'Aggregate counts only. No individual, no account, no link between tier 1 and tier 2.'));
end;
$fn$;

create or replace function nl.stats_json()
returns jsonb
language sql
stable
as $fn$
  select nl.release_json(null);
$fn$;
