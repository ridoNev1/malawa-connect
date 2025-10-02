-- Connect Page — Members list (Org 5)

-- 1) Connections table (optional for filters Friends/Partners)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='connections'
  ) THEN
    CREATE TABLE public.connections (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      requester_id uuid NOT NULL,
      addressee_id uuid NOT NULL,
      status text NOT NULL CHECK (status IN ('pending','accepted','rejected','blocked')),
      connection_type text NOT NULL DEFAULT 'friend' CHECK (connection_type IN ('friend','partner')),
      organization_id bigint NOT NULL DEFAULT 5,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS idx_connections_users ON public.connections (requester_id, addressee_id);
  END IF;
END $$;

-- Enable RLS and add basic policies
ALTER TABLE public.connections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS connections_select_self ON public.connections;
CREATE POLICY connections_select_self ON public.connections FOR SELECT TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());
DROP POLICY IF EXISTS connections_insert_self ON public.connections;
CREATE POLICY connections_insert_self ON public.connections FOR INSERT TO authenticated
  WITH CHECK (requester_id = auth.uid());
DROP POLICY IF EXISTS connections_update_self ON public.connections;
CREATE POLICY connections_update_self ON public.connections FOR UPDATE TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid())
  WITH CHECK (requester_id = auth.uid() OR addressee_id = auth.uid());

-- 2) Blocked users table (optional for filtering)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='blocked_users'
  ) THEN
    CREATE TABLE public.blocked_users (
      blocker_id uuid NOT NULL,
      blocked_id uuid NOT NULL,
      organization_id bigint NOT NULL DEFAULT 5,
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (blocker_id, blocked_id)
    );
  END IF;
END $$;

