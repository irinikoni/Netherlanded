-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 001_schema.sql
-- PostgreSQL 15 or newer.
-- Aggregate-only analytics for the Netherlanded settlement app.
-- Tier 1 and Tier 2 are separate stores. Nothing joins them.

begin;

create schema if not exists nl;

do $do$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'nl' and t.typname = 't1_event') then
    create type nl.t1_event as enum ('step_applies', 'step_completed', 'technical_error', 'cohort_joined');
  end if;
end $do$;

do $do$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'nl' and t.typname = 't2_event') then
    create type nl.t2_event as enum ('joined', 'arrived', 'step_applies', 'step_opened',
                                     'step_completed', 'deadline_missed', 'scam_checked');
  end if;
end $do$;

do $do$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'nl' and t.typname = 'category') then
    create type nl.category as enum ('admin', 'housing', 'money', 'health', 'work', 'social', 'wellbeing');
  end if;
end $do$;

do $do$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'nl' and t.typname = 'suppress_reason') then
    create type nl.suppress_reason as enum ('floor', 'delta', 'sticky',
                                            'complementary', 'over_suppression');
  end if;
end $do$;

create table if not exists nl.institution (
  institution  text primary key,
  display_name text not null,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  constraint institution_key_chk check (institution ~ '^[a-z0-9_-]{2,32}$')
);

create table if not exists nl.step_vocab (
  step     text primary key,
  ord      integer not null,
  is_known boolean not null default true,
  constraint step_key_chk check (step ~ '^[a-z0-9_]{2,32}$')
);

insert into nl.step_vocab (step, ord, is_known) values ('other', 999, false)
on conflict (step) do nothing;

create table if not exists nl.release_table (
  table_id text primary key,
  title    text not null,
  tier     smallint not null check (tier in (1, 2)),
  row_axis text not null,
  col_axis text not null,
  metric   text not null
);

insert into nl.release_table (table_id, title, tier, row_axis, col_axis, metric) values
  ('t1_institution_intake', 'Steps started and finished, by arrival semester',
   1, 'institution', 'intake', 'completed / started'),
  ('t1_category_totals', 'Steps started and finished, by category',
   1, 'category', 'intake', 'completed / started'),
  ('t1_error_rate', 'Technical errors, by arrival semester',
   1, 'institution', 'intake', 'errors / events'),
  ('t2_institution_intake', 'Arrivals, by arrival semester',
   2, 'institution', 'intake', 'arrived / joined'),
  ('t2_step_totals', 'Journey steps, by arrival semester',
   2, 'step', 'intake', 'completed / started')
on conflict (table_id) do nothing;

create table if not exists nl.snapshot (
  snapshot_id  bigserial primary key,
  built_at     timestamptz not null default now(),
  published    boolean not null default false,
  published_at timestamptz,
  note         text
);

create table if not exists nl.raw_t1 (
  id          bigserial primary key,
  institution text not null references nl.institution (institution),
  intake      text not null,
  event       nl.t1_event not null,
  category    nl.category,
  app_version text not null,
  received_at timestamptz not null default date_trunc('hour', now()),
  week_start  date not null default ((date_trunc('week', now()))::date),
  fold_run    bigint,
  constraint raw_t1_intake_chk check (intake ~ '^[0-9]{4}-(sep|feb)$'),
  constraint raw_t1_version_chk check (app_version ~ '^[0-9a-z]{4,64}$')
);

create index if not exists raw_t1_unfolded_idx on nl.raw_t1 (id) where fold_run is null;
create index if not exists raw_t1_received_idx on nl.raw_t1 (received_at);
create index if not exists raw_t1_fold_run_idx on nl.raw_t1 (fold_run) where fold_run is not null;

create table if not exists nl.raw_t2 (
  id          bigserial primary key,
  institution text not null references nl.institution (institution),
  region      text not null,
  intake      text not null,
  event       nl.t2_event not null,
  step        text,
  high_risk   boolean,
  received_at timestamptz not null default date_trunc('hour', now()),
  week_start  date not null default ((date_trunc('week', now()))::date),
  fold_run    bigint,
  constraint raw_t2_region_chk check (region ~ '^[a-z0-9_-]{2,32}$'),
  constraint raw_t2_intake_chk check (intake ~ '^[0-9]{4}-(sep|feb)$'),
  constraint raw_t2_step_chk check (step is null or step ~ '^[a-z0-9_]{2,32}$')
);

create index if not exists raw_t2_unfolded_idx on nl.raw_t2 (id) where fold_run is null;
create index if not exists raw_t2_received_idx on nl.raw_t2 (received_at);
create index if not exists raw_t2_fold_run_idx on nl.raw_t2 (fold_run) where fold_run is not null;

-- Hour-truncated arrival times: exact timestamps could link a tier-1 and a
-- tier-2 event sent in the same moment. Re-applied for existing databases.
alter table nl.raw_t1 alter column received_at set default date_trunc('hour', now());
alter table nl.raw_t2 alter column received_at set default date_trunc('hour', now());

create table if not exists nl.unmapped_value (
  id         bigserial primary key,
  field      text not null,
  value      text not null,
  hits       bigint not null default 0,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  unique (field, value)
);

