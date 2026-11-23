-- GENERATED from db/002_ingest.sql by tools/sync_supabase.py. Edit the source, not this file.
-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 002_ingest.sql
-- Two independent ingest endpoints. Each accepts a single JSON object,
-- an array of objects, or {events: [...]}. Batches are all-or-nothing.
-- Nothing here stores an identity of any kind.

create or replace function nl.normalize_batch(p jsonb)
returns setof jsonb
language plpgsql
immutable
as $fn$
declare
  v_arr jsonb;
  v_len integer;
begin
  if p is null then
    raise exception 'empty payload' using errcode = '22023';
  end if;

  if jsonb_typeof(p) = 'array' then
    v_arr := p;
  elsif jsonb_typeof(p) = 'object' then
    if p ? 'events' then
      if jsonb_typeof(p -> 'events') <> 'array' then
        raise exception 'events must be an array' using errcode = '22023';
      end if;
      v_arr := p -> 'events';
    else
      v_arr := jsonb_build_array(p);
    end if;
  else
    raise exception 'payload must be an object or an array' using errcode = '22023';
  end if;

  v_len := jsonb_array_length(v_arr);
  if v_len < 1 or v_len > 100 then
    raise exception 'batch size % is outside 1..100', v_len using errcode = '22023';
  end if;

  return query select jsonb_array_elements(v_arr);
end;
$fn$;

create or replace function nl.reject_identity(p jsonb)
returns void
language plpgsql
immutable
as $fn$
declare
  k text;
begin
  for k in select lower(key) from jsonb_object_keys(p) as key loop
    if k in ('sid', 'session_id', 'sessionid', 'user_id', 'userid', 'uid',
             'email', 'ip', 'ip_address', 'installation_id', 'install_id',
             'device_id', 'deviceid') then
      raise exception 'field % is not accepted: this endpoint stores no identifier', k
        using errcode = '22023';
    end if;
  end loop;
end;
$fn$;

-- Deprecated: `n` is no longer an accepted field (it was validated but never stored).
-- Kept only so existing grants/revokes resolve; not called by ingest.
create or replace function nl.check_hint(p jsonb)
returns void
language plpgsql
immutable
as $fn$
begin
  if p ? 'n' then
    if jsonb_typeof(p -> 'n') <> 'number' then
      raise exception 'n must be a number' using errcode = '22023';
    end if;
    if (p ->> 'n')::numeric < 1 or (p ->> 'n')::numeric > 50 then
      raise exception 'n must be between 1 and 50' using errcode = '22023';
    end if;
  end if;
end;
$fn$;

create or replace function nl.ingest_t1(p jsonb)
returns integer
language plpgsql
volatile
as $fn$
declare
  e        jsonb;
  v_key    text;
  v_count  integer := 0;
  v_inst   text;
  v_intake text;
  v_year   integer;
  v_event  text;
  v_cat    text;
  v_ver    text;
  v_ok_inst text[] := '{}';
begin
  for e in select * from nl.normalize_batch(p) loop
    if jsonb_typeof(e) <> 'object' then
      raise exception 'each tier-1 event must be an object' using errcode = '22023';
    end if;
    perform nl.reject_identity(e);

    for v_key in select jsonb_object_keys(e) loop
      if v_key not in ('institution', 'intake', 'event', 'category', 'app_version') then
        raise exception 'unexpected tier-1 field %', v_key using errcode = '22023';
      end if;
    end loop;

    v_inst   := e ->> 'institution';
    v_intake := e ->> 'intake';
    v_event  := e ->> 'event';
    v_cat    := e ->> 'category';
    v_ver    := e ->> 'app_version';

    if v_inst is null or v_intake is null or v_event is null or v_ver is null then
      raise exception 'institution, intake, event and app_version are required'
        using errcode = '22023';
    end if;
    if v_event not in ('step_applies', 'step_completed', 'technical_error', 'cohort_joined') then
      raise exception 'unknown tier-1 event %', v_event using errcode = '22023';
    end if;
    if v_intake !~ '^[0-9]{4}-(sep|feb)$' then
      raise exception 'intake % is not YYYY-sep or YYYY-feb', v_intake using errcode = '22023';
    end if;
    v_year := split_part(v_intake, '-', 1)::integer;
    if v_year < 2024 or v_year > 2040 then
      raise exception 'intake year % is out of bounds', v_year using errcode = '22023';
    end if;
    if v_event in ('step_applies', 'step_completed') then
      if v_cat is null or v_cat not in ('admin', 'housing', 'money', 'health', 'work', 'social', 'wellbeing') then
        raise exception 'invalid or missing tier-1 category %', coalesce(v_cat, '<null>') using errcode = '22023';
      end if;
    else
      if v_cat is not null then
        raise exception 'category must not be set for event %', v_event using errcode = '22023';
      end if;
    end if;
    if v_ver !~ '^[0-9a-z]{4,64}$' then
      raise exception 'app_version % is not a content hash', v_ver using errcode = '22023';
    end if;
    -- validate each distinct institution once per batch
    if not (v_inst = any (v_ok_inst)) then
      if not exists (select 1 from nl.institution i
                      where i.institution = v_inst and i.active) then
        raise exception 'unknown or inactive institution %', v_inst using errcode = '22023';
      end if;
      v_ok_inst := v_ok_inst || v_inst;
    end if;

    insert into nl.raw_t1 (institution, intake, event, category, app_version)
    values (v_inst, v_intake, v_event::nl.t1_event, v_cat::nl.category, v_ver);

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$fn$;

