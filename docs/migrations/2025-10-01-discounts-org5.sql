-- Discounts (Org 5) — RPC and optional columns

-- 1) Extend discounts with optional fields (idempotent)
ALTER TABLE public.discounts
  ADD COLUMN IF NOT EXISTS image text,
  ADD COLUMN IF NOT EXISTS valid_until date;

-- 2) RPC: get discounts for Org 5
CREATE OR REPLACE FUNCTION public.get_discounts_org5(
  p_only_active boolean DEFAULT true,
  p_limit int DEFAULT 20
) RETURNS TABLE (
  id bigint,
  name text,
  description text,
  type text,
  value numeric,
  is_active boolean,
  created_at timestamptz,
  unique_code text,
  organization_id bigint,
  image text,
  valid_until date
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT d.id, d.name, d.description, d.type, d.value, d.is_active,
         d.created_at, d.unique_code, d.organization_id, d.image, d.valid_until
  FROM public.discounts d
  WHERE d.organization_id = 5
    AND (p_only_active IS NULL OR p_only_active = false OR d.is_active = true)
  ORDER BY COALESCE(d.valid_until, d.created_at::date) DESC, d.created_at DESC
  LIMIT COALESCE(p_limit, 20);
$$;

ALTER FUNCTION public.get_discounts_org5(boolean, int) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_discounts_org5(boolean, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_discounts_org5(boolean, int) TO service_role;

