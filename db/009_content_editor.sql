-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 009_content_editor.sql
-- PostgreSQL 15+ (applied after 005_content_editor_security_fix.sql / auth.jwt() shim in tests).
-- Isolated content-editor schema (`nl_content`), campus ownership guard,
-- versioned facts with auto-closing history, append-only staff audit log,
-- and tenant-scoped SECURITY DEFINER RPCs.

begin;

create schema if not exists nl_content;

-- 1. Ensure campus-to-city mapping exists for shared-city ownership checks
create table if not exists public.institution_campuses (
  institution_id text not null,
  city_id        text not null,
  primary key (institution_id, city_id)
);

delete from public.institution_campuses
 where institution_id in ('tudelft', 'leiden-th', 'wur');

insert into public.institution_campuses (institution_id, city_id) values
  -- Study cities (18) rolled up to parent institution IDs
  ('uva', 'amsterdam'),
  ('vu', 'amsterdam'),
  ('hva', 'amsterdam'),
  ('saxion', 'apeldoorn'),
  ('tud', 'delft'),
  ('thuas', 'delft'),
  ('saxion', 'deventer'),
  ('tue', 'eindhoven'),
  ('fontys', 'eindhoven'),
  ('utwente', 'enschede'),
  ('saxion', 'enschede'),
  ('rug', 'groningen'),
  ('hanze', 'groningen'),
  ('zuyd', 'heerlen'),
  ('rug', 'leeuwarden'),
  ('leiden', 'leiden'),
  ('um', 'maastricht'),
  ('zuyd', 'maastricht'),
  ('eur', 'rotterdam'),
  ('hr', 'rotterdam'),
  ('zuyd', 'sittard-geleen'),
  ('thuas', 'the-hague'),
  ('leiden', 'the-hague'),
  ('fontys', 'tilburg'),
  ('uu', 'utrecht'),
  ('hu', 'utrecht'),
  ('fontys', 'venlo'),
  ('um', 'venlo'),
  ('thuas', 'zoetermeer'),
  -- Commuter municipalities (16) inheriting their near_city_id institutions
  ('uva', 'amstelveen'),
  ('vu', 'amstelveen'),
  ('hva', 'amstelveen'),
  ('uva', 'diemen'),
  ('vu', 'diemen'),
  ('hva', 'diemen'),
  ('eur', 'capelle-aan-den-ijssel'),
  ('hr', 'capelle-aan-den-ijssel'),
  ('eur', 'schiedam'),
  ('hr', 'schiedam'),
  ('utwente', 'hengelo'),
  ('saxion', 'hengelo'),
  ('thuas', 'leidschendam-voorburg'),
  ('leiden', 'leidschendam-voorburg'),
  ('uu', 'nieuwegein'),
  ('hu', 'nieuwegein'),
  ('uu', 'zeist'),
  ('hu', 'zeist'),
  ('tue', 'nuenen'),
  ('fontys', 'nuenen'),
  ('tue', 'son-en-breugel'),
  ('fontys', 'son-en-breugel'),
  ('tue', 'veldhoven'),
  ('fontys', 'veldhoven'),
  ('leiden', 'oegstgeest'),
  ('leiden', 'voorschoten'),
  ('tud', 'rijswijk'),
  ('thuas', 'rijswijk'),
  ('rug', 'tynaarlo'),
  ('hanze', 'tynaarlo'),
  ('rug', 'westerkwartier'),
  ('hanze', 'westerkwartier')
on conflict (institution_id, city_id) do nothing;