-- 3) RPC: get_members_org5 — returns JSON (items + pagination)
CREATE OR REPLACE FUNCTION public.get_members_org5(
  p_tab text DEFAULT 'nearest',            -- 'nearest' | 'network'
  p_status text DEFAULT 'Semua',           -- 'Semua' | 'Online' | 'Friends' | 'Partners'
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
  v_total int;
  v_items jsonb;
  v_base_loc bigint := p_base_location_id;
BEGIN
  -- Determine base location for 'nearest'
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
           c.interests
    FROM public.customers c
    WHERE c.organization_id = 5
      AND c.member_id <> v_uid
      AND (COALESCE(p_search,'') = '' OR c.full_name ILIKE '%'||p_search||'%')
      AND (p_tab <> 'nearest' OR (v_base_loc IS NOT NULL AND c.location_id = v_base_loc))
      AND NOT EXISTS (
        SELECT 1 FROM public.blocked_users b
        WHERE b.organization_id = 5
          AND ((b.blocker_id = v_uid AND b.blocked_id = c.member_id)
            OR (b.blocker_id = c.member_id AND b.blocked_id = v_uid))
      )
  ),
  pres AS (
    -- active presence (online), ensure single row per user
    SELECT DISTINCT ON (up.user_id)
           up.user_id,
           up.last_heartbeat_at,
           up.check_out_at,
           up.check_in_at,
           up.location_id
    FROM public.user_presence up
    WHERE up.check_out_at IS NULL
    ORDER BY up.user_id, up.last_heartbeat_at DESC NULLS LAST, up.check_in_at DESC NULLS LAST
  ),
  last_pres AS (
    -- last known presence per user for fallback location
    SELECT DISTINCT ON (up.user_id)
           up.user_id,
           up.location_id,
           GREATEST(
             COALESCE(up.last_heartbeat_at, timestamp 'epoch'),
             COALESCE(up.check_in_at,        timestamp 'epoch'),
             COALESCE(up.check_out_at,       timestamp 'epoch')
           ) AS last_ts
    FROM public.user_presence up
    ORDER BY up.user_id, last_ts DESC
  ),
  joined AS (
    SELECT b.*,
           (p.user_id IS NOT NULL AND p.last_heartbeat_at >= now() - interval '120 seconds') AS "isOnline",
           to_char(
             GREATEST(
               COALESCE(p.last_heartbeat_at, timestamp 'epoch'),
               COALESCE(p.check_in_at, timestamp 'epoch')
             ), 'YYYY-MM-DD"T"HH24:MI:SSZ'
           ) AS "lastSeen",
           COALESCE(p.location_id, lp.location_id, b.location_id) AS location_id_effective,
           '-'::text AS distance
    FROM base b
    LEFT JOIN pres p   ON p.user_id = b.member_id
    LEFT JOIN last_pres lp ON lp.user_id = b.member_id
  ),
  loc AS (
    SELECT l.id, l.name FROM public.locations l WHERE l.organization_id = 5
  ),
  conns AS (
    SELECT DISTINCT ON (peer_id)
           peer_id,
           c.connection_type,
           c.status
    FROM (
      SELECT CASE WHEN c.requester_id = v_uid THEN c.addressee_id ELSE c.requester_id END AS peer_id,
             c.connection_type,
             c.status,
             COALESCE(c.updated_at, c.created_at) AS ord_ts
      FROM public.connections c
      WHERE c.organization_id = 5
        AND (c.requester_id = v_uid OR c.addressee_id = v_uid)
    ) c
    ORDER BY peer_id, ord_ts DESC
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
  ),
  counted AS (
    SELECT COUNT(*) AS total FROM filtered
  ),
  page AS (
    -- ensure distinct members on page output
    SELECT DISTINCT ON (f.member_id)
           f.*, (SELECT name FROM loc WHERE id = f.location_id_effective) AS location_name
    FROM filtered f
    ORDER BY f.member_id, "isOnline" DESC, name ASC
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

-- 4) RPC: send/accept/decline/unfriend (Org 5)
CREATE OR REPLACE FUNCTION public.send_connection_request_org5(
  p_addressee_id uuid,
  p_connection_type text DEFAULT 'friend'
) RETURNS public.connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.connections%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  IF p_addressee_id IS NULL OR p_addressee_id = v_uid THEN RAISE EXCEPTION 'Invalid addressee'; END IF;
  IF p_connection_type NOT IN ('friend','partner') THEN RAISE EXCEPTION 'Invalid connection_type'; END IF;
  -- Block check
  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
    WHERE b.organization_id = 5 AND ((b.blocker_id=v_uid AND b.blocked_id=p_addressee_id) OR (b.blocker_id=p_addressee_id AND b.blocked_id=v_uid))
  ) THEN RAISE EXCEPTION 'Cannot connect: blocked'; END IF;

  -- Existing connection?
  SELECT * INTO v_row FROM public.connections c
   WHERE c.organization_id=5
     AND ((c.requester_id=v_uid AND c.addressee_id=p_addressee_id) OR (c.requester_id=p_addressee_id AND c.addressee_id=v_uid))
   ORDER BY c.created_at DESC LIMIT 1;

  IF FOUND THEN
    IF v_row.status = 'accepted' THEN
      RETURN v_row; -- already friends/partners
    ELSIF v_row.status = 'pending' THEN
      RETURN v_row; -- request already pending
    ELSE
      -- Re-initiate request
      INSERT INTO public.connections(requester_id, addressee_id, status, connection_type, organization_id)
      VALUES (v_uid, p_addressee_id, 'pending', p_connection_type, 5)
      RETURNING * INTO v_row;
      RETURN v_row;
    END IF;
  END IF;

  INSERT INTO public.connections(requester_id, addressee_id, status, connection_type, organization_id)
  VALUES (v_uid, p_addressee_id, 'pending', p_connection_type, 5)
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

