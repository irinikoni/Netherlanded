-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- netherlanded-analytics :: 012_health_ping.sql
-- Dead-man's-switch monitoring for nl.health().
--
-- Every 5 minutes pg_cron runs nl.health_ping(), which calls an external check URL
-- (e.g. a Healthchecks.io check):
--   * health ok            -> GET <url>          (the check stays green)
--   * health not ok / error-> GET <url>/fail     (immediate alert)
--   * nothing at all       -> the check times out and alerts, which also covers a stopped
--                             pg_cron, a paused project or a missing secret.
-- The request carries no data: no body, no query string, nothing from the database.
--
-- The URL is stored in Supabase Vault, never in this repository. Set it once, in the SQL editor:
--   select vault.create_secret('https://hc-ping.com/<uuid>', 'health_ping_url');
-- Rotate it with vault.update_secret(). Without the secret the function does nothing.
begin;

create or replace function nl.health_ping()
returns void
language plpgsql
security definer
set search_path = nl, pg_temp
as $fn$
declare
  v_url text;
  v_ok  boolean;
begin
  -- Late-bound on purpose: vault and net exist on Supabase, not on a plain test database.
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'health_ping_url' limit 1$q$
     into v_url;
  if v_url is null or v_url = '' then
    return;
  end if;

  begin
    v_ok := coalesce((nl.health() ->> 'ok')::boolean, false);
  exception when others then
    v_ok := false;
  end;

  if v_ok then
    execute 'select net.http_get(url := $1, timeout_milliseconds := 5000)' using v_url;
  else
    execute 'select net.http_get(url := $1, timeout_milliseconds := 5000)'
      using rtrim(v_url, '/') || '/fail';
  end if;
end;
$fn$;

alter function nl.health_ping() set search_path = nl, pg_temp;
revoke all on function nl.health_ping() from public;

do $mon$
declare
  v_jid bigint;
begin
  if exists (select 1 from pg_roles where rolname in ('anon', 'authenticated')) then
    execute 'revoke execute on function nl.health_ping() from anon, authenticated';
  end if;

  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not enabled: skipping the nl-health-ping schedule';
    return;
  end if;
  if not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'pg_net not available: skipping the nl-health-ping schedule';
    return;
  end if;

  create extension if not exists pg_net;

  for v_jid in select jobid from cron.job where jobname = 'nl-health-ping' loop
    perform cron.unschedule(v_jid);
  end loop;
  perform cron.schedule('nl-health-ping', '*/5 * * * *', $$select nl.health_ping()$$);
end
$mon$;

commit;
