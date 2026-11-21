-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- ============================================================================
-- Netherlanded v2.1 — Shared-City Content Editor Privilege Fix
-- ============================================================================
-- Fixes the shared-city privilege escalation vector identified in SECURITY_AUDIT.md:
-- Previously, an institutional editor at one school in a multi-institution city
-- (e.g., Amsterdam, Rotterdam, The Hague, Delft/Leiden) could edit city-wide
-- municipal service cards affecting all other institutions in that city.
--
-- New rule:
--   1. 'super_admin' can always edit any city.
--   2. An institutional 'editor' can only edit city-level records if their
--      institution is mapped to that city AND that city has exactly ONE
--      participating institution in `institution_campuses` (or they edit
--      institution-scoped overrides rather than shared municipal rows).
-- ============================================================================

begin;

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

commit;
