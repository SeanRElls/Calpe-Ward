-- CREATE OVERLOAD: ack_notice() with NO p_token parameter (accepts p_user_id instead)
-- This allows the function to be called without explicitly passing p_token

DROP FUNCTION IF EXISTS public.ack_notice(uuid, integer) CASCADE;

CREATE FUNCTION public.ack_notice(p_notice_id uuid, p_version integer, p_user_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Use provided user_id, or fall back to auth.uid()
  INSERT INTO public.notice_ack (notice_id, user_id, acknowledged_at, version)
  VALUES (p_notice_id, COALESCE(p_user_id, auth.uid()), now(), p_version)
  ON CONFLICT (notice_id, user_id)
  DO UPDATE
  SET acknowledged_at = now(), version = p_version;
END;
$$;

ALTER FUNCTION public.ack_notice(uuid, integer, uuid) OWNER TO postgres;

-- Grant execute to authenticated and anon users
GRANT EXECUTE ON FUNCTION public.ack_notice(uuid, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ack_notice(uuid, integer, uuid) TO anon;