create or replace function nl.ingest_t2(p jsonb)
returns integer
language plpgsql
volatile
as $fn$
declare
  e        jsonb;
  v_key    text;
  v_count  integer := 0;
  v_inst   text;
  v_region text;
  v_intake text;
  v_year   integer;
  v_event  text;
  v_step   text;
  v_hr     boolean;
  v_ok_inst text[] := '{}';
begin
  for e in select * from nl.normalize_batch(p) loop
    if jsonb_typeof(e) <> 'object' then
      raise exception 'each tier-2 event must be an object' using errcode = '22023';
    end if;
    perform nl.reject_identity(e);

    for v_key in select jsonb_object_keys(e) loop
      if v_key not in ('institution', 'region', 'intake', 'event', 'step', 'high_risk') then
        raise exception 'unexpected tier-2 field %', v_key using errcode = '22023';
      end if;
    end loop;

    v_inst   := e ->> 'institution';
    v_region := e ->> 'region';
    v_intake := e ->> 'intake';
    v_event  := e ->> 'event';
    v_step   := e ->> 'step';

    if v_inst is null or v_region is null or v_intake is null or v_event is null then
      raise exception 'institution, region, intake and event are required'
        using errcode = '22023';
    end if;
    if v_event not in ('joined', 'arrived', 'step_applies', 'step_opened',
                       'step_completed', 'deadline_missed', 'scam_checked') then
      raise exception 'unknown tier-2 event %', v_event using errcode = '22023';
    end if;
    if v_intake !~ '^[0-9]{4}-(sep|feb)$' then
      raise exception 'intake % is not YYYY-sep or YYYY-feb', v_intake using errcode = '22023';
    end if;
    v_year := split_part(v_intake, '-', 1)::integer;
    if v_year < 2024 or v_year > 2040 then
      raise exception 'intake year % is out of bounds', v_year using errcode = '22023';
    end if;
    if v_region not in ('eu_eea', 'non_eu') then
      raise exception 'region % is not allowed', v_region using errcode = '22023';
    end if;
    if v_step is not null and v_step !~ '^[a-z0-9_]{2,32}$' then
      raise exception 'step % is not a slug', v_step using errcode = '22023';
    end if;
    if e ? 'high_risk' then
      if jsonb_typeof(e -> 'high_risk') <> 'boolean' then
        raise exception 'high_risk must be a boolean' using errcode = '22023';
      end if;
      if v_event <> 'scam_checked' then
        raise exception 'high_risk is only accepted on scam_checked events' using errcode = '22023';
      end if;
      v_hr := (e ->> 'high_risk')::boolean;
    else
      v_hr := false;
    end if;
    -- validate each distinct institution once per batch
    if not (v_inst = any (v_ok_inst)) then
      if not exists (select 1 from nl.institution i
                      where i.institution = v_inst and i.active) then
        raise exception 'unknown or inactive institution %', v_inst using errcode = '22023';
      end if;
      v_ok_inst := v_ok_inst || v_inst;
    end if;

    insert into nl.raw_t2 (institution, region, intake, event, step, high_risk)
    values (v_inst, v_region, v_intake, v_event::nl.t2_event, v_step,
            case when v_event = 'scam_checked' then v_hr else null end);

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$fn$;