ALTER FUNCTION public.send_connection_request_org5(uuid, text) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.send_connection_request_org5(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_connection_request_org5(uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.accept_connection_request_org5(
  p_requester_id uuid
) RETURNS public.connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.connections%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  UPDATE public.connections
     SET status='accepted', updated_at=now()
   WHERE requester_id=p_requester_id AND addressee_id=v_uid AND organization_id=5 AND status='pending'
   RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  RETURN v_row;
END;
$$;

ALTER FUNCTION public.accept_connection_request_org5(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.accept_connection_request_org5(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_connection_request_org5(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.decline_connection_request_org5(
  p_requester_id uuid
) RETURNS public.connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.connections%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  UPDATE public.connections
     SET status='rejected', updated_at=now()
   WHERE requester_id=p_requester_id AND addressee_id=v_uid AND organization_id=5 AND status='pending'
   RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;
  RETURN v_row;
END;
$$;

ALTER FUNCTION public.decline_connection_request_org5(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.decline_connection_request_org5(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_connection_request_org5(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.unfriend_org5(
  p_peer_id uuid
) RETURNS public.connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.connections%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  UPDATE public.connections
     SET status='rejected', updated_at=now()
   WHERE organization_id=5 AND status='accepted'
     AND ((requester_id=v_uid AND addressee_id=p_peer_id) OR (requester_id=p_peer_id AND addressee_id=v_uid))
   RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'No active connection to unfriend'; END IF;
  RETURN v_row;
END;
$$;

ALTER FUNCTION public.unfriend_org5(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.unfriend_org5(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unfriend_org5(uuid) TO service_role;

-- 5) RPC: get_member_detail_org5 (by legacy id text or member_id uuid string)
CREATE OR REPLACE FUNCTION public.get_member_detail_org5(
  p_id text
) RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH me AS (
    SELECT auth.uid() AS v_uid
  ), base AS (
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
    -- ensure single active presence row per user
    SELECT DISTINCT ON (up.user_id)
           up.user_id,
           up.last_heartbeat_at,
           up.check_in_at,
           up.check_out_at,
           up.location_id
    FROM public.user_presence up
    WHERE up.check_out_at IS NULL
    ORDER BY up.user_id, up.last_heartbeat_at DESC NULLS LAST, up.check_in_at DESC NULLS LAST
  ), last_pres AS (
    SELECT DISTINCT ON (up.user_id)
           up.user_id,
           up.location_id,
           GREATEST(
             COALESCE(up.last_heartbeat_at, timestamp 'epoch'),
             COALESCE(up.check_in_at,        timestamp 'epoch'),
             COALESCE(up.check_out_at,       timestamp 'epoch')
           ) AS last_ts
    FROM public.user_presence up
    ORDER BY up.user_id, last_ts DESC
  ), loc AS (
    SELECT l.id, l.name FROM public.locations l WHERE l.organization_id = 5
  ), conn AS (
    SELECT DISTINCT ON (peer_id)
           peer_id,
           status,
           connection_type
    FROM (
      SELECT CASE WHEN c.requester_id = (SELECT v_uid FROM me) THEN c.addressee_id ELSE c.requester_id END AS peer_id,
             c.status,
             c.connection_type,
             COALESCE(c.updated_at, c.created_at) AS ord_ts
      FROM public.connections c
      WHERE c.organization_id = 5
        AND ((c.requester_id = (SELECT v_uid FROM me)) OR (c.addressee_id = (SELECT v_uid FROM me)))
    ) x
    ORDER BY peer_id, ord_ts DESC
  )
  SELECT to_jsonb(j) FROM (
    SELECT b.*,
      (SELECT name FROM loc WHERE id = COALESCE(p.location_id, lp.location_id, b.location_id)) AS location_name,
      (p.user_id IS NOT NULL AND p.last_heartbeat_at >= now() - interval '120 seconds') AS "isOnline",
      CASE
        WHEN COALESCE(p.last_heartbeat_at, p.check_in_at, lp.last_ts, b.last_visit_at) IS NULL THEN NULL
        ELSE to_char(
          COALESCE(p.last_heartbeat_at, p.check_in_at, lp.last_ts, b.last_visit_at),
          'YYYY-MM-DD"T"HH24:MI:SSZ'
        )
      END AS "lastSeen",
      c.status AS connection_status,
      c.connection_type
    FROM base b
    LEFT JOIN pres p ON p.user_id = b.member_id
    LEFT JOIN last_pres lp ON lp.user_id = b.member_id
    LEFT JOIN conn c ON c.peer_id = b.member_id
  ) j;
$$;

ALTER FUNCTION public.get_member_detail_org5(text) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_member_detail_org5(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_member_detail_org5(text) TO service_role;
