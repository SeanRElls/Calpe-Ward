-- CREATE OVERLOAD: get_notices_for_user() with NO parameters (uses auth.uid())
-- This allows the function to be called without explicitly passing p_token

DROP FUNCTION IF EXISTS public.get_notices_for_user() CASCADE;

CREATE FUNCTION public.get_notices_for_user()
RETURNS TABLE(
  id uuid,
  title text,
  body_en text,
  body_es text,
  version integer,
  is_active boolean,
  updated_at timestamp with time zone,
  created_by uuid,
  created_by_name text,
  target_all boolean,
  target_roles integer[],
  acknowledged_at timestamp with time zone,
  ack_version integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    n.id,
    n.title,
    n.body_en,
    n.body_es,
    n.version,
    n.is_active,
    n.updated_at,
    n.created_by,
    u.name AS created_by_name,
    n.target_all,
    n.target_roles,
    ack.acknowledged_at,
    ack.version AS ack_version
  FROM public.notices n
  LEFT JOIN public.users u ON n.created_by = u.id
  LEFT JOIN public.notice_ack ack
    ON ack.notice_id = n.id
    AND ack.user_id = auth.uid()
  WHERE
    n.is_active = true
    AND (
      n.target_all = true
      OR n.target_roles && ARRAY[(SELECT role_id::integer FROM public.users WHERE id = auth.uid())]
      OR n.created_by = auth.uid()
    )
  ORDER BY n.updated_at DESC;
$$;

ALTER FUNCTION public.get_notices_for_user() OWNER TO postgres;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION public.get_notices_for_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notices_for_user() TO anon;
