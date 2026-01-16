| Function (schema.name(args)) | SECURITY DEFINER | What it does (1 line) | Validates session token | Validates PIN | Enforces permission groups | Callable by roles | Risk |
|---|---|---|---|---|---|---|---|
| auth.email() | N | Supabase auth helper for email claim | N | N | N | anon, authenticated, service_role, system roles | Low |
| auth.jwt() | N | Supabase auth helper for JWT | N | N | N | anon, authenticated, service_role, system roles | Low |
| auth.role() | N | Supabase auth helper for role | N | N | N | anon, authenticated, service_role, system roles | Low |
| auth.uid() | N | Supabase auth helper for user id | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.armor(bytea) | N | pgcrypto armor encode | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.armor(bytea, text[], text[]) | N | pgcrypto armor encode with headers | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.crypt(text, text) | N | pgcrypto crypt hash | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.dearmor(text) | N | pgcrypto dearmor | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.decrypt(bytea, bytea, text) | N | pgcrypto decrypt | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.decrypt_iv(bytea, bytea, bytea, text) | N | pgcrypto decrypt with IV | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.digest(bytea, text) | N | pgcrypto digest | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.digest(text, text) | N | pgcrypto digest | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.encrypt(bytea, bytea, text) | N | pgcrypto encrypt | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.encrypt_iv(bytea, bytea, bytea, text) | N | pgcrypto encrypt with IV | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.gen_random_bytes(integer) | N | pgcrypto random bytes | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.gen_random_uuid() | N | random UUID | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.gen_salt(text) | N | pgcrypto salt | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.gen_salt(text, integer) | N | pgcrypto salt with rounds | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.grant_pg_cron_access() | N | Supabase cron access helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.grant_pg_graphql_access() | N | Supabase GraphQL access helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.grant_pg_net_access() | N | Supabase net access helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.hmac(bytea, bytea, text) | N | pgcrypto hmac | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.hmac(text, text, text) | N | pgcrypto hmac | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamptz, OUT minmax_stats_since timestamptz) | N | pg_stat_statements view | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamptz) | N | pg_stat_statements info | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pg_stat_statements_reset(userid oid, dbid oid, queryid bigint, minmax_only boolean) | N | reset stats | N | N | N | postgres, supabase_admin | Low |
| extensions.pgp_armor_headers(text, OUT key text, OUT value text) | N | pgp armor headers | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_key_id(bytea) | N | pgp key id | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_decrypt(bytea, bytea) | N | pgp decrypt | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_decrypt(bytea, bytea, text) | N | pgp decrypt with passphrase | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_decrypt(bytea, bytea, text, text) | N | pgp decrypt with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_decrypt_bytea(bytea, bytea) | N | pgp decrypt bytea | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_decrypt_bytea(bytea, bytea, text) | N | pgp decrypt bytea with passphrase | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text) | N | pgp decrypt bytea with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_encrypt(text, bytea) | N | pgp encrypt | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_encrypt(text, bytea, text) | N | pgp encrypt with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_encrypt_bytea(bytea, bytea) | N | pgp encrypt bytea | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_pub_encrypt_bytea(bytea, bytea, text) | N | pgp encrypt bytea with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_decrypt(bytea, text) | N | pgp sym decrypt | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_decrypt(bytea, text, text) | N | pgp sym decrypt with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_decrypt_bytea(bytea, text) | N | pgp sym decrypt bytea | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_decrypt_bytea(bytea, text, text) | N | pgp sym decrypt bytea with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_encrypt(text, text) | N | pgp sym encrypt | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_encrypt(text, text, text) | N | pgp sym encrypt with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_encrypt_bytea(bytea, text) | N | pgp sym encrypt bytea | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgp_sym_encrypt_bytea(bytea, text, text) | N | pgp sym encrypt bytea with options | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgrst_ddl_watch() | N | PostgREST DDL watch | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.pgrst_drop_watch() | N | PostgREST drop watch | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.set_graphql_placeholder() | N | Supabase GraphQL placeholder | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_generate_v1() | N | uuid-ossp v1 | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_generate_v1mc() | N | uuid-ossp v1mc | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_generate_v3(namespace uuid, name text) | N | uuid-ossp v3 | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_generate_v4() | N | uuid-ossp v4 | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_generate_v5(namespace uuid, name text) | N | uuid-ossp v5 | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_nil() | N | uuid-ossp nil | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_ns_dns() | N | uuid-ossp ns dns | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_ns_oid() | N | uuid-ossp ns oid | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_ns_url() | N | uuid-ossp ns url | N | N | N | anon, authenticated, service_role, system roles | Low |
| extensions.uuid_ns_x500() | N | uuid-ossp ns x500 | N | N | N | anon, authenticated, service_role, system roles | Low |
| graphql._internal_resolve(query text, variables jsonb, operationName text, extensions jsonb) | N | GraphQL resolver | N | N | N | anon, authenticated, service_role, system roles | Low |
| graphql.comment_directive(comment_ text) | N | GraphQL comment directive | N | N | N | anon, authenticated, service_role, system roles | Low |
| graphql.exception(message text) | N | GraphQL exception helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| graphql.get_schema_version() | Y | GraphQL schema version | N | N | N | anon, authenticated, service_role, system roles | Low |
| graphql.increment_schema_version() | Y | GraphQL schema version increment | N | N | N | anon, authenticated, service_role, system roles | Low |
| graphql.resolve(query text, variables jsonb, operationName text, extensions jsonb) | N | GraphQL resolver | N | N | N | anon, authenticated, service_role, system roles | Low |
| graphql_public.graphql(operationName text, query text, variables jsonb, extensions jsonb) | N | Public GraphQL entry | N | N | N | anon, authenticated, service_role, system roles | Low |
| pgbouncer.get_auth(p_usename text) | Y | pgbouncer auth helper | N | N | N | pgbouncer, supabase_admin | Low |
| public._require_admin(p_admin_id uuid, p_pin text) | Y | Admin PIN check helper | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.ack_notice(p_notice_id uuid, p_user_id uuid, p_version integer) | Y | Upsert notice ack | N | N | N | anon, authenticated, service_role, system roles | High |
| public.acknowledge_notice(p_user_id uuid, p_pin text, p_notice_id uuid) | Y | Ack notice with PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_approve_swap_request(p_admin_id uuid, p_pin text, p_swap_request_id uuid) | Y | Approve swap request | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_clear_request_cell(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date) | Y | Admin delete request cell | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_create_five_week_period(p_admin_id uuid, p_pin text, p_name text, p_start_date date, p_end_date date) | Y | Create 5-week period | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_create_next_period(p_admin_user_id uuid) | Y | Create next period | N | N | N | anon, authenticated, service_role, system roles | High |
| public.admin_decline_swap_request(p_admin_id uuid, p_pin text, p_swap_request_id uuid) | Y | Decline swap request | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_delete_notice(p_admin_id uuid, p_pin text, p_notice_id uuid) | Y | Delete notice | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_execute_shift_swap(p_admin_id uuid, p_pin text, p_initiator_user_id uuid, p_initiator_shift_date date, p_counterparty_user_id uuid, p_counterparty_shift_date date, p_period_id integer) | Y | Execute shift swap | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_get_all_notices(p_admin_id uuid, p_pin text) | Y | Fetch all notices (admin) | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_get_notice_acks(p_admin_id uuid, p_pin text, p_notice_id uuid) | Y | Get notice acknowledgements | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_get_swap_executions(p_admin_id uuid, p_pin text, p_period_id integer) | Y | List swap executions | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_get_swap_requests(p_admin_id uuid, p_pin text) | Y | List swap requests | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_lock_request_cell(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date, p_reason_en text, p_reason_es text) | Y | Lock request cell | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_notice_ack_counts(p_admin_id uuid, p_pin text, p_notice_ids uuid[]) | N | Notice ack counts | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_active_period(p_admin_id uuid, p_pin text, p_period_id uuid) | Y | Set active period (PIN) | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_active_period(p_admin_user_id uuid, p_period_id bigint) | Y | Set active period (no PIN) | N | N | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_notice_active(p_admin_id uuid, p_pin text, p_notice_id uuid, p_active boolean) | Y | Toggle notice active | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_period_closes_at(p_admin_id uuid, p_pin text, p_period_id uuid, p_closes_at timestamptz) | Y | Set period close time | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_period_hidden(p_admin_user_id uuid, p_period_id bigint, p_hidden boolean) | Y | Set period hidden | N | N | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_request_cell(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date, p_value text, p_important_rank smallint) | Y | Admin set request cell | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_week_open(p_admin_user_id uuid, p_week_id bigint, p_open boolean) | Y | Set week open | N | N | N | anon, authenticated, service_role, system roles | High |
| public.admin_set_week_open_flags(p_admin_id uuid, p_pin text, p_week_id uuid, p_open boolean, p_open_after_close boolean) | Y | Set week open flags | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_toggle_hidden_period(p_admin_id uuid, p_pin text, p_period_id uuid) | Y | Toggle hidden period | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_unlock_request_cell(p_admin_id uuid, p_pin text, p_target_user_id uuid, p_date date) | Y | Unlock request cell | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_upsert_notice(p_admin_id uuid, p_pin text, p_notice_id uuid, p_title text, p_body_en text, p_body_es text, p_target_all boolean, p_target_roles integer[]) | Y | Create/update notice | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.admin_upsert_user(p_user_id uuid, p_name text, p_role_id integer) | Y | Create/update user | N | N | N | anon, authenticated, service_role, system roles | High |
| public.assert_admin(p_user_id uuid, p_pin text) | Y | Assert admin + PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.change_user_pin(p_user_id uuid, p_old_pin text, p_new_pin text) | Y | Change user PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.clear_request_cell(p_user_id uuid, p_pin text, p_date date) | Y | Clear request cell | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.clear_request_with_pin(p_user_id uuid, p_pin text, p_date date) | Y | Clear request with PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.crypt(p_password text, p_salt text) | N | Wrapper for crypt | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.delete_request_with_pin(p_user_id uuid, p_pin text, p_date date) | Y | Delete request with PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.enforce_max_5_requests_per_week() | N | Trigger to cap requests | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.enforce_off_priority_rules() | N | Trigger to enforce priority | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.gen_salt(p_type text) | N | Wrapper for gen_salt | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.gen_salt(p_type text, p_rounds integer) | N | Wrapper for gen_salt | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.get_all_notices(p_user_id uuid, p_pin text) | Y | Fetch notices for user | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.get_notices_for_user(p_user_id uuid) | Y | Fetch notices for user | N | N | N | anon, authenticated, service_role, system roles | High |
| public.get_notices_for_user(p_user_id uuid, p_pin text) | Y | Fetch notices for user (PIN) | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.get_pending_swap_requests_for_me(p_user_id uuid) | Y | List pending swap requests | N | N | N | anon, authenticated, service_role, system roles | High |
| public.get_unread_notices(p_user_id uuid, p_pin text) | Y | Fetch unread notices | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.get_week_comments(p_week_id uuid, p_user_id uuid, p_pin text) | Y | Fetch week comments | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.is_admin() | Y | Returns admin status via auth.uid | N | N | N | anon, authenticated, service_role, system roles | High |
| public.is_admin_user(p_user_id uuid) | N | Returns admin status by id | N | N | N | anon, authenticated, service_role, system roles | High |
| public.log_rota_assignment_audit(p_period_id uuid, p_user_id uuid, p_date date, p_old_shift_id bigint, p_new_shift_id bigint, p_action_type text, p_changed_by uuid, p_comment text) | N | Log rota audit | N | N | N | anon, authenticated, service_role, system roles | Med |
| public.notifications_set_updated_at() | N | Trigger to set updated_at | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.save_request_with_pin(p_user_id uuid, p_pin text, p_date date, p_value text, p_important_rank integer) | Y | Save request with PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.set_comment_created_audit() | N | Trigger to set comment audit | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.set_comment_updated_audit() | N | Trigger to set comment audit | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.set_override_created_audit() | N | Trigger to set override audit | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.set_override_updated_audit() | N | Trigger to set override audit | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.set_request_cell(p_user_id uuid, p_pin text, p_date date, p_value text, p_important_rank smallint) | Y | Set request cell | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.set_user_active(p_admin_id uuid, p_pin text, p_user_id uuid, p_active boolean) | Y | Set user active (PIN) | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.set_user_active(p_user_id uuid, p_active boolean) | Y | Set user active (auth.uid) | N | N | N | anon, authenticated, service_role, system roles | High |
| public.set_user_admin(p_user_id uuid, p_admin boolean) | Y | Set user admin | N | N | N | anon, authenticated, service_role, system roles | High |
| public.set_user_language(p_user_id uuid, p_pin text, p_lang text) | Y | Set user language | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.set_user_pin(p_user_id uuid, p_pin text) | Y | Set user PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.set_week_comments_updated_at() | N | Trigger to set updated_at | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.staff_request_shift_swap(p_user_id uuid, p_initiator_shift_date date, p_counterparty_user_id uuid, p_counterparty_shift_date date, p_period_id integer) | Y | Staff request swap | N | N | N | anon, authenticated, service_role, system roles | High |
| public.staff_respond_to_swap_request(p_user_id uuid, p_swap_request_id uuid, p_response text) | Y | Staff respond to swap | N | N | N | anon, authenticated, service_role, system roles | High |
| public.touch_notice_updated_at() | N | Trigger to set notice updated_at | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.touch_updated_at() | N | Trigger to set updated_at | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.update_staffing_requirements_updated_at() | N | Trigger to set updated_at | N | N | N | anon, authenticated, service_role, system roles | Low |
| public.upsert_request_with_pin(p_user_id uuid, p_pin text, p_date date, p_value text, p_important_rank integer) | Y | Upsert request with PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.upsert_week_comment(p_week_id uuid, p_user_id uuid, p_pin text, p_comment text) | Y | Upsert week comment | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.verify_admin_pin(p_admin_id uuid, p_pin text) | Y | Verify admin PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.verify_pin_login(p_user_id uuid, p_pin text) | Y | Verify PIN and issue session token | N | Y | N | anon, authenticated, service_role, system roles | High |
| public.verify_user_pin(p_user_id uuid, p_pin text) | Y | Verify user PIN | N | Y | N | anon, authenticated, service_role, system roles | High |
| realtime.apply_rls(wal jsonb, max_record_bytes integer) | N | Realtime RLS helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text) | N | Realtime broadcast | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) | N | Realtime prepared SQL | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.cast(val text, type_ regtype) | N | Realtime cast helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) | N | Realtime filter helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) | N | Realtime filter helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) | N | Realtime change list | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.quote_wal2json(entity regclass) | N | Realtime WAL helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.send(payload jsonb, event text, topic text, private boolean) | N | Realtime send | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.subscription_check_filters() | N | Realtime filter check | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.to_regrole(role_name text) | N | Realtime role helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| realtime.topic() | N | Realtime topic helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.add_prefixes(_bucket_id text, _name text) | Y | Storage prefix helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) | N | Storage insert check | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.delete_leaf_prefixes(bucket_ids text[], names text[]) | Y | Storage delete helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.delete_prefix(_bucket_id text, _name text) | Y | Storage delete prefix | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.delete_prefix_hierarchy_trigger() | N | Storage trigger | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.enforce_bucket_name_length() | N | Storage constraint trigger | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.extension(name text) | N | Storage extension helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.filename(name text) | N | Storage filename helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.foldername(name text) | N | Storage foldername helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.get_level(name text) | N | Storage get level helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.get_prefix(name text) | N | Storage get prefix helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.get_prefixes(name text) | N | Storage get prefixes helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.get_size_by_bucket() | N | Storage size by bucket | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text) | N | Storage list multipart | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.list_objects_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer, start_after text, next_token text) | N | Storage list objects | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.lock_top_prefixes(bucket_ids text[], names text[]) | Y | Storage lock prefixes | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.objects_delete_cleanup() | Y | Storage delete cleanup | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.objects_insert_prefix_trigger() | N | Storage trigger | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.objects_update_cleanup() | Y | Storage update cleanup | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.objects_update_level_trigger() | N | Storage trigger | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.objects_update_prefix_trigger() | N | Storage trigger | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.operation() | N | Storage operation helper | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.prefixes_delete_cleanup() | Y | Storage delete cleanup | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.prefixes_insert_trigger() | N | Storage trigger | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.search(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) | N | Storage search | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.search_legacy_v1(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) | N | Storage search legacy | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.search_v1_optimised(prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text) | N | Storage search v1 | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.search_v2(prefix text, bucket_name text, limits integer, levels integer, start_after text, sort_order text, sort_column text, sort_column_after text) | N | Storage search v2 | N | N | N | anon, authenticated, service_role, system roles | Low |
| storage.update_updated_at_column() | N | Storage updated_at trigger | N | N | N | anon, authenticated, service_role, system roles | Low |
| vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) | N | Vault decrypt | N | N | N | service_role, supabase_admin, postgres | Low |
| vault._crypto_aead_det_encrypt(message bytea, additional bytea, key_id bigint, context bytea, nonce bytea) | N | Vault encrypt | N | N | N | supabase_admin | Low |
| vault._crypto_aead_det_noncegen() | N | Vault nonce generator | N | N | N | supabase_admin | Low |
| vault.create_secret(new_secret text, new_name text, new_description text, new_key_id uuid) | Y | Vault create secret | N | N | N | service_role, supabase_admin, postgres | Low |
| vault.update_secret(secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid) | Y | Vault update secret | N | N | N | service_role, supabase_admin, postgres | Low |
