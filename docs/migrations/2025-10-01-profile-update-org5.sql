-- Update customer profile for Org 5 via RPC
-- Allows authenticated user to update their own customer row (member_id = auth.uid()) in org 5.

CREATE OR REPLACE FUNCTION public.update_customer_profile_org5(
  p_full_name          text DEFAULT NULL,
  p_preference         text DEFAULT NULL,
  p_interests          text[] DEFAULT NULL,
  p_gallery_images     text[] DEFAULT NULL,
  p_profile_image_url  text DEFAULT NULL,
  p_date_of_birth      date DEFAULT NULL,
  p_gender             text DEFAULT NULL,
  p_visibility         boolean DEFAULT NULL,
  p_search_radius_km   numeric DEFAULT NULL,
  p_location_id        bigint DEFAULT NULL,
  p_notes              text DEFAULT NULL
) RETURNS public.customers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_member_id uuid := auth.uid();
  v_org_id    bigint := 5;
  v_row       public.customers%ROWTYPE;
BEGIN
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Must be authenticated';
  END IF;

  UPDATE public.customers c
     SET full_name         = COALESCE(p_full_name, c.full_name),
         preference        = COALESCE(p_preference, c.preference),
         interests         = COALESCE(p_interests, c.interests),
         gallery_images    = COALESCE(p_gallery_images, c.gallery_images),
         profile_image_url = COALESCE(p_profile_image_url, c.profile_image_url),
         date_of_birth     = COALESCE(p_date_of_birth, c.date_of_birth),
         gender            = COALESCE(p_gender, c.gender),
         visibility        = COALESCE(p_visibility, c.visibility),
         search_radius_km  = COALESCE(p_search_radius_km, c.search_radius_km),
         location_id       = COALESCE(p_location_id, c.location_id),
         notes             = COALESCE(p_notes, c.notes),
         updated_at        = now()
   WHERE c.member_id = v_member_id
     AND c.organization_id = v_org_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer row not found for current user in org 5';
  END IF;

  RETURN v_row;
END;
$$;

ALTER FUNCTION public.update_customer_profile_org5(
  text, text, text[], text[], text, date, text, boolean, numeric, bigint, text
) OWNER TO postgres;

GRANT EXECUTE ON FUNCTION public.update_customer_profile_org5(
  text, text, text[], text[], text, date, text, boolean, numeric, bigint, text
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_customer_profile_org5(
  text, text, text[], text[], text, date, text, boolean, numeric, bigint, text
) TO service_role;

