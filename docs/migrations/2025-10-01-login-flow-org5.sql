-- FE Login Flow helpers (Org 5)
-- Purpose: Allow FE to upsert and fetch customers without requiring JWT active_organization_id,
--          by defaulting organization_id to 5.

-- 1) Upsert customer by phone for Org 5
--    - If phone exists (in org 5 or legacy NULL org), update row and set member_id = auth.uid(), org=5
--    - Else insert new row under org 5
CREATE OR REPLACE FUNCTION public.auth_sync_customer_login_org5(
  p_phone        text,
  p_full_name    text DEFAULT NULL,
  p_location_id  bigint DEFAULT NULL
) RETURNS public.customers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_customer   public.customers%ROWTYPE;
  v_member_id  uuid := auth.uid();
  v_org_id     bigint := 5;  -- fixed per request
BEGIN
  IF p_phone IS NULL OR btrim(p_phone) = '' THEN
    RAISE EXCEPTION 'Phone number is required';
  END IF;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Must be authenticated';
  END IF;

  -- Find by phone within org 5 (or legacy rows without org)
  SELECT *
    INTO v_customer
  FROM public.customers
  WHERE phone_number = p_phone
    AND (organization_id IS NULL OR organization_id = v_org_id)
  FOR UPDATE;

  IF FOUND THEN
    -- Update existing row; ensure it is linked to current member and org 5
    UPDATE public.customers
       SET member_id        = v_member_id,
           full_name        = COALESCE(p_full_name, full_name),
           location_id      = COALESCE(p_location_id, location_id),
           organization_id  = COALESCE(organization_id, v_org_id),
           last_visit_at    = COALESCE(last_visit_at, now()),
           updated_at       = now()
     WHERE id = v_customer.id
     RETURNING * INTO v_customer;
  ELSE
    -- Insert new row under org 5
    INSERT INTO public.customers (
      full_name,
      phone_number,
      organization_id,
      member_id,
      location_id,
      created_at,
      updated_at
    )
    VALUES (
      COALESCE(p_full_name, p_phone, 'Member'),
      p_phone,
      v_org_id,
      v_member_id,
      p_location_id,
      now(),
      now()
    )
    RETURNING * INTO v_customer;
  END IF;

  RETURN v_customer;
END;
$$;

ALTER FUNCTION public.auth_sync_customer_login_org5(text, text, bigint) OWNER TO postgres;

-- Helpful index for phone lookups within org
CREATE INDEX IF NOT EXISTS idx_customers_phone_org
  ON public.customers (phone_number, organization_id);

GRANT EXECUTE ON FUNCTION public.auth_sync_customer_login_org5(text, text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_sync_customer_login_org5(text, text, bigint) TO service_role;

-- 2) Get customer by member_id for Org 5 (no need for active_organization_id in JWT)
CREATE OR REPLACE FUNCTION public.get_customer_detail_by_member_id_org5(
  p_member_id uuid
) RETURNS public.customers
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT c.*
  FROM public.customers c
  WHERE c.member_id = p_member_id
    AND c.organization_id = 5
  LIMIT 1;
$$;

ALTER FUNCTION public.get_customer_detail_by_member_id_org5(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_customer_detail_by_member_id_org5(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_customer_detail_by_member_id_org5(uuid) TO service_role;