-- Keep public.can_edit_city consistent with 005_content_editor_security_fix.sql
create or replace function public.can_edit_city(p_city_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    case
      when coalesce(auth.jwt()->'app_metadata'->>'role', '') = 'super_admin' then true
      when coalesce(auth.jwt()->'app_metadata'->>'role', '') = 'editor' then (
        exists (
          select 1
          from public.institution_campuses ic
          where ic.city_id = p_city_id
            and ic.institution_id = coalesce(auth.jwt()->'app_metadata'->>'institution_id', '')
        )
        and (
          select count(distinct ic2.institution_id)
          from public.institution_campuses ic2
          where ic2.city_id = p_city_id
        ) = 1
      )
      else false
    end;
$$;

revoke execute on function public.can_edit_city(text) from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function public.can_edit_city(text) to authenticated';
  end if;
end $$;

-- 2. Content editor tables
create table if not exists nl_content.service (
  service_id         text primary key check (service_id ~ '^[a-z0-9_-]{2,64}$'),
  name               text not null check (length(trim(name)) between 2 and 200),
  service_type       text not null constraint service_service_type_check check (service_type in ('gp', 'housing', 'support', 'community', 'government', 'banking', 'legal', 'municipal', 'other')),
  city_id            text not null check (city_id ~ '^[a-z0-9-]{2,64}$'),
  municipality_id    text not null check (municipality_id ~ '^[a-z0-9-]{2,64}$'),
  for_institution_id text,
  description        text not null check (length(trim(description)) between 2 and 2000),
  url                text not null constraint service_url_check check (url ~ '^https?://[^\s"''<>]+$'),
  accepting_students text,
  related_step_id    text,
  source_id          text,
  last_verified      date not null default current_date,
  updated_at         timestamptz not null default now(),
  updated_by         text
);

alter table nl_content.service drop constraint if exists service_service_type_check;
alter table nl_content.service add constraint service_service_type_check
  check (service_type in ('gp', 'housing', 'support', 'community', 'government', 'banking', 'legal', 'municipal', 'other'));
alter table nl_content.service drop constraint if exists service_url_check;
alter table nl_content.service add constraint service_url_check
  check (url ~ '^https?://[^\s"''<>]+$');

create table if not exists nl_content.step_local (
  step_id            text not null check (step_id ~ '^[a-z0-9_-]{2,64}$'),
  municipality_id    text not null check (municipality_id ~ '^[a-z0-9-]{2,64}$'),
  for_institution_id text not null default '',
  body               text not null check (length(trim(body)) between 2 and 4000),
  links              jsonb not null default '[]'::jsonb,
  last_verified      date not null default current_date,
  updated_at         timestamptz not null default now(),
  updated_by         text,
  primary key (step_id, municipality_id, for_institution_id)
);

create table if not exists nl_content.fact (
  fact_id       bigserial primary key,
  fact_key      text not null check (fact_key ~ '^[a-z0-9_]{2,64}$'),
  label         text not null check (length(trim(label)) between 2 and 200),
  value         text not null check (length(trim(value)) between 1 and 200),
  unit          text,
  source_id     text not null check (length(trim(source_id)) between 2 and 64),
  step_id       text,
  valid_from    date not null default current_date,
  valid_to      date,
  last_verified date not null default current_date,
  updated_at    timestamptz not null default now(),
  updated_by    text
);

create unique index if not exists idx_fact_current
  on nl_content.fact (fact_key)
  where valid_to is null;

create or replace function nl_content.on_fact_insert()
returns trigger
language plpgsql
as $fn$
begin
  new.valid_from := coalesce(new.valid_from, current_date);
  new.valid_to := null;
  update nl_content.fact
     set valid_to = new.valid_from,
         updated_at = now()
   where fact_key = new.fact_key
     and valid_to is null;
  return new;
end;
$fn$;

drop trigger if exists on_fact_insert on nl_content.fact;
create trigger on_fact_insert
  before insert on nl_content.fact
  for each row execute function nl_content.on_fact_insert();

create table if not exists nl_content.staff_change (
  change_id         bigserial primary key,
  changed_at        timestamptz not null default now(),
  actor_sub         text not null,
  actor_role        text not null,
  actor_institution text,
  entity_type       text not null check (entity_type in ('service', 'step_local', 'fact')),
  entity_key        text not null,
  action            text not null check (action in ('create', 'update', 'publish', 'verify')),
  before_json       jsonb,
  after_json        jsonb,
  reason            text not null check (length(trim(reason)) >= 3)
);

create or replace function nl_content.guard_staff_change_immutable()
returns trigger
language plpgsql
as $fn$
begin
  raise exception 'staff_change is append-only' using errcode = '42501';
end;
$fn$;

drop trigger if exists guard_staff_change_immutable on nl_content.staff_change;
create trigger guard_staff_change_immutable
  before update or delete on nl_content.staff_change
  for each row execute function nl_content.guard_staff_change_immutable();

-- 3. Seed representative baseline content (idempotent)
insert into nl_content.service (
  service_id, name, service_type, city_id, municipality_id, for_institution_id,
  description, url, accepting_students, related_step_id, source_id, last_verified, updated_by
) values
  ('thuas_io', 'THUAS International Office', 'support', 'the-hague', 'the-hague', 'thuas',
   'Arrival guidance, residence permit scheduling, and student registration support for incoming THUAS students.',
   'https://www.thuas.com/study-choice/international-office', 'yes', 'collect_permit', 'thuas-arrival', '2026-11-12', 'seed'),
  ('thuas_housing', 'THUAS Housing Service', 'housing', 'the-hague', 'the-hague', 'thuas',
   'Trusted partner rooms for roughly half of incoming first-year international students without a Dutch address.',
   'https://www.thuas.com/study-choice/international-office/housing', 'limited', 'find_housing', 'thuas-housing', '2026-11-12', 'seed'),
  ('the_student_doctors', 'The Student Doctors', 'gp', 'the-hague', 'the-hague', null,
   'Student-oriented general practice in The Hague listed as open to international students.',
   'https://www.thestudentdoctors.nl/', 'yes', 'register_gp', 'leiden-gp', '2026-10-19', 'seed'),
  ('biking_doctors', 'Biking Doctors', 'gp', 'the-hague', 'the-hague', null,
   'English-speaking GP service operating in The Hague and surrounding municipalities.',
   'https://www.bikingdoctors.nl/', 'yes', 'register_gp', 'leiden-gp', '2026-04-01', 'seed'),
  ('zoetermeer_desk', 'Gemeente Zoetermeer BRP Desk', 'municipal', 'zoetermeer', 'zoetermeer', null,
   'Municipal registration (BRP) and BSN appointment counter for students living in Zoetermeer.',
   'https://www.zoetermeer.nl/', 'yes', 'register_municipality', 'zoetermeer-brp', '2026-10-19', 'seed')
on conflict (service_id) do nothing;

insert into nl_content.step_local (
  step_id, municipality_id, for_institution_id, body, links, last_verified, updated_by
) values
  ('register_municipality', 'the-hague', '',
   'Register in person at The Hague International Centre / City Hall within 5 days of arrival if staying over 4 months.',
   '[{"label":"The Hague International Centre","url":"https://www.thehagueinternationalcentre.nl/"}]'::jsonb,
   '2026-10-19', 'seed'),
  ('find_housing', 'the-hague', 'thuas',
   'Apply immediately via the THUAS Housing Service portal once conditionally admitted; rooms fill within hours of opening.',
   '[{"label":"THUAS Housing","url":"https://www.thuas.com/study-choice/international-office/housing"}]'::jsonb,
   '2026-11-12', 'seed'),
  ('register_municipality', 'zoetermeer', '',
   'Book an in-person BRP appointment with Gemeente Zoetermeer within 5 days of moving into your Zoetermeer address.',
   '[{"label":"Gemeente Zoetermeer","url":"https://www.zoetermeer.nl/"}]'::jsonb,
   '2026-10-19', 'seed')
on conflict (step_id, municipality_id, for_institution_id) do nothing;

insert into nl_content.fact (fact_key, label, value, unit, source_id, step_id, valid_from, last_verified, updated_by)
select v.fact_key, v.label, v.value, v.unit, v.source_id, v.step_id, v.valid_from, v.last_verified, 'seed'
from (values
  ('cak_fine_eur', 'CAK fine for being uninsured', '529.74', 'EUR', 'cak-fine-en', 'cak_letter', date '2026-01-01', date '2026-10-19'),
  ('brp_deadline_days', 'Register in person within', '5', 'days of arrival', 'nlww-brp', 'register_municipality', date '2025-01-01', date '2026-10-19'),
  ('bank_bsn_deadline_days', 'Deadline to add BSN to bank account', '90-120', 'days', 'uva-bank', 'add_bsn_bank', date '2025-01-01', date '2026-03-15'),
  ('duo_min_hours_month', 'Work needed for student finance (DUO rule)', 'at least 32', 'hours/month', 'dutchreview-duo', 'student_finance', date '2023-09-01', date '2026-10-19')
) as v(fact_key, label, value, unit, source_id, step_id, valid_from, last_verified)
where not exists (select 1 from nl_content.fact f where f.fact_key = v.fact_key);

-- 4. Enable Row Level Security (default deny for direct table access)
alter table nl_content.service      enable row level security;
alter table nl_content.step_local   enable row level security;
alter table nl_content.fact         enable row level security;
alter table nl_content.staff_change enable row level security;

-- 5. Internal caller & validation helpers
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
  v_priv    boolean := (v_caller not in ('anon', 'authenticated'))
                       and (session_user not in ('anon', 'authenticated'))
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

create or replace function nl_content._validate_links(p_links jsonb)
returns jsonb
language plpgsql
immutable
as $fn$
declare
  v_item jsonb;
  v_url  text;
begin
  if p_links is null then
    return '[]'::jsonb;
  end if;
  if jsonb_typeof(p_links) <> 'array' or jsonb_array_length(p_links) > 10 then
    raise exception 'links must be a JSON array of at most 10 items' using errcode = '22023';
  end if;
  for v_item in select * from jsonb_array_elements(p_links) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'each link must be a JSON object' using errcode = '22023';
    end if;
    v_url := coalesce(v_item ->> 'url', '');
    if v_url !~ '^https?://[^\s"''<>]+$' then
      raise exception 'invalid link url scheme' using errcode = '22023';
    end if;
  end loop;
  return p_links;
end;
$fn$;

-- 6. SECURITY DEFINER editor RPCs
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
               or (s.for_institution_id is null and public.can_edit_city(s.municipality_id)),
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
    if v_ctx.role not in ('super_admin', 'editor') then
      raise exception 'forbidden editor role' using errcode = '42501';
    end if;
    if v_ctx.role <> 'super_admin' and v_ctx.institution_id = '' then
      raise exception 'missing institution scope' using errcode = '42501';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'change reason is required (min 3 characters)' using errcode = '22023';
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
  v_verified   := coalesce(nullif(trim(p_payload ->> 'last_verified'), '')::date, current_date);
  if v_verified > current_date then
    raise exception 'last_verified cannot be in the future' using errcode = '22023';
  end if;

  if v_service_id is null or v_service_id !~ '^[a-z0-9_-]{2,64}$' then
    raise exception 'invalid service_id' using errcode = '22023';
  end if;
  if v_name is null or v_type is null or v_city is null or v_muni is null or v_desc is null or v_url is null then
    raise exception 'missing required service fields' using errcode = '22023';
  end if;
  if v_url !~ '^https?://[^\s"''<>]+$' then
    raise exception 'invalid url scheme' using errcode = '22023';
  end if;

  select * into v_existing from nl_content.service where service_id = v_service_id;
  v_has_old := found;
  if v_has_old then
    v_before_json := to_jsonb(v_existing);
    if v_ctx.role <> 'super_admin' then
      if not coalesce(
        v_existing.for_institution_id = v_ctx.institution_id
        or (v_existing.for_institution_id is null and public.can_edit_city(v_existing.municipality_id)),
        false
      ) then
        raise exception 'forbidden: cannot modify existing service outside institution scope' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_ctx.role <> 'super_admin' then
    if not coalesce(
      v_for_inst = v_ctx.institution_id
      or (v_for_inst is null and public.can_edit_city(v_muni)),
      false
    ) then
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
    if v_ctx.role not in ('super_admin', 'editor') then
      raise exception 'forbidden editor role' using errcode = '42501';
    end if;
    if v_ctx.role <> 'super_admin' and v_ctx.institution_id = '' then
      raise exception 'missing institution scope' using errcode = '42501';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'change reason is required (min 3 characters)' using errcode = '22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be a JSON object' using errcode = '22023';
  end if;

  v_step_id  := nullif(trim(p_payload ->> 'step_id'), '');
  v_muni     := nullif(trim(p_payload ->> 'municipality_id'), '');
  v_for_inst := coalesce(nullif(trim(p_payload ->> 'for_institution_id'), ''), '');
  v_body     := nullif(trim(p_payload ->> 'body'), '');
  v_links    := nl_content._validate_links(p_payload -> 'links');
  v_verified := coalesce(nullif(trim(p_payload ->> 'last_verified'), '')::date, current_date);
  if v_verified > current_date then
    raise exception 'last_verified cannot be in the future' using errcode = '22023';
  end if;

  if v_step_id is null or v_step_id !~ '^[a-z0-9_-]{2,64}$' or v_muni is null or v_muni !~ '^[a-z0-9-]{2,64}$' or v_body is null then
    raise exception 'invalid or missing step_local fields' using errcode = '22023';
  end if;

  if v_ctx.role <> 'super_admin' then
    if not (
      v_for_inst = v_ctx.institution_id
      or (v_for_inst = '' and public.can_edit_city(v_muni))
    ) then
      raise exception 'forbidden: shared city step_local requires institution override or super_admin' using errcode = '42501';
    end if;
  end if;

  select * into v_existing
    from nl_content.step_local
   where step_id = v_step_id
     and municipality_id = v_muni
     and for_institution_id = v_for_inst;
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
  v_old_json    jsonb;
  v_saved       nl_content.fact%rowtype;
begin
  select * into v_ctx from nl_content._caller_context();
  if not v_ctx.is_privileged and v_ctx.role <> 'super_admin' then
    raise exception 'forbidden: only super_admin may publish national facts' using errcode = '42501';
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'change reason is required (min 3 characters)' using errcode = '22023';
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
  v_valid_from := coalesce(nullif(trim(p_payload ->> 'valid_from'), '')::date, current_date);
  v_verified   := coalesce(nullif(trim(p_payload ->> 'last_verified'), '')::date, current_date);
  if v_verified > current_date then
    raise exception 'last_verified cannot be in the future' using errcode = '22023';
  end if;

  if v_fact_key is null or v_fact_key !~ '^[a-z0-9_]{2,64}$' or v_label is null or v_value is null or v_source_id is null then
    raise exception 'invalid or missing fact fields' using errcode = '22023';
  end if;

  select to_jsonb(f) into v_old_json
    from nl_content.fact f
   where f.fact_key = v_fact_key and f.valid_to is null;

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
begin
  select * into v_ctx from nl_content._caller_context();
  if not v_ctx.is_privileged then
    if v_ctx.role not in ('super_admin', 'editor') then
      raise exception 'forbidden editor role' using errcode = '42501';
    end if;
    if v_ctx.role <> 'super_admin' and v_ctx.institution_id = '' then
      raise exception 'missing institution scope' using errcode = '42501';
    end if;
  end if;

  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'verification reason is required (min 3 characters)' using errcode = '22023';
  end if;

  if p_entity_type = 'service' then
    select * into v_svc from nl_content.service where service_id = p_entity_key;
    if not found then
      raise exception 'unknown service %', p_entity_key using errcode = '22023';
    end if;
    if v_ctx.role <> 'super_admin' and not coalesce(
      v_svc.for_institution_id = v_ctx.institution_id
      or (v_svc.for_institution_id is null and public.can_edit_city(v_svc.municipality_id)),
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

  elsif p_entity_type = 'step_local' then
    v_step := split_part(p_entity_key, '|', 1);
    v_muni := split_part(p_entity_key, '|', 2);
    v_inst := coalesce(split_part(p_entity_key, '|', 3), '');
    select * into v_sl
      from nl_content.step_local
     where step_id = v_step and municipality_id = v_muni and for_institution_id = v_inst;
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
    select * into v_fact from nl_content.fact where fact_key = p_entity_key and valid_to is null;
    if not found then
      raise exception 'unknown active fact %', p_entity_key using errcode = '22023';
    end if;
    v_old_json := to_jsonb(v_fact);
    update nl_content.fact
       set last_verified = current_date, updated_at = now(), updated_by = v_ctx.actor_sub
     where fact_id = v_fact.fact_id
     returning * into v_fact;
    v_new_json := to_jsonb(v_fact);

  else
    raise exception 'unknown entity_type %', p_entity_type using errcode = '22023';
  end if;

  insert into nl_content.staff_change (
    actor_sub, actor_role, actor_institution, entity_type, entity_key,
    action, before_json, after_json, reason
  ) values (
    v_ctx.actor_sub, v_ctx.role, nullif(v_ctx.institution_id, ''),
    p_entity_type, p_entity_key, 'verify',
    v_old_json, v_new_json, trim(p_reason)
  );

  return v_new_json || jsonb_build_object('editable', true);
end;
$fn$;

-- 7. Permissions & grants (least privilege)
revoke all on schema nl_content from public;
revoke all on all tables in schema nl_content from public;
revoke all on all sequences in schema nl_content from public;
revoke all on all functions in schema nl_content from public;

do $grants$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke usage on schema nl_content from anon';
    execute 'revoke all on all tables in schema nl_content from anon';
    execute 'revoke execute on all functions in schema nl_content from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant usage on schema nl_content to authenticated';
    execute 'revoke all on all tables in schema nl_content from authenticated';
    execute 'grant execute on function nl_content.editor_list(text) to authenticated';
    execute 'grant execute on function nl_content.editor_upsert_service(jsonb, text) to authenticated';
    execute 'grant execute on function nl_content.editor_upsert_step_local(jsonb, text) to authenticated';
    execute 'grant execute on function nl_content.editor_publish_fact(jsonb, text) to authenticated';
    execute 'grant execute on function nl_content.editor_mark_verified(text, text, text) to authenticated';
  end if;
end
$grants$;

commit;
