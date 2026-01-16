-- DROP OLD FUNCTIONS FIRST (forces complete recreation)
DROP FUNCTION IF EXISTS admin_get_swap_requests(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS admin_get_swap_executions(uuid, text, integer) CASCADE;

-- NOW CREATE THE FIXED VERSIONS (using INTO pattern like other functions)

create or replace function admin_get_swap_requests(
  p_admin_id uuid,
  p_pin text
)
returns table(
  id uuid,
  period_id integer,
  initiator_name text,
  counterparty_name text,
  initiator_shift_date date,
  initiator_shift_code text,
  counterparty_shift_date date,
  counterparty_shift_code text,
  status text,
  counterparty_response text,
  counterparty_responded_at timestamp,
  created_at timestamp
) as $$
declare
  v_admin_name text;
begin
  -- Verify admin exists and is active
  select name into v_admin_name from public.users where id = p_admin_id and is_active = true;
  if v_admin_name is null then
    raise exception 'Admin not found or inactive';
  end if;

  return query
  select 
    swap_requests.id, 
    swap_requests.period_id,
    (select u.name from public.users u where u.id = swap_requests.initiator_user_id limit 1),
    (select u.name from public.users u where u.id = swap_requests.counterparty_user_id limit 1),
    swap_requests.initiator_shift_date, 
    swap_requests.initiator_shift_code,
    swap_requests.counterparty_shift_date, 
    swap_requests.counterparty_shift_code,
    swap_requests.status, 
    swap_requests.counterparty_response, 
    swap_requests.counterparty_responded_at,
    swap_requests.created_at
  from swap_requests
  order by swap_requests.created_at desc;
end;
$$ language plpgsql security definer;

create or replace function admin_get_swap_executions(
  p_admin_id uuid,
  p_pin text,
  p_period_id integer default null
)
returns table(
  id uuid,
  period_id integer,
  initiator_name text,
  counterparty_name text,
  authoriser_name text,
  initiator_date date,
  initiator_old_shift text,
  initiator_new_shift text,
  counterparty_date date,
  counterparty_old_shift text,
  counterparty_new_shift text,
  method text,
  executed_at timestamp
) as $$
declare
  v_admin_name text;
begin
  -- Verify admin exists and is active
  select name into v_admin_name from public.users where id = p_admin_id and is_active = true;
  if v_admin_name is null then
    raise exception 'Admin not found or inactive';
  end if;

  return query
  select 
    swap_executions.id,
    swap_executions.period_id,
    swap_executions.initiator_name,
    swap_executions.counterparty_name,
    swap_executions.authoriser_name,
    swap_executions.initiator_old_shift_date,
    swap_executions.initiator_old_shift_code,
    swap_executions.initiator_new_shift_code,
    swap_executions.counterparty_old_shift_date,
    swap_executions.counterparty_old_shift_code,
    swap_executions.counterparty_new_shift_code,
    swap_executions.method,
    swap_executions.executed_at
  from swap_executions
  where (p_period_id is null or p_period_id = 0 or swap_executions.period_id = p_period_id)
  order by swap_executions.executed_at desc;
end;
$$ language plpgsql security definer;

grant execute on function admin_get_swap_requests(uuid, text) to authenticated;
grant execute on function admin_get_swap_executions(uuid, text, integer) to authenticated;
