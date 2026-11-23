-- GENERATED from db/010_function_search_path.sql by tools/sync_supabase.py. Edit the source, not this file.
-- Copyright (c) 2026 Eirini Konidari. All rights reserved.
-- Pin search_path on every nl / nl_content function that did not set one
-- (Supabase linter 0011 function_search_path_mutable). Without it a function resolves
-- unqualified names through the caller's search_path, so a caller who can create
-- objects earlier on that path could shadow a table or function the body uses.
-- pg_catalog is still searched first implicitly, so built-ins (gen_random_uuid,
-- jsonb_*, get_byte) resolve as before. Apply after 009_content_editor.sql.
-- A later CREATE OR REPLACE of any of these must repeat the SET clause.

alter function nl.accumulate()                              set search_path = nl, pg_temp;
alter function nl.assert_release_safe(bigint)               set search_path = nl, pg_temp;
alter function nl.bucket(bigint)                            set search_path = nl, pg_temp;
alter function nl.build_stage()                             set search_path = nl, pg_temp;
alter function nl.cell_noise(bigint)                        set search_path = nl, pg_temp;
alter function nl.check_hint(jsonb)                         set search_path = nl, pg_temp;
alter function nl.dim_label(text, text)                     set search_path = nl, pg_temp;
alter function nl.guard_raw_delete()                        set search_path = nl, pg_temp;
alter function nl.health()                                  set search_path = nl, pg_temp;
alter function nl.ingest_t1(jsonb)                          set search_path = nl, pg_temp;
alter function nl.ingest_t2(jsonb)                          set search_path = nl, pg_temp;
alter function nl.limit_ingest_gateway()                    set search_path = nl, pg_temp;
alter function nl.new_record_key()                          set search_path = nl, pg_temp;
alter function nl.normalize_batch(jsonb)                    set search_path = nl, pg_temp;
alter function nl.payload_event_count(jsonb)                set search_path = nl, pg_temp;
alter function nl.publish_snapshot(text)                    set search_path = nl, pg_temp;
alter function nl.purge_raw()                               set search_path = nl, pg_temp;
alter function nl.reject_identity(jsonb)                    set search_path = nl, pg_temp;
alter function nl.release_json(bigint)                      set search_path = nl, pg_temp;
alter function nl.stats_json()                              set search_path = nl, pg_temp;
alter function nl_content._parse_date(text, text)           set search_path = nl_content, pg_temp;
alter function nl_content._validate_links(jsonb)            set search_path = nl_content, pg_temp;
alter function nl_content.guard_staff_change_immutable()    set search_path = nl_content, pg_temp;
alter function nl_content.on_fact_insert()                  set search_path = nl_content, pg_temp;
