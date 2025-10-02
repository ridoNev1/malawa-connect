-- Add connection_status/connection_type to member detail RPC (Org 5)

CREATE OR REPLACE FUNCTION public.get_member_detail_org5(
  p_id text
) RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
      AND (c.id::text = p_id OR c.member_id::text = p_id)
  ), pres AS (
    SELECT up.user_id,
           up.location_id,
           up.last_heartbeat_at,
           up.check_in_at
    FROM public.user_presence up
    WHERE up.check_out_at IS NULL
  ), loc AS (
    SELECT l.id, l.name FROM public.locations l WHERE l.organization_id = 5
  ), conns_raw AS (
    SELECT CASE WHEN c.requester_id = auth.uid() THEN c.addressee_id ELSE c.requester_id END AS peer_id,
           c.connection_type,
           c.status,
           COALESCE(c.updated_at, c.created_at) AS ts
    FROM public.connections c
    WHERE c.organization_id = 5
      AND (c.requester_id = auth.uid() OR c.addressee_id = auth.uid())
  ), conns AS (
    SELECT DISTINCT ON (peer_id)
           peer_id,
           connection_type,
           status,
           ts
    FROM conns_raw
    ORDER BY peer_id, ts DESC
  )
  SELECT to_jsonb(j) FROM (
    SELECT b.*,
      l.name AS location_name,
      (p.user_id IS NOT NULL AND p.last_heartbeat_at >= now() - interval '120 seconds') AS "isOnline",
      CASE
        WHEN p.user_id IS NOT NULL
          THEN to_char(COALESCE(p.last_heartbeat_at, p.check_in_at), 'YYYY-MM-DD"T"HH24:MI:SSZ')
        WHEN b.last_visit_at IS NOT NULL
          THEN to_char(b.last_visit_at, 'YYYY-MM-DD"T"HH24:MI:SSZ')
        ELSE NULL
      END AS "lastSeen",
      cc.status AS connection_status,
      cc.connection_type AS connection_type
    FROM base b
    LEFT JOIN pres p ON p.user_id = b.member_id
    LEFT JOIN loc  l ON l.id = COALESCE(p.location_id, b.location_id)
    LEFT JOIN conns cc ON cc.peer_id = b.member_id
  ) j;
$$;

ALTER FUNCTION public.get_member_detail_org5(text) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_member_detail_org5(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_detail_org5(text) TO service_role;

NOTIFY pgrst, 'reload schema';

