-- ============================================================================
-- Pattern Anchor Validation Query (schema-aligned)
-- ============================================================================
-- Purpose: Find users on anchored patterns with missing anchor_week_start_date
-- Why: Without anchors, anchored patterns (2/2/3, 3/3/4) silently use week 1
--      targets every week instead of cycling through the pattern.
--
-- Run this before deploying generate_schedule_preview_v2 to catch data issues
-- that will cause "patterns ignored" bugs in production.
-- ============================================================================

WITH anchored_pattern_users AS (
    -- Users assigned to patterns that require anchors
    SELECT 
        u.id AS user_id,
        u.name AS staff_name,
        up.pattern_id,
        pd.pattern_type,
        pd.weekly_targets,
        pd.requires_anchor,
        up.anchor_week_start_date,
        up.assigned_at,
        up.updated_at
    FROM public.users u
    JOIN public.user_patterns up 
        ON up.user_id = u.id
    JOIN public.pattern_definitions pd 
        ON pd.id = up.pattern_id
    WHERE pd.requires_anchor = TRUE
      AND u.is_active = TRUE
),
flagged AS (
    SELECT
        user_id,
        staff_name,
        pattern_type,
        weekly_targets,
        anchor_week_start_date,
        assigned_at,
        updated_at,
        CASE 
            WHEN anchor_week_start_date IS NULL 
                THEN '❌ MISSING ANCHOR - will default to weekly_targets[1] every week'
            WHEN EXTRACT(dow FROM anchor_week_start_date) <> 0 
                THEN '⚠️ ANCHOR NOT SUNDAY - anchored cycle phase will be misaligned'
            ELSE '✅ OK'
        END AS validation_status,
        -- Suggested fix: normalize any non-Sunday anchor to its Sunday
        (anchor_week_start_date - EXTRACT(dow FROM anchor_week_start_date)::int) AS suggested_sunday_anchor
    FROM anchored_pattern_users
)
SELECT *
FROM flagged
WHERE anchor_week_start_date IS NULL 
   OR EXTRACT(dow FROM anchor_week_start_date) <> 0
ORDER BY 
    pattern_type,
    staff_name;

-- ============================================================================
-- Additional check: All pattern definitions sanity
-- ============================================================================
-- Uncomment to see all pattern definitions and their anchor requirements

/*
SELECT 
    id AS pattern_id,
    pattern_type,
    weekly_targets,
    array_length(weekly_targets, 1) AS cycle_weeks,
    requires_anchor,
    CASE 
        WHEN array_length(weekly_targets, 1) > 1 AND NOT requires_anchor 
            THEN '⚠️ Multi-week non-anchored - will always use week 1'
        WHEN array_length(weekly_targets, 1) = 1 AND requires_anchor 
            THEN '⚠️ Single-week anchored - anchor unnecessary'
        ELSE '✅ OK'
    END AS definition_status
FROM public.pattern_definitions
ORDER BY pattern_type;
*/

-- ============================================================================
-- Quick count summary (needs its own CTE to work)
-- ============================================================================
WITH anchored_pattern_users AS (
    SELECT
        u.id AS user_id,
        up.anchor_week_start_date
    FROM public.users u
    JOIN public.user_patterns up ON up.user_id = u.id
    JOIN public.pattern_definitions pd ON pd.id = up.pattern_id
    WHERE pd.requires_anchor = TRUE
      AND u.is_active = TRUE
)
SELECT 
    COUNT(*) FILTER (WHERE anchor_week_start_date IS NULL) AS missing_anchors,
    COUNT(*) FILTER (
        WHERE anchor_week_start_date IS NOT NULL 
          AND EXTRACT(dow FROM anchor_week_start_date) <> 0
    ) AS non_sunday_anchors,
    COUNT(*) FILTER (
        WHERE anchor_week_start_date IS NOT NULL 
          AND EXTRACT(dow FROM anchor_week_start_date) = 0
    ) AS valid_anchors,
    COUNT(*) AS total_anchored_pattern_users
FROM anchored_pattern_users;