create table if not exists nl.accumulation_run (
  run_id      bigserial primary key,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  max_t1      bigint,
  max_t2      bigint,
  cells       bigint
);

create table if not exists nl.accumulated_cell (
  table_id   text not null references nl.release_table (table_id),
  row_key    text not null,
  col_key    text not null,
  num        bigint not null default 0 check (num >= 0),
  denom      bigint not null default 0 check (denom >= 0),
  updated_at timestamptz not null default now(),
  primary key (table_id, row_key, col_key)
);

create table if not exists nl.t1_cohort (
  institution  text not null,
  intake       text not null,
  contributors bigint not null default 0 check (contributors >= 0),
  updated_at   timestamptz not null default now(),
  primary key (institution, intake)
);

create table if not exists nl.t2_base (
  institution text not null,
  intake      text not null,
  joined      bigint not null default 0 check (joined >= 0),
  arrived     bigint not null default 0 check (arrived >= 0),
  updated_at  timestamptz not null default now(),
  primary key (institution, intake)
);

create table if not exists nl.t2_region_base (
  institution text not null,
  region      text not null,
  intake      text not null,
  joined      bigint not null default 0 check (joined >= 0),
  updated_at  timestamptz not null default now(),
  primary key (institution, region, intake)
);

create table if not exists nl.stage_cell (
  table_id   text not null,
  row_key    text not null,
  col_key    text not null,
  num_true   bigint not null,
  denom_true bigint not null,
  num_pub    bigint,
  denom_pub  bigint,
  rate       numeric(4, 3),
  band       smallint,
  reason     nl.suppress_reason,
  built_at   timestamptz not null default now(),
  primary key (table_id, row_key, col_key)
);

create table if not exists nl.published_cell (
  snapshot_id bigint not null references nl.snapshot (snapshot_id) on delete cascade,
  table_id    text not null,
  row_key     text not null,
  col_key     text not null,
  num         bigint not null,
  denom       bigint not null,
  rate        numeric(4, 3) not null,
  rate_true   numeric(7, 5) not null,
  band        smallint,
  primary key (snapshot_id, table_id, row_key, col_key)
);

create index if not exists published_cell_history_idx
  on nl.published_cell (table_id, row_key, col_key, snapshot_id desc);

create table if not exists nl.suppressed_cell (
  snapshot_id bigint not null references nl.snapshot (snapshot_id) on delete cascade,
  table_id    text not null,
  row_key     text not null,
  col_key     text not null,
  reason      nl.suppress_reason not null,
  bucket      text not null check (bucket in ('<15', '15-49', '50-99', '100+')),
  primary key (snapshot_id, table_id, row_key, col_key)
);

create or replace function nl.bucket(p_n bigint)
returns text
language sql
immutable
as $fn$
  select case
           when p_n is null then '<15'
           when p_n < 15  then '<15'
           when p_n < 50  then '15-49'
           when p_n < 100 then '50-99'
           else '100+'
         end;
$fn$;

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
           else initcap(replace(p_key, '_', ' '))
         end;
$fn$;


-- Cell-key perturbation (defence against n-1 flooding; see DISCLOSURE_CONTROL.md §3a).
-- Every raw event gets a secret, server-assigned record key in 0..251. Each published
-- cell carries the sum of its contributors' keys (mod 252); nl.cell_noise() turns that
-- cell key into a fixed perturbation of -4..+4 applied before rounding. Clients cannot
-- choose or see keys, so an attacker who floods a cell with fake events cannot place it
-- on a rounding boundary, and an unchanged cell always gets the same noise.
create or replace function nl.new_record_key()
returns smallint
language sql
volatile
as $fn$
  select ((get_byte(b, 0) * 256 + get_byte(b, 1)) % 252)::smallint
    from (select uuid_send(gen_random_uuid()) as b) x;
$fn$;

create or replace function nl.cell_noise(p_key bigint)
returns integer
language sql
immutable
as $fn$
  -- 252 is divisible by 9, so a uniform key gives a uniform -4..+4; key 0 gives 0.
  select (((coalesce(p_key, 0) % 252) % 9 + 4) % 9 - 4)::integer;
$fn$;

alter table nl.raw_t1 add column if not exists rkey smallint not null default nl.new_record_key()
  check (rkey between 0 and 251);
alter table nl.raw_t2 add column if not exists rkey smallint not null default nl.new_record_key()
  check (rkey between 0 and 251);
alter table nl.accumulated_cell add column if not exists num_key   integer not null default 0;
alter table nl.accumulated_cell add column if not exists denom_key integer not null default 0;
alter table nl.t2_base add column if not exists joined_key  integer not null default 0;
alter table nl.t2_base add column if not exists arrived_key integer not null default 0;

-- Carry-forward (§5): the true counts behind each published value, kept internally (never
-- returned to readers) so the next release can tell whether fewer than 5 contributions changed.
alter table nl.stage_cell add column if not exists num_basis   bigint;
alter table nl.stage_cell add column if not exists denom_basis bigint;
alter table nl.stage_cell add column if not exists carried     boolean not null default false;
alter table nl.published_cell add column if not exists num_true   bigint;
alter table nl.published_cell add column if not exists denom_true bigint;
alter table nl.published_cell add column if not exists carried    boolean not null default false;

commit;
