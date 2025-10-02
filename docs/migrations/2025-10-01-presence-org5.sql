-- Presence & Locations (Org 5) for Check-in/Checkout

-- 1) Extend locations with geofence fields (idempotent)
ALTER TABLE public.locations
  ADD COLUMN IF NOT EXISTS lat double precision,
  ADD COLUMN IF NOT EXISTS lng double precision,
  ADD COLUMN IF NOT EXISTS geofence_radius_m integer NOT NULL DEFAULT 500;

-- 2) Create user_presence table (idempotent-ish)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE c.relname='user_presence' AND n.nspname='public'
  ) THEN
    CREATE TABLE public.user_presence (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL,
      location_id bigint NOT NULL REFERENCES public.locations(id),
      check_in_at timestamptz NOT NULL DEFAULT now(),
      last_heartbeat_at timestamptz,
      check_out_at timestamptz
    );
  END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_presence_user ON public.user_presence(user_id);
CREATE INDEX IF NOT EXISTS idx_user_presence_active ON public.user_presence(user_id) WHERE check_out_at IS NULL;

-- Enable RLS and self policies (for direct selects if needed)
ALTER TABLE public.user_presence ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS presence_select_self ON public.user_presence;
CREATE POLICY presence_select_self ON public.user_presence FOR SELECT TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS presence_insert_self ON public.user_presence;
CREATE POLICY presence_insert_self ON public.user_presence FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS presence_update_self ON public.user_presence;
CREATE POLICY presence_update_self ON public.user_presence FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- 3) RPC: check-in to location (Org 5)
CREATE OR REPLACE FUNCTION public.presence_check_in_org5(p_location_id bigint)
RETURNS public.user_presence
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.user_presence%ROWTYPE;
  v_org int := 5;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;

  -- Validate location belongs to org 5
  PERFORM 1 FROM public.locations l WHERE l.id = p_location_id AND l.organization_id = v_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invalid location for org 5'; END IF;

  -- Close existing active presence
  UPDATE public.user_presence
     SET check_out_at = now()
   WHERE user_id = v_uid AND check_out_at IS NULL;

  -- Insert new presence
  INSERT INTO public.user_presence(user_id, location_id, check_in_at, last_heartbeat_at)
  VALUES (v_uid, p_location_id, now(), now())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

ALTER FUNCTION public.presence_check_in_org5(bigint) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.presence_check_in_org5(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.presence_check_in_org5(bigint) TO service_role;

-- 4) RPC: heartbeat (Org 5)
CREATE OR REPLACE FUNCTION public.presence_heartbeat_org5()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  UPDATE public.user_presence SET last_heartbeat_at = now()
   WHERE user_id = v_uid AND check_out_at IS NULL;
END; $$;

ALTER FUNCTION public.presence_heartbeat_org5() OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.presence_heartbeat_org5() TO authenticated;
GRANT EXECUTE ON FUNCTION public.presence_heartbeat_org5() TO service_role;

-- 5) RPC: check-out (Org 5)
CREATE OR REPLACE FUNCTION public.presence_check_out_org5()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  UPDATE public.user_presence SET check_out_at = now()
   WHERE user_id = v_uid AND check_out_at IS NULL;
END; $$;

ALTER FUNCTION public.presence_check_out_org5() OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.presence_check_out_org5() TO authenticated;
GRANT EXECUTE ON FUNCTION public.presence_check_out_org5() TO service_role;

-- 6) RPC: get current presence summary (Org 5)
CREATE OR REPLACE FUNCTION public.get_current_presence_org5()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT to_jsonb(t) FROM (
    SELECT up.location_id,
           l.name AS location_name,
           up.check_in_at AS check_in_time,
           up.last_heartbeat_at
    FROM public.user_presence up
    JOIN public.locations l ON l.id = up.location_id AND l.organization_id = 5
    WHERE up.user_id = auth.uid()
      AND up.check_out_at IS NULL
    ORDER BY up.check_in_at DESC
    LIMIT 1
  ) t;
$$;

ALTER FUNCTION public.get_current_presence_org5() OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_current_presence_org5() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_current_presence_org5() TO service_role;

-- 7) RPC: list locations (Org 5) with geofence fields
CREATE OR REPLACE FUNCTION public.get_locations_org5()
RETURNS TABLE(
  id bigint,
  name text,
  address text,
  lat double precision,
  lng double precision,
  geofence_radius_m integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT l.id, l.name, l.address, l.lat, l.lng, l.geofence_radius_m
  FROM public.locations l
  WHERE l.organization_id = 5
  ORDER BY l.name;
$$;

ALTER FUNCTION public.get_locations_org5() OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_locations_org5() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_locations_org5() TO service_role;
