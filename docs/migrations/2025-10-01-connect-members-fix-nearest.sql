-- Patch: Nearest filter should use presence.location_id OR customers.location_id
-- This ensures members currently online in a location are included in the
-- 'nearest' tab even if their customers.location_id is NULL.

CREATE OR REPLACE FUNCTION public.get_members_org5(
  p_tab text DEFAULT 'nearest',
  p_status text DEFAULT 'Semua',
  p_search text DEFAULT '',
  p_page int DEFAULT 1,
  p_page_size int DEFAULT 10,
  p_base_location_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offset int := GREATEST((COALESCE(p_page,1)-1) * COALESCE(p_page_size,10), 0);
  v_items jsonb;
  v_base_loc bigint := p_base_location_id;
BEGIN
  IF p_tab = 'nearest' AND v_base_loc IS NULL THEN
    SELECT location_id INTO v_base_loc FROM public.customers
    WHERE member_id = v_uid AND organization_id = 5;
  END IF;

  WITH base AS (
    SELECT c.id::text AS id,
           c.member_id,
           c.location_id,
           c.full_name AS name,
           c.profile_image_url AS avatar,
           c.preference,
           c.gallery_images,
           c.date_of_birth,
           c.gender,
           c.interests,
           c.last_visit_at
    FROM public.customers c
    WHERE c.organization_id = 5
      AND c.member_id <> v_uid
      AND (COALESCE(p_search,'') = '' OR c.full_name ILIKE '%'||p_search||'%')
      -- IMPORTANT: do NOT filter nearest here; we will filter after joining presence
  ),
  pres AS (
    SELECT up.user_id,
           up.location_id,
           up.last_heartbeat_at,
           up.check_in_at
    FROM public.user_presence up
    WHERE up.check_out_at IS NULL
  ),
  loc AS (
    SELECT l.id, l.name FROM public.locations l WHERE l.organization_id = 5
  ),
  joined AS (
    SELECT b.*,
           (p.user_id IS NOT NULL AND p.last_heartbeat_at >= now() - interval '120 seconds') AS "isOnline",
           CASE
             WHEN p.user_id IS NOT NULL
               THEN to_char(COALESCE(p.last_heartbeat_at, p.check_in_at), 'YYYY-MM-DD"T"HH24:MI:SSZ')
             WHEN b.last_visit_at IS NOT NULL
               THEN to_char(b.last_visit_at, 'YYYY-MM-DD"T"HH24:MI:SSZ')
             ELSE NULL
           END AS "lastSeen",
           COALESCE(p.location_id, b.location_id) AS effective_location_id,
           l.name AS location_name,
           '-'::text AS distance
    FROM base b
    LEFT JOIN pres p ON p.user_id = b.member_id
    LEFT JOIN loc  l ON l.id = COALESCE(p.location_id, b.location_id)
  ),
  conns AS (
    SELECT CASE WHEN c.requester_id = v_uid THEN c.addressee_id ELSE c.requester_id END AS peer_id,
           c.connection_type,
           c.status
    FROM public.connections c
    WHERE c.organization_id = 5
      AND (c.requester_id = v_uid OR c.addressee_id = v_uid)
  ),
  filtered AS (
    SELECT j.*, cc.status as connection_status, cc.connection_type as connection_type
    FROM joined j
    LEFT JOIN conns cc ON cc.peer_id = j.member_id
    WHERE (
      p_status IS NULL OR p_status = 'Semua'
      OR (p_status = 'Online'   AND j."isOnline" = true)
      OR (p_status = 'Friends'  AND cc.status = 'accepted' AND cc.connection_type = 'friend')
      OR (p_status = 'Partners' AND cc.status = 'accepted' AND cc.connection_type = 'partner')
    )
    AND (
      p_tab <> 'nearest' OR (
        v_base_loc IS NOT NULL AND j.effective_location_id = v_base_loc
      )
    )
  ),
  counted AS (
    SELECT COUNT(*) AS total FROM filtered
  ),
  page AS (
    SELECT * FROM filtered
    ORDER BY "isOnline" DESC, name ASC
    OFFSET v_offset LIMIT COALESCE(p_page_size,10)
  )
  SELECT jsonb_build_object(
    'items', COALESCE(jsonb_agg(to_jsonb(page)), '[]'::jsonb),
    'page', COALESCE(p_page,1),
    'pageSize', COALESCE(p_page_size,10),
    'total', (SELECT total FROM counted),
    'hasMore', ((SELECT total FROM counted) > (v_offset + COALESCE(p_page_size,10)))
  ) INTO v_items
  FROM page;

  RETURN COALESCE(v_items, jsonb_build_object(
    'items','[]'::jsonb,'page',COALESCE(p_page,1),'pageSize',COALESCE(p_page_size,10),'total',0,'hasMore',false
  ));
END;
$$;

ALTER FUNCTION public.get_members_org5(text, text, text, int, int, bigint) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_members_org5(text, text, text, int, int, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_members_org5(text, text, text, int, int, bigint) TO service_role;

-- Refresh PostgREST schema cache (optional)
NOTIFY pgrst, 'reload schema';

