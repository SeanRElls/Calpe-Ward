-- RPC functions for weekly comments (week_comments table)

DROP FUNCTION IF EXISTS public.get_week_comments(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.upsert_week_comment(uuid, uuid, uuid, text) CASCADE;

-- 1. Get comments for a specific week
CREATE OR REPLACE FUNCTION public.get_week_comments(
  p_week_id uuid,
  p_token uuid
)
RETURNS TABLE (
  id uuid,
  week_id uuid,
  user_id uuid,
  comment text,
  updated_at timestamp with time zone,
  created_at timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT wc.id, wc.week_id, wc.user_id, wc.comment, wc.updated_at, wc.created_at
  FROM week_comments wc
  WHERE wc.week_id = p_week_id
    AND EXISTS (
      SELECT 1 FROM sessions
      WHERE token = p_token
        AND expires_at > now()
        AND revoked_at IS NULL
    )
  ORDER BY wc.created_at DESC;
$$;

-- 2. Upsert (create or update) a week comment
CREATE OR REPLACE FUNCTION public.upsert_week_comment(
  p_week_id uuid,
  p_user_id uuid,
  p_token uuid,
  p_comment text DEFAULT ''
)
RETURNS SETOF public.week_comments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Validate token
  SELECT user_id INTO v_user_id
  FROM sessions
  WHERE token = p_token AND expires_at > now() AND revoked_at IS NULL;
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired token';
  END IF;

  -- Only allow users to edit their own comments
  IF p_user_id != v_user_id THEN
    RAISE EXCEPTION 'Can only edit your own comments';
  END IF;

  -- Delete existing comment if empty, otherwise upsert
  IF p_comment = '' OR p_comment IS NULL THEN
    DELETE FROM public.week_comments
    WHERE week_id = p_week_id AND user_id = p_user_id;
  ELSE
    INSERT INTO public.week_comments (week_id, user_id, comment, updated_at)
    VALUES (p_week_id, p_user_id, p_comment, now())
    ON CONFLICT ON CONSTRAINT week_comments_week_id_user_id_key DO UPDATE
    SET comment = p_comment,
        updated_at = now();
  END IF;

  -- Return all comments for this week
  RETURN QUERY
  SELECT *
  FROM public.week_comments
  WHERE week_id = p_week_id
  ORDER BY created_at DESC;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_week_comments(uuid, uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.upsert_week_comment(uuid, uuid, uuid, text) TO anon, authenticated, service_role;
