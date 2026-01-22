 schemaname |          tablename           |                  policyname                  |        roles         |  cmd   |                              qual                               |                           with_check                            
------------+------------------------------+----------------------------------------------+----------------------+--------+-----------------------------------------------------------------+-----------------------------------------------------------------
 public     | admin_pins                   | admin_pins_no_direct                         | {public}             | ALL    | false                                                           | false
 public     | app_settings                 | app_settings_no_direct                       | {public}             | ALL    | false                                                           | false
 public     | audit_logs                   | audit_logs_admin_read_all                    | {public}             | SELECT | (EXISTS ( SELECT 1                                             +| 
            |                              |                                              |                      |        |    FROM users                                                  +| 
            |                              |                                              |                      |        |   WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))) | 
 public     | audit_logs                   | audit_logs_user_read_own                     | {public}             | SELECT | ((user_id = auth.uid()) OR (impersonator_user_id = auth.uid())) | 
 public     | bank_holidays                | bank_holidays_no_direct                      | {public}             | ALL    | false                                                           | false
 public     | calendar_tokens              | calendar_tokens_no_direct_write              | {authenticated}      | ALL    | false                                                           | 
 public     | calendar_tokens              | calendar_tokens_user_read                    | {authenticated}      | SELECT | (user_id = auth.uid())                                          | 
 public     | login_audit                  | login_audit_no_direct                        | {public}             | ALL    | false                                                           | false
 public     | login_rate_limiting          | login_rate_limiting_no_direct                | {public}             | ALL    | false                                                           | false
 public     | non_staff_people             | non_staff_people_no_direct                   | {public}             | ALL    | false                                                           | false
 public     | notice_ack                   | ack no direct                                | {public}             | ALL    | false                                                           | false
 public     | notice_targets               | notice_targets_no_direct                     | {public}             | ALL    | false                                                           | false
 public     | notices                      | notices_no_direct                            | {public}             | ALL    | false                                                           | false
 public     | notifications                | notifications_no_direct                      | {public}             | ALL    | false                                                           | false
 public     | operation_rate_limits        | operation_rate_limits_no_direct              | {public}             | ALL    | false                                                           | false
 public     | pattern_definitions          | pattern_definitions_no_direct                | {public}             | ALL    | false                                                           | false
 public     | pattern_templates            | pattern_templates_no_direct                  | {public}             | ALL    | false                                                           | false
 public     | period_non_staff             | period_non_staff_no_direct                   | {public}             | ALL    | false                                                           | false
 public     | permission_group_permissions | permission_group_permissions_no_direct       | {public}             | ALL    | false                                                           | false
 public     | permission_groups            | permission_groups_no_direct                  | {public}             | ALL    | false                                                           | false
 public     | permissions                  | permissions_no_direct                        | {public}             | ALL    | false                                                           | false
 public     | planned_assignments          | planned_assignments_no_direct                | {public}             | ALL    | false                                                           | false
 public     | request_cell_locks           | request_cell_locks_read_admin                | {public}             | SELECT | (EXISTS ( SELECT 1                                             +| 
            |                              |                                              |                      |        |    FROM users                                                  +| 
            |                              |                                              |                      |        |   WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))) | 
 public     | request_cell_locks           | request_cell_locks_read_own                  | {public}             | SELECT | (auth.uid() = user_id)                                          | 
 public     | requests                     | requests_insert_own                          | {public}             | INSERT |                                                                 | (auth.uid() = user_id)
 public     | requests                     | requests_no_delete                           | {anon,authenticated} | DELETE | false                                                           | 
 public     | requests                     | requests_no_insert                           | {anon,authenticated} | INSERT |                                                                 | false
 public     | requests                     | requests_no_update                           | {anon,authenticated} | UPDATE | false                                                           | false
 public     | requests                     | requests_read_admin                          | {public}             | SELECT | (EXISTS ( SELECT 1                                             +| 
            |                              |                                              |                      |        |    FROM users                                                  +| 
            |                              |                                              |                      |        |   WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))) | 
 public     | requests                     | requests_read_own                            | {public}             | SELECT | (auth.uid() = user_id)                                          | 
 public     | requests                     | requests_select_own                          | {public}             | SELECT | (auth.uid() = user_id)                                          | 
 public     | requests                     | requests_update_own                          | {public}             | UPDATE | (auth.uid() = user_id)                                          | (auth.uid() = user_id)
 public     | requests                     | requests_write_own                           | {public}             | ALL    | (auth.uid() = user_id)                                          | (auth.uid() = user_id)
 public     | roles                        | roles_no_direct                              | {public}             | ALL    | false                                                           | false
 public     | rota_assignment_audits       | rota_assignment_audits_no_direct             | {public}             | ALL    | false                                                           | false
 public     | rota_assignment_comments     | rota_assignment_comments_no_direct           | {public}             | ALL    | false                                                           | false
 public     | rota_assignment_history      | rota_assignment_history_no_direct            | {public}             | ALL    | false                                                           | false
 public     | rota_assignment_overrides    | rota_assignment_overrides_no_direct          | {public}             | ALL    | false                                                           | false
 public     | rota_assignments             | rota_assignments_no_direct                   | {public}             | ALL    | false                                                           | false
 public     | rota_dates                   | rota_dates_no_direct                         | {public}             | ALL    | false                                                           | false
 public     | rota_periods                 | rota_periods_no_direct                       | {public}             | ALL    | false                                                           | false
 public     | rota_weeks                   | rota_weeks_no_direct                         | {public}             | ALL    | false                                                           | false
 public     | sessions                     | sessions_no_direct                           | {public}             | ALL    | false                                                           | false
 public     | shift_catalogue              | shift_catalogue_no_direct                    | {public}             | ALL    | false                                                           | false
 public     | shift_eligibility            | shift_eligibility_no_direct                  | {public}             | ALL    | false                                                           | false
 public     | shifts                       | shifts_no_direct                             | {public}             | ALL    | false                                                           | false
 public     | staffing_requirements        | Only admins can modify staffing requirements | {authenticated}      | ALL    | (EXISTS ( SELECT 1                                             +| (EXISTS ( SELECT 1                                             +
            |                              |                                              |                      |        |    FROM users                                                  +|    FROM users                                                  +
            |                              |                                              |                      |        |   WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))) |   WHERE ((users.id = auth.uid()) AND (users.is_admin = true))))
 public     | staffing_requirements        | staffing_requirements_admin_only             | {public}             | SELECT | (EXISTS ( SELECT 1                                             +| 
            |                              |                                              |                      |        |    FROM users                                                  +| 
            |                              |                                              |                      |        |   WHERE ((users.id = auth.uid()) AND (users.is_admin = true)))) | 
 public     | swap_executions              | swap_executions_no_direct                    | {public}             | ALL    | false                                                           | false
 public     | swap_requests                | swap_requests_no_direct                      | {public}             | ALL    | false                                                           | false
 public     | user_patterns                | user_patterns_no_direct                      | {public}             | ALL    | false                                                           | false
 public     | user_permission_groups       | user_permission_groups_no_direct             | {public}             | ALL    | false                                                           | false
 public     | users                        | users_no_delete                              | {public}             | DELETE | false                                                           | 
 public     | users                        | users_no_insert                              | {public}             | INSERT |                                                                 | false
 public     | users                        | users_no_update                              | {public}             | UPDATE | false                                                           | false
 public     | users                        | users_read_admin                             | {public}             | SELECT | (EXISTS ( SELECT 1                                             +| 
            |                              |                                              |                      |        |    FROM users u                                                +| 
            |                              |                                              |                      |        |   WHERE ((u.id = auth.uid()) AND (u.is_admin = true))))         | 
 public     | users                        | users_read_self                              | {public}             | SELECT | (auth.uid() = id)                                               | 
 public     | week_comments                | week_comments_own                            | {public}             | ALL    | (auth.uid() = user_id)                                          | (auth.uid() = user_id)
 public     | week_comments                | week_comments_read_own                       | {public}             | SELECT | (auth.uid() = user_id)                                          | 
(59 rows)

