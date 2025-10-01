


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."order_status_enum" AS ENUM (
    'pending',
    'on_cooking',
    'ready_to_serve',
    'served',
    'completed',
    'canceled'
);


ALTER TYPE "public"."order_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."order_type_enum" AS ENUM (
    'dine_in',
    'takeaway',
    'delivery'
);


ALTER TYPE "public"."order_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."session_status_enum" AS ENUM (
    'open',
    'closed'
);


ALTER TYPE "public"."session_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."table_status_enum" AS ENUM (
    'available',
    'occupied',
    'reserved'
);


ALTER TYPE "public"."table_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'system_admin',
    'owner',
    'super_admin_warehouse',
    'branch_manager',
    'kasir',
    'koki'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."adjust_inventory_stock"("p_location_id" bigint, "p_ingredient_id" bigint, "p_adjustment_quantity" numeric, "p_is_addition" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_new_quantity NUMERIC;
BEGIN
  -- Hanya owner & super_admin_warehouse
  IF public.get_current_role() NOT IN ('owner','super_admin_warehouse') THEN
    RAISE EXCEPTION 'Access denied: You do not have permission to adjust inventory.';
  END IF;

  -- Upsert kuantitas
  INSERT INTO public.inventory (location_id, ingredient_id, quantity)
  VALUES (
    p_location_id,
    p_ingredient_id,
    CASE WHEN p_is_addition THEN p_adjustment_quantity ELSE -p_adjustment_quantity END
  )
  ON CONFLICT (location_id, ingredient_id) DO UPDATE
  SET quantity = inventory.quantity + EXCLUDED.quantity;

  -- Anti-negatif
  SELECT quantity INTO v_new_quantity
  FROM public.inventory
  WHERE location_id = p_location_id AND ingredient_id = p_ingredient_id;

  IF v_new_quantity < 0 THEN
    RAISE EXCEPTION 'Resulting stock cannot be negative (%.%)', p_location_id, p_ingredient_id;
  END IF;
END;
$$;


ALTER FUNCTION "public"."adjust_inventory_stock"("p_location_id" bigint, "p_ingredient_id" bigint, "p_adjustment_quantity" numeric, "p_is_addition" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_create_organization"("p_name" "text", "p_owner_id" "uuid") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  new_organization_id BIGINT;
BEGIN
  -- Keamanan: Hanya system_admin yang boleh menjalankan
  IF public.get_user_role() != 'system_admin' THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;

  -- 1. Buat entri baru di tabel organizations
  INSERT INTO public.organizations (name, owner_id)
  VALUES (p_name, p_owner_id)
  RETURNING id INTO new_organization_id;

  -- 2. Daftarkan owner ke tabel penghubung organization_staff
  INSERT INTO public.organization_staff (user_id, organization_id)
  VALUES (p_owner_id, new_organization_id);

  -- 3. Update peran pengguna yang dipilih menjadi 'owner' di tabel profiles
  UPDATE public.profiles
  SET role = 'owner'
  WHERE id = p_owner_id;

  RETURN new_organization_id;
END;
$$;


ALTER FUNCTION "public"."admin_create_organization"("p_name" "text", "p_owner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_stock_transfer_v2"("p_transfer_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_role text := public.get_current_role();
  t record;
  it record;
BEGIN
  IF v_role NOT IN ('owner','super_admin_warehouse') THEN
    RAISE EXCEPTION 'Only owner/SAW can approve';
  END IF;

  SELECT * INTO t FROM public.stock_transfers
   WHERE id=p_transfer_id AND organization_id=public.get_current_organization_id() FOR UPDATE;
  IF NOT FOUND OR t.status <> 'pending' THEN
    RAISE EXCEPTION 'Invalid transfer state';
  END IF;

  FOR it IN SELECT * FROM public.stock_transfer_items WHERE transfer_id=t.id LOOP
    PERFORM 1 FROM public.inventory inv
     WHERE inv.location_id=t.from_location_id AND inv.ingredient_id=it.ingredient_id AND inv.quantity >= it.quantity;
    IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient stock for ingredient %', it.ingredient_id; END IF;

    UPDATE public.inventory
      SET quantity = quantity - it.quantity
      WHERE location_id=t.from_location_id AND ingredient_id=it.ingredient_id;

    INSERT INTO public.inventory(location_id,ingredient_id,quantity)
    VALUES (t.to_location_id, it.ingredient_id, it.quantity)
    ON CONFLICT (location_id,ingredient_id) DO UPDATE
      SET quantity = public.inventory.quantity + EXCLUDED.quantity;
  END LOOP;

  UPDATE public.stock_transfers SET status='completed', completion_date=now()
   WHERE id=t.id;
END $$;


ALTER FUNCTION "public"."approve_stock_transfer_v2"("p_transfer_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_staff_to_location_v2"("p_location_id" bigint, "p_staff_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id bigint;
  v_role text;
  v_ok boolean;
  v_row jsonb;
BEGIN
  PERFORM public.ensure_location_in_current_org(p_location_id);
  PERFORM public.ensure_membership_in_active_org();

  v_org_id := public.get_current_organization_id();
  v_role   := public.get_current_role();

  -- staff yang akan ditugaskan harus member org aktif
  SELECT TRUE INTO v_ok
  FROM public.organization_staff os
  WHERE os.organization_id = v_org_id
    AND os.user_id = p_staff_id
  LIMIT 1;

  IF NOT COALESCE(v_ok, FALSE) THEN
    RAISE EXCEPTION 'Target staff is not a member of the active organization (%).', v_org_id
      USING ERRCODE = '42501';
  END IF;

  -- role check
  IF v_role = 'owner' THEN
    -- ok
  ELSIF v_role = 'branch_manager' THEN
    -- branch manager hanya boleh assign pada lokasi yang dia kelola
    SELECT TRUE INTO v_ok
    FROM public.location_staff ls
    WHERE ls.location_id = p_location_id
      AND ls.staff_id = auth.uid()
    LIMIT 1;

    IF NOT COALESCE(v_ok, FALSE) THEN
      RAISE EXCEPTION 'You are not a manager for this location (%).', p_location_id
        USING ERRCODE = '42501';
    END IF;
  ELSE
    RAISE EXCEPTION 'Role % is not allowed to assign staff to locations.', v_role
      USING ERRCODE = '42501';
  END IF;

  -- Insert idempotent
  INSERT INTO public.location_staff (location_id, staff_id)
  VALUES (p_location_id, p_staff_id)
  ON CONFLICT (location_id, staff_id) DO NOTHING;

  -- Return row yang baru/ada
  SELECT to_jsonb(ls.*) INTO v_row
  FROM public.location_staff ls
  WHERE ls.location_id = p_location_id AND ls.staff_id = p_staff_id;

  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."assign_staff_to_location_v2"("p_location_id" bigint, "p_staff_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_staff_to_locations"("p_staff_id" "uuid", "p_location_ids" bigint[]) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Hanya owner atau super_admin yang bisa menjalankan fungsi ini
  IF (SELECT public.get_user_role()) NOT IN ('owner', 'super_admin') THEN
    RAISE EXCEPTION 'Access denied: You do not have permission to manage staff assignments.';
  END IF;

  -- 1. Hapus semua penugasan lama untuk staf ini
  DELETE FROM public.location_staff WHERE staff_id = p_staff_id;

  -- 2. Jika ada daftar lokasi baru, masukkan penugasan yang baru
  IF array_length(p_location_ids, 1) > 0 THEN
    INSERT INTO public.location_staff (staff_id, location_id)
    SELECT p_staff_id, unnest(p_location_ids);
  END IF;
END;
$$;


ALTER FUNCTION "public"."assign_staff_to_locations"("p_staff_id" "uuid", "p_location_ids" bigint[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_staff_to_locations_v2"("p_staff_id" "uuid", "p_location_ids" bigint[]) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id        bigint;
  v_caller_id     uuid := auth.uid();
  v_caller_role   text;
  v_target_role   public.user_role;
  v_is_member     boolean;
BEGIN
  -- Wajib: caller adalah member org-aktif
  PERFORM public.ensure_membership_in_active_org();
  v_org_id := public.get_current_organization_id();
  v_caller_role := public.get_current_role();

  -- Target staff harus member org-aktif
  SELECT EXISTS (
    SELECT 1 FROM public.organization_staff os
    WHERE os.organization_id = v_org_id AND os.user_id = p_staff_id
  ) INTO v_is_member;
  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Target staff is not a member of the active organization (%).', v_org_id
      USING ERRCODE = '42501';
  END IF;

  -- Ambil role target
  SELECT pr.role INTO v_target_role
  FROM public.profiles pr WHERE pr.id = p_staff_id;

  -- PBAC:
  IF v_caller_role = 'owner' THEN
    -- Owner boleh atur semua role kecuali system_admin (jaga-jaga)
    IF v_target_role = 'system_admin' THEN
      RAISE EXCEPTION 'Owner cannot modify system_admin assignments.' USING ERRCODE = '42501';
    END IF;

  ELSIF v_caller_role = 'branch_manager' THEN
    -- BM hanya boleh atur kasir/koki
    IF v_target_role NOT IN ('kasir','koki') THEN
      RAISE EXCEPTION 'Branch manager can only manage assignments for kasir/koki (not %).', v_target_role
        USING ERRCODE = '42501';
    END IF;
  ELSE
    RAISE EXCEPTION 'Only owner or branch_manager can manage staff assignments (caller=%).', v_caller_role
      USING ERRCODE = '42501';
  END IF;

  -- Normalisasi input
  p_location_ids := COALESCE(p_location_ids, ARRAY[]::bigint[]);

  -- Temp table: lokasi yang diizinkan untuk caller
  CREATE TEMP TABLE _allowed_locs(lid bigint) ON COMMIT DROP;

  IF v_caller_role = 'owner' THEN
    INSERT INTO _allowed_locs
      SELECT id FROM public.locations WHERE organization_id = v_org_id;
  ELSE
    -- BM: hanya lokasi yang dia kelola
    INSERT INTO _allowed_locs
      SELECT ls.location_id
      FROM public.location_staff ls
      JOIN public.locations l ON l.id = ls.location_id
      WHERE ls.staff_id = v_caller_id
        AND l.organization_id = v_org_id;
  END IF;

  -- Temp table: lokasi baru (intersection input × allowed) agar aman
  CREATE TEMP TABLE _new_locs(lid bigint) ON COMMIT DROP;
  INSERT INTO _new_locs
    SELECT DISTINCT x
    FROM unnest(p_location_ids) AS x
    JOIN _allowed_locs a ON a.lid = x;

  -- Bila BM mencoba mengutak-atik lokasi di luar kewenangannya → tolak
  IF v_caller_role = 'branch_manager' THEN
    IF EXISTS (
      SELECT 1
      FROM unnest(p_location_ids) AS x
      LEFT JOIN _allowed_locs a ON a.lid = x
      WHERE a.lid IS NULL
    ) THEN
      RAISE EXCEPTION 'You can only assign locations you manage.' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- REPLACE semantics
  IF v_caller_role = 'owner' THEN
    -- Owner: hapus semua assignment staff di org-aktif, lalu masukkan persis daftar baru
    DELETE FROM public.location_staff ls
    USING public.locations l
    WHERE ls.staff_id = p_staff_id
      AND ls.location_id = l.id
      AND l.organization_id = v_org_id;

    INSERT INTO public.location_staff (staff_id, location_id)
    SELECT p_staff_id, nl.lid
    FROM _new_locs nl
    ON CONFLICT DO NOTHING;

  ELSE
    -- Branch Manager: replace HANYA dalam ruang lingkup lokasi yang ia kelola
    -- Hapus assignment lama di allowed yang tidak ada di new
    DELETE FROM public.location_staff ls
    WHERE ls.staff_id = p_staff_id
      AND ls.location_id IN (SELECT lid FROM _allowed_locs)
      AND ls.location_id NOT IN (SELECT lid FROM _new_locs);

    -- Tambah assignment baru di allowed yang belum ada
    INSERT INTO public.location_staff (staff_id, location_id)
    SELECT p_staff_id, nl.lid
    FROM _new_locs nl
    LEFT JOIN public.location_staff ls
      ON ls.staff_id = p_staff_id AND ls.location_id = nl.lid
    WHERE ls.staff_id IS NULL
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN;
END;
$$;


ALTER FUNCTION "public"."assign_staff_to_locations_v2"("p_staff_id" "uuid", "p_location_ids" bigint[]) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" bigint NOT NULL,
    "full_name" "text" NOT NULL,
    "phone_number" "text",
    "visit_count" integer DEFAULT 1 NOT NULL,
    "last_visit_at" timestamp with time zone DEFAULT "now"(),
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "total_point" integer DEFAULT 0 NOT NULL,
    "organization_id" bigint NOT NULL,
    "member_id" "uuid",
    "location_id" bigint,
    "preference" "text",
    "interests" "text"[],
    "gallery_images" "text"[],
    "profile_image_url" "text",
    "date_of_birth" "date",
    "gender" "text",
    "visibility" boolean DEFAULT true,
    "search_radius_km" numeric DEFAULT 3,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auth_upsert_customer_by_phone"("p_phone" "text", "p_member_id" "uuid" DEFAULT NULL::"uuid", "p_full_name" "text" DEFAULT NULL::"text", "p_location_id" bigint DEFAULT NULL::bigint, "p_preference" "text" DEFAULT NULL::"text", "p_interests" "text"[] DEFAULT NULL::"text"[], "p_gallery_images" "text"[] DEFAULT NULL::"text"[], "p_profile_image_url" "text" DEFAULT NULL::"text", "p_date_of_birth" "date" DEFAULT NULL::"date", "p_gender" "text" DEFAULT NULL::"text", "p_visibility" boolean DEFAULT NULL::boolean, "p_search_radius_km" numeric DEFAULT NULL::numeric, "p_notes" "text" DEFAULT NULL::"text") RETURNS "public"."customers"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_customer public.customers%ROWTYPE;
  v_org_id bigint := public.get_current_organization_id();
BEGIN
  IF p_phone IS NULL OR btrim(p_phone) = '' THEN
    RAISE EXCEPTION 'Phone number is required';
  END IF;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Active organization context is required';
  END IF;

  SELECT *
    INTO v_customer
  FROM public.customers
  WHERE phone_number = p_phone
  FOR UPDATE;

  IF FOUND THEN
    IF v_customer.organization_id <> v_org_id THEN
      RAISE EXCEPTION 'Phone number is already linked to another organization';
    END IF;

    IF v_customer.member_id IS NOT NULL
       AND p_member_id IS NOT NULL
       AND v_customer.member_id <> p_member_id THEN
      RAISE EXCEPTION 'Phone number is already linked to a different member_id';
    END IF;

    UPDATE public.customers
       SET member_id        = COALESCE(p_member_id, v_customer.member_id),
           full_name        = COALESCE(p_full_name, v_customer.full_name),
           location_id      = COALESCE(p_location_id, v_customer.location_id),
           preference       = COALESCE(p_preference, v_customer.preference),
           interests        = COALESCE(p_interests, v_customer.interests),
           gallery_images   = COALESCE(p_gallery_images, v_customer.gallery_images),
           profile_image_url= COALESCE(p_profile_image_url, v_customer.profile_image_url),
           date_of_birth    = COALESCE(p_date_of_birth, v_customer.date_of_birth),
           gender           = COALESCE(p_gender, v_customer.gender),
           visibility       = COALESCE(p_visibility, v_customer.visibility),
           search_radius_km = COALESCE(p_search_radius_km, v_customer.search_radius_km),
           notes            = COALESCE(p_notes, v_customer.notes),
           last_visit_at    = COALESCE(v_customer.last_visit_at, now()),
           updated_at       = now()
     WHERE id = v_customer.id
     RETURNING * INTO v_customer;
  ELSE
    INSERT INTO public.customers (
      full_name,
      phone_number,
      organization_id,
      member_id,
      location_id,
      preference,
      interests,
      gallery_images,
      profile_image_url,
      date_of_birth,
      gender,
      visibility,
      search_radius_km,
      notes
    )
    VALUES (
      COALESCE(p_full_name, p_phone, 'Member'),
      p_phone,
      v_org_id,
      p_member_id,
      p_location_id,
      p_preference,
      p_interests,
      p_gallery_images,
      p_profile_image_url,
      p_date_of_birth,
      p_gender,
      COALESCE(p_visibility, true),
      COALESCE(p_search_radius_km, 3),
      p_notes
    )
    RETURNING * INTO v_customer;
  END IF;

  RETURN v_customer;
END;
$$;


ALTER FUNCTION "public"."auth_upsert_customer_by_phone"("p_phone" "text", "p_member_id" "uuid", "p_full_name" "text", "p_location_id" bigint, "p_preference" "text", "p_interests" "text"[], "p_gallery_images" "text"[], "p_profile_image_url" "text", "p_date_of_birth" "date", "p_gender" "text", "p_visibility" boolean, "p_search_radius_km" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_hpp"("p_product_id" bigint) RETURNS numeric
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_total_hpp NUMERIC;
BEGIN
  SELECT
    COALESCE(SUM(pr.quantity_needed * i.cost), 0)
  INTO v_total_hpp
  FROM
    public.product_recipes pr
  JOIN
    public.ingredients i ON pr.ingredient_id = i.id
  WHERE
    pr.product_id = p_product_id;
    
  RETURN v_total_hpp;
END;
$$;


ALTER FUNCTION "public"."calculate_hpp"("p_product_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_single_product_stock"("p_product_id" bigint, "p_location_id" bigint) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  makeable_stock INT;
BEGIN
  -- Hitung stok berdasarkan bahan baku yang paling terbatas (bottleneck)
  SELECT
    MIN(FLOOR(COALESCE(inv.quantity, 0) / pr.quantity_needed))
  INTO makeable_stock
  FROM
    public.product_recipes AS pr
  LEFT JOIN
    public.inventory AS inv ON pr.ingredient_id = inv.ingredient_id AND inv.location_id = p_location_id
  WHERE
    pr.product_id = p_product_id;

  -- Jika produk tidak punya resep, kembalikan 0. Jika punya resep tapi tidak ada bahan, hasilnya juga akan 0.
  RETURN COALESCE(makeable_stock, 0);
END;
$$;


ALTER FUNCTION "public"."calculate_single_product_stock"("p_product_id" bigint, "p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_stock_transfer_v2"("p_transfer_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_role text := public.get_current_role();
  t record;
  it record;
BEGIN
  IF v_role NOT IN ('owner','super_admin_warehouse') THEN
    RAISE EXCEPTION 'Only owner/SAW can cancel';
  END IF;

  SELECT * INTO t FROM public.stock_transfers
   WHERE id=p_transfer_id AND organization_id=public.get_current_organization_id() FOR UPDATE;
  IF NOT FOUND OR t.status NOT IN ('pending','completed') THEN
    RAISE EXCEPTION 'Invalid transfer state';
  END IF;

  IF t.status='completed' THEN
    FOR it IN SELECT * FROM public.stock_transfer_items WHERE transfer_id=t.id LOOP
      PERFORM 1 FROM public.inventory inv
       WHERE inv.location_id=t.to_location_id AND inv.ingredient_id=it.ingredient_id AND inv.quantity >= it.quantity;
      IF NOT FOUND THEN RAISE EXCEPTION 'Cannot rollback: destination lacks stock for ingredient %', it.ingredient_id; END IF;

      UPDATE public.inventory
        SET quantity = quantity - it.quantity
        WHERE location_id=t.to_location_id AND ingredient_id=it.ingredient_id;

      UPDATE public.inventory
        SET quantity = quantity + it.quantity
        WHERE location_id=t.from_location_id AND ingredient_id=it.ingredient_id;
    END LOOP;
  END IF;

  UPDATE public.stock_transfers SET status='canceled', completion_date=NULL
   WHERE id=t.id;
END $$;


ALTER FUNCTION "public"."cancel_stock_transfer_v2"("p_transfer_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clone_products_with_options_recipes_v1"("p_src_location_id" bigint, "p_target_location_ids" bigint[], "p_reset_stock_to_zero" boolean DEFAULT true) RETURNS TABLE("target_location_id" bigint, "source_product_id" bigint, "new_product_id" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id           bigint := public.get_current_organization_id();
  v_role             text   := public.get_user_role();
  v_src_count        int;
  v_loc_id           bigint;
  v_src_product_id   bigint;
  v_new_product_id   bigint;
BEGIN
  -- Guard peran
  IF v_role NOT IN ('owner','branch_manager') THEN
    RAISE EXCEPTION 'Access denied: role % cannot clone products', v_role
      USING ERRCODE = '42501';
  END IF;

  -- Validasi lokasi sumber & target berada di org aktif
  IF NOT EXISTS (
    SELECT 1 FROM public.locations l
    WHERE l.id = p_src_location_id AND l.organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'Source location % is not in active organization %', p_src_location_id, v_org_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.locations l
    WHERE l.id = ANY(p_target_location_ids) AND l.organization_id <> v_org_id
  ) THEN
    RAISE EXCEPTION 'One or more target locations are not in active organization %', v_org_id;
  END IF;

  -- Pastikan ada produk di lokasi sumber
  SELECT COUNT(*) INTO v_src_count
  FROM public.location_products lp
  JOIN public.products p ON p.id = lp.product_id
  WHERE lp.location_id = p_src_location_id
    AND p.organization_id = v_org_id;

  IF v_src_count = 0 THEN
    RAISE EXCEPTION 'No products found in source location %', p_src_location_id;
  END IF;

  -- Loop lokasi target
  FOREACH v_loc_id IN ARRAY p_target_location_ids LOOP
    -- Semua product_id yang tertaut ke lokasi sumber
    FOR v_src_product_id IN
      SELECT p.id
      FROM public.location_products lp
      JOIN public.products p ON p.id = lp.product_id
      WHERE lp.location_id = p_src_location_id
        AND p.organization_id = v_org_id
    LOOP
      -- Duplikasi baris products (buat ID baru)
      INSERT INTO public.products (
        category_id, name, description, price, unit, image_url,
        stock, organization_id
      )
      SELECT
        p.category_id,
        p.name,
        p.description,
        p.price,
        p.unit,
        p.image_url,
        CASE WHEN p_reset_stock_to_zero THEN 0 ELSE COALESCE(p.stock,0) END,
        v_org_id
      FROM public.products p
      WHERE p.id = v_src_product_id
      RETURNING id INTO v_new_product_id;

      -- Tautkan produk baru ke lokasi target (idempoten)
      INSERT INTO public.location_products (location_id, product_id)
      VALUES (v_loc_id, v_new_product_id)
      ON CONFLICT DO NOTHING;

      -- Salin product_options (idempoten jika ada unique constraint)
      INSERT INTO public.product_options (product_id, option_group_id)
      SELECT v_new_product_id, po.option_group_id
      FROM public.product_options po
      WHERE po.product_id = v_src_product_id
      ON CONFLICT DO NOTHING;

      -- Salin product_recipes (idempoten jika ada unique constraint)
      INSERT INTO public.product_recipes (product_id, ingredient_id, quantity_needed)
      SELECT v_new_product_id, pr.ingredient_id, pr.quantity_needed
      FROM public.product_recipes pr
      WHERE pr.product_id = v_src_product_id
      ON CONFLICT DO NOTHING;

      -- Kembalikan mapping per produk
      target_location_id := v_loc_id;
      source_product_id  := v_src_product_id;
      new_product_id     := v_new_product_id;
      RETURN NEXT;
    END LOOP;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."clone_products_with_options_recipes_v1"("p_src_location_id" bigint, "p_target_location_ids" bigint[], "p_reset_stock_to_zero" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_category_v2"("p_name" "text", "p_description" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id bigint;
  v_cat_id bigint;
  v_row jsonb;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  v_org_id := public.get_current_organization_id();

  INSERT INTO public.categories (name, description, organization_id)
  VALUES (p_name, p_description, v_org_id)
  RETURNING id INTO v_cat_id;

  SELECT to_jsonb(c.*) INTO v_row
  FROM public.categories c
  WHERE c.id = v_cat_id;

  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."create_category_v2"("p_name" "text", "p_description" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_new_order"("p_payload" "jsonb") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_customer_id BIGINT;
  v_points_redeemed INT;
  new_order_id BIGINT;
  order_item JSONB;
  v_product_id BIGINT;
  v_quantity INT;
  v_current_stock INT;
  v_product_name TEXT;
  v_rupiah_per_point NUMERIC;
  new_points_earned INT;
  v_location_id BIGINT;
BEGIN
  v_location_id := (p_payload->>'location_id')::BIGINT;

  IF p_payload->>'customer_phone' IS NOT NULL AND p_payload->>'customer_phone' <> '' THEN
    SELECT id INTO v_customer_id FROM public.customers WHERE phone_number = p_payload->>'customer_phone';
    IF v_customer_id IS NOT NULL THEN
      UPDATE public.customers SET visit_count = visit_count + 1, last_visit_at = NOW() WHERE id = v_customer_id;
    ELSE
      INSERT INTO public.customers (full_name, phone_number)
      VALUES (COALESCE(p_payload->>'customer_name', p_payload->>'customer_phone'), p_payload->>'customer_phone')
      RETURNING id INTO v_customer_id;
    END IF;
  ELSIF p_payload->>'customer_name' IS NOT NULL AND p_payload->>'customer_name' <> '' THEN
    INSERT INTO public.customers (full_name, phone_number) VALUES (p_payload->>'customer_name', NULL) RETURNING id INTO v_customer_id;
  ELSE
    v_customer_id := NULL;
  END IF;

  FOR order_item IN SELECT * FROM jsonb_array_elements(p_payload->'order_items')
  LOOP
    v_product_id := (order_item->>'product_id')::BIGINT;
    v_quantity := (order_item->>'quantity')::INT;
    SELECT name, stock INTO v_product_name, v_current_stock FROM public.products WHERE id = v_product_id;
    IF v_current_stock IS NOT NULL AND v_current_stock < v_quantity THEN
      RAISE EXCEPTION 'Stok untuk produk "%" tidak cukup. Tersisa: %, Dibutuhkan: %', v_product_name, v_current_stock, v_quantity;
    END IF;
  END LOOP;

  INSERT INTO public.orders (
    location_id, customer_id, staff_id, table_id, order_type,
    status, notes, total_price, tax_amount, discount_amount, final_amount
  )
  VALUES (
    v_location_id, v_customer_id, (p_payload->>'staff_id')::UUID,
    (p_payload->>'table_id')::BIGINT, (p_payload->>'order_type')::order_type_enum,
    'pending', p_payload->>'notes',
    (p_payload->>'total_price')::NUMERIC, (p_payload->>'tax_amount')::NUMERIC,
    (p_payload->>'discount_amount')::NUMERIC + (p_payload->>'points_redeemed')::NUMERIC,
    (p_payload->>'final_amount')::NUMERIC
  )
  RETURNING id INTO new_order_id;

  FOR order_item IN SELECT * FROM jsonb_array_elements(p_payload->'order_items')
  LOOP
    v_product_id := (order_item->>'product_id')::BIGINT;
    v_quantity := (order_item->>'quantity')::INT;

    INSERT INTO public.order_items (
      order_id, product_id, quantity, price_per_unit, selected_options
    )
    VALUES (
      new_order_id, v_product_id, v_quantity,
      (order_item->>'price_per_unit')::NUMERIC, (order_item->'selected_options')::JSONB
    );

    UPDATE public.products SET stock = stock - v_quantity WHERE id = v_product_id;
  END LOOP;

  v_points_redeemed := (p_payload->>'points_redeemed')::INT;
  IF v_customer_id IS NOT NULL AND v_points_redeemed > 0 THEN
    UPDATE public.customers
    SET total_point = total_point - v_points_redeemed
    WHERE id = v_customer_id;
  END IF;

  IF v_customer_id IS NOT NULL THEN
    SELECT value::NUMERIC INTO v_rupiah_per_point FROM public.settings WHERE key = 'rupiah_per_point';
    
    IF v_rupiah_per_point IS NOT NULL AND v_rupiah_per_point > 0 THEN
      new_points_earned := FLOOR((p_payload->>'final_amount')::NUMERIC / v_rupiah_per_point);
      
      IF new_points_earned > 0 THEN
        UPDATE public.customers SET total_point = total_point + new_points_earned WHERE id = v_customer_id;
      END IF;
    END IF;
  END IF;
  
  -- PANGGIL FUNGSI PENGURANGAN STOK BAHAN BAKU
  PERFORM decrement_ingredients_from_order(new_order_id, v_location_id);

  RETURN new_order_id;
END;
$$;


ALTER FUNCTION "public"."create_new_order"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_new_order_v2"("p_payload" "jsonb") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id            bigint;
  v_location_id       bigint;
  v_table_id          bigint;
  v_order_type        public.order_type_enum;
  v_notes             text;

  v_customer_id       bigint;
  v_customer_phone    text;
  v_customer_name     text;

  v_total             numeric;
  v_tax               numeric;
  v_discount          numeric;
  v_points            int;
  v_final             numeric;

  v_new_order_id      bigint;
  v_staff             uuid;

  r_item              jsonb;
  v_product_id        bigint;
  v_qty               int;
  v_current_stock     int;
  v_product_name      text;

  v_rupiah_per_point  numeric;
  v_ok                boolean;
BEGIN
  -- Guards multi-tenant
  PERFORM public.ensure_membership_in_active_org();
  v_org_id := public.get_current_organization_id();

  v_location_id := (p_payload->>'location_id')::bigint;
  PERFORM public.ensure_location_in_current_org(v_location_id);

  v_table_id   := NULLIF(p_payload->>'table_id','')::bigint;
  IF v_table_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.restaurant_tables t
      WHERE t.id = v_table_id AND t.location_id = v_location_id
    ) THEN
      RAISE EXCEPTION 'Table % does not belong to location %', v_table_id, v_location_id
        USING ERRCODE = '42501';
    END IF;
  END IF;

  v_order_type := COALESCE(NULLIF(p_payload->>'order_type',''),'dine_in')::public.order_type_enum;
  v_notes      := NULLIF(p_payload->>'notes','');

  -- Resolve customer (per-org bila ada kolom, kalau tidak global)
  v_customer_phone := NULLIF(p_payload->>'customer_phone','');
  v_customer_name  := NULLIF(p_payload->>'customer_name','');

  IF NULLIF(p_payload->>'customer_id','') IS NOT NULL THEN
    v_customer_id := (p_payload->>'customer_id')::bigint;
    SELECT TRUE INTO v_ok
    FROM public.customers c
    WHERE c.id = v_customer_id
      AND (c.organization_id IS NULL OR c.organization_id = v_org_id)
    LIMIT 1;
    IF NOT COALESCE(v_ok, FALSE) THEN
      v_customer_id := NULL;
    END IF;
  END IF;

  IF v_customer_id IS NULL THEN
    IF v_customer_phone IS NOT NULL THEN
      SELECT c.id INTO v_customer_id
      FROM public.customers c
      WHERE c.phone_number = v_customer_phone
        AND (c.organization_id IS NULL OR c.organization_id = v_org_id)
      LIMIT 1;

      IF v_customer_id IS NULL THEN
        INSERT INTO public.customers (full_name, phone_number, organization_id, created_at)
        VALUES (COALESCE(v_customer_name, v_customer_phone), v_customer_phone, v_org_id, now())
        RETURNING id INTO v_customer_id;
      ELSE
        UPDATE public.customers
           SET full_name    = COALESCE(v_customer_name, full_name),
               last_visit_at = now(),
               visit_count   = COALESCE(visit_count,0) + 1
         WHERE id = v_customer_id;
      END IF;
    ELSIF v_customer_name IS NOT NULL THEN
      INSERT INTO public.customers (full_name, organization_id, created_at)
      VALUES (v_customer_name, v_org_id, now())
      RETURNING id INTO v_customer_id;
    END IF;
  END IF;

  -- Validasi produk & stok + keterikatan ke lokasi
  FOR r_item IN SELECT * FROM jsonb_array_elements(p_payload->'order_items')
  LOOP
    v_product_id := (r_item->>'product_id')::bigint;
    v_qty        := COALESCE((r_item->>'quantity')::int, 1);

    SELECT p.name, p.stock
      INTO v_product_name, v_current_stock
    FROM public.products p
    WHERE p.id = v_product_id
      AND p.organization_id = v_org_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % not found in your organization', v_product_id
        USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.location_products lp
      WHERE lp.product_id = v_product_id AND lp.location_id = v_location_id
    ) THEN
      RAISE EXCEPTION 'Product % is not assigned to location %', v_product_id, v_location_id
        USING ERRCODE = '42501';
    END IF;

    IF v_current_stock IS NOT NULL AND v_current_stock < v_qty THEN
      RAISE EXCEPTION 'Stok untuk produk "%" tidak cukup. Tersisa: %, Dibutuhkan: %',
        v_product_name, v_current_stock, v_qty;
    END IF;
  END LOOP;

  -- Totals dari payload (sesuai v1)
  v_total   := COALESCE((p_payload->>'total_price')::numeric, 0);
  v_tax     := COALESCE((p_payload->>'tax_amount')::numeric, 0);
  v_discount:= COALESCE((p_payload->>'discount_amount')::numeric, 0);
  v_points  := COALESCE((p_payload->>'points_redeemed')::int, 0);
  v_final   := COALESCE((p_payload->>'final_amount')::numeric, 0);

  v_staff := auth.uid();

  INSERT INTO public.orders (
    location_id, customer_id, staff_id, table_id, order_type,
    status, notes, total_price, tax_amount, discount_amount, final_amount,
    organization_id
  )
  VALUES (
    v_location_id, v_customer_id, v_staff, v_table_id, v_order_type,
    'pending', v_notes, v_total, v_tax, v_discount + v_points, v_final,
    v_org_id
  )
  RETURNING id INTO v_new_order_id;

  -- Items + pengurangan stok global (v1)
  FOR r_item IN SELECT * FROM jsonb_array_elements(p_payload->'order_items')
  LOOP
    v_product_id := (r_item->>'product_id')::bigint;
    v_qty        := COALESCE((r_item->>'quantity')::int, 1);

    INSERT INTO public.order_items (
      order_id, product_id, quantity, price_per_unit, selected_options
    )
    VALUES (
      v_new_order_id, v_product_id, v_qty,
      (r_item->>'price_per_unit')::numeric, r_item->'selected_options'
    );

    UPDATE public.products
       SET stock = CASE WHEN stock IS NULL THEN NULL ELSE stock - v_qty END
     WHERE id = v_product_id
       AND organization_id = v_org_id;
  END LOOP;

  -- Redeem poin
  IF v_customer_id IS NOT NULL AND v_points > 0 THEN
    UPDATE public.customers
       SET total_point = COALESCE(total_point,0) - v_points
     WHERE id = v_customer_id;
  END IF;

  -- Baca rupiah_per_point:
  -- coba per-org (jika kolom organization_id ada), kalau tidak ada → fallback global
  v_rupiah_per_point := NULL;
  BEGIN
    SELECT s.value::numeric
      INTO v_rupiah_per_point
    FROM public.settings s
    WHERE s.key = 'rupiah_per_point'
      AND s.organization_id = v_org_id
    LIMIT 1;
  EXCEPTION WHEN undefined_column THEN
    v_rupiah_per_point := NULL;  -- kolom tidak ada, nanti fallback
  END;

  IF v_rupiah_per_point IS NULL THEN
    SELECT s.value::numeric
      INTO v_rupiah_per_point
    FROM public.settings s
    WHERE s.key = 'rupiah_per_point'
    ORDER BY s.updated_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_customer_id IS NOT NULL
     AND v_rupiah_per_point IS NOT NULL
     AND v_rupiah_per_point > 0 THEN
    UPDATE public.customers
       SET total_point = COALESCE(total_point,0) + FLOOR(v_final / v_rupiah_per_point)
     WHERE id = v_customer_id;
  END IF;

  -- Kurangi bahan baku (jika helper ada)
  BEGIN
    PERFORM public.decrement_ingredients_from_order(v_new_order_id, v_location_id);
  EXCEPTION WHEN undefined_function THEN
    BEGIN
      FOR r_item IN SELECT * FROM jsonb_array_elements(p_payload->'order_items')
      LOOP
        v_product_id := (r_item->>'product_id')::bigint;
        v_qty        := COALESCE((r_item->>'quantity')::int, 1);
        PERFORM public.decrement_inventory_for_product_v2(v_location_id, v_product_id, v_qty);
      END LOOP;
    EXCEPTION WHEN undefined_function THEN
      NULL;
    END;
  END;

  RETURN v_new_order_id;
END;
$$;


ALTER FUNCTION "public"."create_new_order_v2"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization_and_link_owner"("p_organization_name" "text") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  new_organization_id BIGINT;
  v_user_id UUID := auth.uid();
BEGIN
  -- 1. Buat organisasi baru
  INSERT INTO public.organizations (name, owner_id)
  VALUES (p_organization_name, v_user_id)
  RETURNING id INTO new_organization_id;

  -- 2. Jadikan pengguna saat ini sebagai anggota organisasi tersebut
  INSERT INTO public.organization_staff (user_id, organization_id)
  VALUES (v_user_id, new_organization_id);

  RETURN new_organization_id;
END;
$$;


ALTER FUNCTION "public"."create_organization_and_link_owner"("p_organization_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_product_with_location"("p_location_id" bigint, "p_name" "text", "p_description" "text", "p_price" numeric, "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  new_product_id BIGINT;
  new_product JSON;
BEGIN
  -- Langkah 1: Buat produk baru di tabel 'products'
  INSERT INTO public.products (name, description, price, unit, category_id, image_url, stock)
  VALUES (p_name, p_description, p_price, p_unit, p_category_id, p_image_url, p_stock)
  RETURNING id INTO new_product_id;

  -- Langkah 2: Hubungkan produk baru tersebut ke lokasi yang aktif
  INSERT INTO public.location_products (location_id, product_id)
  VALUES (p_location_id, new_product_id);

  -- Langkah 3: Ambil data produk lengkap yang baru dibuat untuk dikembalikan
  SELECT to_json(p.*) INTO new_product FROM public.products p WHERE p.id = new_product_id;

  RETURN new_product;
END;
$$;


ALTER FUNCTION "public"."create_product_with_location"("p_location_id" bigint, "p_name" "text", "p_description" "text", "p_price" numeric, "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_product_with_location_v2"("p_location_id" bigint, "p_name" "text", "p_price" numeric, "p_description" "text" DEFAULT NULL::"text", "p_unit" "text" DEFAULT 'serving'::"text", "p_category_id" bigint DEFAULT NULL::bigint, "p_image_url" "text" DEFAULT NULL::"text", "p_stock" bigint DEFAULT NULL::bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id bigint;
  v_product_id bigint;
  v_row jsonb;
  v_ok boolean;
BEGIN
  -- Validasi lokasi milik org aktif
  PERFORM public.ensure_location_in_current_org(p_location_id);
  v_org_id := public.get_current_organization_id();

  -- Validasi kategori (jika ada) milik org aktif
  IF p_category_id IS NOT NULL THEN
    SELECT TRUE INTO v_ok
    FROM public.categories c
    WHERE c.id = p_category_id
      AND c.organization_id = v_org_id
    LIMIT 1;

    IF NOT COALESCE(v_ok, FALSE) THEN
      RAISE EXCEPTION 'Category % does not belong to your active organization (%).', p_category_id, v_org_id
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Insert product + org id
  INSERT INTO public.products (
    name, description, price, unit, category_id, image_url, stock, organization_id
  ) VALUES (
    p_name, p_description, p_price, p_unit, p_category_id, p_image_url, p_stock, v_org_id
  )
  RETURNING id INTO v_product_id;

  -- Relasi ke lokasi
  INSERT INTO public.location_products (location_id, product_id)
  VALUES (p_location_id, v_product_id);

  -- Return row
  SELECT to_jsonb(p.*) INTO v_row FROM public.products p WHERE p.id = v_product_id;
  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."create_product_with_location_v2"("p_location_id" bigint, "p_name" "text", "p_price" numeric, "p_description" "text", "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_user_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email, 'User'),
    'kasir'::public.user_role
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_user_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_ingredients_from_order"("p_order_id" bigint, "p_location_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  order_item RECORD;
  recipe_item RECORD;
BEGIN
  -- Ulangi untuk setiap item di dalam pesanan
  FOR order_item IN
    SELECT product_id, quantity FROM public.order_items WHERE order_id = p_order_id
  LOOP
    -- Untuk setiap item, ulangi resepnya
    FOR recipe_item IN
      SELECT ingredient_id, quantity_needed FROM public.product_recipes WHERE product_id = order_item.product_id
    LOOP
      -- Kurangi stok di tabel inventory untuk lokasi yang benar
      UPDATE public.inventory
      SET quantity = quantity - (order_item.quantity * recipe_item.quantity_needed)
      WHERE ingredient_id = recipe_item.ingredient_id AND location_id = p_location_id;
    END LOOP;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."decrement_ingredients_from_order"("p_order_id" bigint, "p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_inventory_for_product_v2"("p_location_id" bigint, "p_product_id" bigint, "p_qty" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  r_rec record;
  v_need numeric;
  v_have numeric;
BEGIN
  FOR r_rec IN
    SELECT pr.ingredient_id, pr.quantity_needed
    FROM public.product_recipes pr
    WHERE pr.product_id = p_product_id
  LOOP
    v_need := p_qty * r_rec.quantity_needed;

    SELECT COALESCE(inv.quantity, 0)
      INTO v_have
    FROM public.inventory inv
    WHERE inv.location_id = p_location_id
      AND inv.ingredient_id = r_rec.ingredient_id;

    IF v_have < v_need THEN
      RAISE EXCEPTION 'Insufficient inventory for ingredient %: have %, need % (location %).',
        r_rec.ingredient_id, v_have, v_need, p_location_id
        USING ERRCODE = '22023';
    END IF;

    UPDATE public.inventory
    SET quantity = quantity - v_need
    WHERE location_id = p_location_id
      AND ingredient_id = r_rec.ingredient_id;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."decrement_inventory_for_product_v2"("p_location_id" bigint, "p_product_id" bigint, "p_qty" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_organization"("p_org_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF public.get_user_role() != 'system_admin' THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;

  DELETE FROM public.organizations WHERE id = p_org_id;
END;
$$;


ALTER FUNCTION "public"."delete_organization"("p_org_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_location_in_current_org"("p_location_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id bigint;
  v_ok boolean;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  v_org_id := public.get_current_organization_id();

  SELECT TRUE INTO v_ok
  FROM public.locations l
  WHERE l.id = p_location_id
    AND l.organization_id = v_org_id
  LIMIT 1;

  IF NOT COALESCE(v_ok, FALSE) THEN
    RAISE EXCEPTION 'Location % does not belong to your active organization (%).', p_location_id, v_org_id
      USING ERRCODE = '42501';
  END IF;
END;
$$;


ALTER FUNCTION "public"."ensure_location_in_current_org"("p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_membership_in_active_org"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id bigint;
  v_exists boolean;
BEGIN
  v_org_id := public.get_current_organization_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Active organization is not set in your token (active_organization_id is NULL).'
      USING ERRCODE = '42501';
  END IF;

  SELECT TRUE INTO v_exists
  FROM public.organization_staff os
  WHERE os.organization_id = v_org_id
    AND os.user_id = auth.uid()
  LIMIT 1;

  IF NOT COALESCE(v_exists, FALSE) THEN
    RAISE EXCEPTION 'You are not a member of the active organization (%).', v_org_id
      USING ERRCODE = '42501';
  END IF;
END;
$$;


ALTER FUNCTION "public"."ensure_membership_in_active_org"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_all_organizations"() RETURNS TABLE("id" bigint, "name" "text", "owner_id" "uuid", "created_at" timestamp with time zone, "owner_full_name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF public.get_user_role() != 'system_admin' THEN
    RAISE EXCEPTION 'Access denied. Only system admins can access this resource.';
  END IF;

  RETURN QUERY
  SELECT
    o.id,
    o.name,
    o.owner_id,
    o.created_at,
    p.full_name AS owner_full_name
  FROM public.organizations o
  -- Perbaikan di sini: memastikan perbandingan antara tipe UUID
  LEFT JOIN public.profiles p ON o.owner_id = p.id;
END;
$$;


ALTER FUNCTION "public"."get_all_organizations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_assigned_locations_with_details"() RETURNS TABLE("id" bigint, "name" "text", "address" "text", "is_main_warehouse" boolean, "restaurant_tables" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_role TEXT;
BEGIN
  -- Dapatkan peran pengguna yang sedang login
  v_user_role := public.get_user_role();

  -- Jika perannya adalah admin atau owner, kembalikan semua lokasi
  IF v_user_role IN ('owner', 'super_admin') THEN
    RETURN QUERY
    SELECT
      l.id,
      l.name,
      l.address,
      l.is_main_warehouse,
      (SELECT jsonb_agg(rt.*) FROM public.restaurant_tables rt WHERE rt.location_id = l.id)
    FROM
      public.locations l
    ORDER BY
      l.name;
  ELSE
    -- Jika bukan, kembalikan hanya lokasi yang ditugaskan kepada staf tersebut
    RETURN QUERY
    SELECT
      l.id,
      l.name,
      l.address,
      l.is_main_warehouse,
      (SELECT jsonb_agg(rt.*) FROM public.restaurant_tables rt WHERE rt.location_id = l.id)
    FROM
      public.locations l
    JOIN
      public.location_staff ls ON l.id = ls.location_id
    WHERE
      ls.staff_id = auth.uid()
    ORDER BY
      l.name;
  END IF;
END;
$$;


ALTER FUNCTION "public"."get_assigned_locations_with_details"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_assigned_locations_with_details_v2"() RETURNS TABLE("id" bigint, "name" "text", "address" "text", "is_main_warehouse" boolean, "restaurant_tables" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_org_id bigint;
  v_role   text;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  v_org_id := public.get_current_organization_id();
  v_role   := public.get_current_role();

  IF v_role IN ('owner','super_admin_warehouse') THEN
    RETURN QUERY
    SELECT
      l.id, l.name, l.address, l.is_main_warehouse,
      COALESCE(jsonb_agg(to_jsonb(rt.*)) FILTER (WHERE rt.id IS NOT NULL), '[]'::jsonb) AS restaurant_tables
    FROM public.locations l
    -- CHANGED: hanya join meja yang belum dihapus
    LEFT JOIN public.restaurant_tables rt
      ON rt.location_id = l.id
     AND rt.deleted_at IS NULL
    WHERE l.organization_id = v_org_id
    GROUP BY l.id, l.name, l.address, l.is_main_warehouse
    ORDER BY l.name;
  ELSE
    RETURN QUERY
    SELECT
      l.id, l.name, l.address, l.is_main_warehouse,
      COALESCE(jsonb_agg(to_jsonb(rt.*)) FILTER (WHERE rt.id IS NOT NULL), '[]'::jsonb) AS restaurant_tables
    FROM public.locations l
    JOIN public.location_staff me
      ON me.location_id = l.id
     AND me.staff_id    = auth.uid()
    -- CHANGED: hanya join meja yang belum dihapus
    LEFT JOIN public.restaurant_tables rt
      ON rt.location_id = l.id
     AND rt.deleted_at IS NULL
    WHERE l.organization_id = v_org_id
    GROUP BY l.id, l.name, l.address, l.is_main_warehouse
    ORDER BY l.name;
  END IF;
END;
$$;


ALTER FUNCTION "public"."get_assigned_locations_with_details_v2"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_organization_id"() RETURNS bigint
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'active_organization_id','')::BIGINT,
    NULLIF((current_setting('request.jwt.claims', true)::jsonb->'user_metadata'->>'active_organization_id'),'')::BIGINT,
    NULLIF((current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'active_organization_id'),'')::BIGINT
  );
$$;


ALTER FUNCTION "public"."get_current_organization_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_role"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text;
BEGIN
  -- 1) Sumber utama: profiles.role
  SELECT p.role::text
    INTO v_role
  FROM public.profiles p
  WHERE p.id = auth.uid();

  -- 2) Fallback: user_metadata.role di JWT (kalau ada)
  IF v_role IS NULL OR v_role = '' THEN
    v_role := NULLIF(
      (current_setting('request.jwt.claims', true)::jsonb->'user_metadata'->>'role'),
      ''
    );
  END IF;

  -- 3) Default terakhir
  RETURN COALESCE(v_role, 'authenticated');
END;
$$;


ALTER FUNCTION "public"."get_current_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_detail_by_member_id"("p_member_id" "uuid") RETURNS "public"."customers"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT c.*
  FROM public.customers c
  WHERE c.member_id = p_member_id
    AND c.organization_id = public.get_current_organization_id();
$$;


ALTER FUNCTION "public"."get_customer_detail_by_member_id"("p_member_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_sales_revenue"("days_limit" integer) RETURNS TABLE("sale_date" "date", "revenue" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    date_trunc('day', created_at)::DATE AS sale_date,
    SUM(final_amount) AS revenue
  FROM
    public.orders
  WHERE
    status <> 'canceled'
    AND created_at >= NOW() - (days_limit || ' days')::INTERVAL
  GROUP BY
    sale_date
  ORDER BY
    sale_date ASC;
END;
$$;


ALTER FUNCTION "public"."get_daily_sales_revenue"("days_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_sales_revenue_v2"("days_limit" integer) RETURNS TABLE("sale_date" "date", "revenue" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text := public.get_current_role();
  tz text := 'Asia/Jakarta';
  v_days integer := GREATEST(COALESCE(days_limit, 30), 1);
  start_d date := ((now() AT TIME ZONE tz)::date - (v_days - 1));
  end_d   date := (now() AT TIME ZONE tz)::date;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  IF v_role <> 'owner' THEN
    RAISE EXCEPTION 'Not allowed (owner only)';
  END IF;

  RETURN QUERY
  WITH d AS (
    SELECT generate_series(start_d, end_d, interval '1 day')::date AS sale_date
  ),
  r AS (
    SELECT
      (o.created_at AT TIME ZONE tz)::date AS sale_date,
      COALESCE(SUM(o.final_amount),0)::numeric AS revenue
    FROM public.orders o
    JOIN public.locations l ON l.id = o.location_id
    WHERE l.organization_id = public.get_current_organization_id()
      AND o.status::text = 'completed'
      AND (o.created_at AT TIME ZONE tz)::date BETWEEN start_d AND end_d
    GROUP BY 1
  )
  SELECT d.sale_date, COALESCE(r.revenue, 0)::numeric
  FROM d
  LEFT JOIN r USING (sale_date)
  ORDER BY d.sale_date;
END $$;


ALTER FUNCTION "public"."get_daily_sales_revenue_v2"("days_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dashboard_cards_data"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  -- Revenue
  v_revenue_current_month NUMERIC;
  v_revenue_previous_month NUMERIC;
  v_revenue_growth_rate NUMERIC;

  -- Customers
  v_new_customers_current_month INT;
  v_new_customers_previous_month INT;
  v_total_customers_all_time INT;
  v_total_customers_previous_month INT;
  v_customer_growth_rate NUMERIC;
  v_all_time_customers_growth_rate NUMERIC;

BEGIN
  -- === KALKULASI REVENUE (Diperbaiki) ===
  -- Menghitung semua pesanan KECUALI yang statusnya 'canceled'
  SELECT COALESCE(SUM(final_amount), 0) INTO v_revenue_current_month
  FROM public.orders
  WHERE status <> 'canceled' AND created_at >= date_trunc('month', NOW());

  SELECT COALESCE(SUM(final_amount), 0) INTO v_revenue_previous_month
  FROM public.orders
  WHERE status <> 'canceled'
    AND created_at >= date_trunc('month', NOW() - INTERVAL '1 month')
    AND created_at < date_trunc('month', NOW());

  -- Hitung growth rate revenue
  IF v_revenue_previous_month > 0 THEN
    v_revenue_growth_rate := ((v_revenue_current_month - v_revenue_previous_month) / v_revenue_previous_month) * 100;
  ELSE
    v_revenue_growth_rate := 100;
  END IF;

  -- === KALKULASI PELANGGAN (Logika tetap sama) ===
  SELECT COUNT(*) INTO v_new_customers_current_month
  FROM public.customers
  WHERE created_at >= date_trunc('month', NOW());
  
  SELECT COUNT(*) INTO v_new_customers_previous_month
  FROM public.customers
  WHERE created_at >= date_trunc('month', NOW() - INTERVAL '1 month')
    AND created_at < date_trunc('month', NOW());

  SELECT COUNT(*) INTO v_total_customers_all_time FROM public.customers;
  
  SELECT COUNT(*) INTO v_total_customers_previous_month
  FROM public.customers
  WHERE created_at < date_trunc('month', NOW());

  IF v_new_customers_previous_month > 0 THEN
    v_customer_growth_rate := ((v_new_customers_current_month::NUMERIC - v_new_customers_previous_month::NUMERIC) / v_new_customers_previous_month::NUMERIC) * 100;
  ELSE
    v_customer_growth_rate := 100;
  END IF;

  IF v_total_customers_previous_month > 0 THEN
     v_all_time_customers_growth_rate := ((v_total_customers_all_time::NUMERIC - v_total_customers_previous_month::NUMERIC) / v_total_customers_previous_month::NUMERIC) * 100;
  ELSE
     v_all_time_customers_growth_rate := 100;
  END IF;

  -- Kembalikan semua hasil dalam satu objek JSON
  RETURN jsonb_build_object(
    'revenue_this_month', v_revenue_current_month,
    'revenue_growth_rate', v_revenue_growth_rate,
    'new_customers_this_month', v_new_customers_current_month,
    'customer_growth_rate', v_customer_growth_rate,
    'total_customers_all_time', v_total_customers_all_time,
    'all_time_customers_growth_rate', v_all_time_customers_growth_rate
  );
END;
$$;


ALTER FUNCTION "public"."get_dashboard_cards_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dashboard_cards_data_v2"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text := public.get_current_role();
  v_org  bigint := public.get_current_organization_id();
  tz     text := 'Asia/Jakarta';

  start_this_month timestamptz := (date_trunc('month', (now() AT TIME ZONE tz)) AT TIME ZONE tz);
  start_next_month timestamptz := (date_trunc('month', (now() AT TIME ZONE tz) + interval '1 month') AT TIME ZONE tz);
  start_prev_month timestamptz := (date_trunc('month', (now() AT TIME ZONE tz) - interval '1 month') AT TIME ZONE tz);

  revenue_this_month numeric := 0;
  revenue_prev_month numeric := 0;
  revenue_growth_rate numeric := 0;

  new_customers_this_month bigint := 0;
  new_customers_prev_month bigint := 0;
  customer_growth_rate numeric := 0;

  total_customers_all_time bigint := 0;
  total_customers_prev_eom bigint := 0;
  all_time_customers_growth_rate numeric := 0;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  IF v_role <> 'owner' THEN
    RAISE EXCEPTION 'Not allowed (owner only)';
  END IF;

  -- Revenue bulan ini
  SELECT COALESCE(SUM(o.final_amount),0)::numeric
    INTO revenue_this_month
  FROM public.orders o
  JOIN public.locations l ON l.id = o.location_id
  WHERE l.organization_id = v_org
    AND o.status::text = 'completed'
    AND o.created_at >= start_this_month
    AND o.created_at <  start_next_month;

  -- Revenue bulan lalu
  SELECT COALESCE(SUM(o.final_amount),0)::numeric
    INTO revenue_prev_month
  FROM public.orders o
  JOIN public.locations l ON l.id = o.location_id
  WHERE l.organization_id = v_org
    AND o.status::text = 'completed'
    AND o.created_at >= start_prev_month
    AND o.created_at <  start_this_month;

  revenue_growth_rate :=
    CASE
      WHEN revenue_prev_month > 0
        THEN ROUND(((revenue_this_month - revenue_prev_month) / revenue_prev_month) * 100.0, 2)
      WHEN revenue_prev_month = 0 AND revenue_this_month > 0
        THEN 100
      ELSE 0
    END;

  -- New customers bulan ini & bulan lalu
  SELECT COUNT(*)::bigint
    INTO new_customers_this_month
  FROM public.customers c
  WHERE c.organization_id = v_org
    AND c.created_at >= start_this_month
    AND c.created_at <  start_next_month;

  SELECT COUNT(*)::bigint
    INTO new_customers_prev_month
  FROM public.customers c
  WHERE c.organization_id = v_org
    AND c.created_at >= start_prev_month
    AND c.created_at <  start_this_month;

  customer_growth_rate :=
    CASE
      WHEN new_customers_prev_month > 0
        THEN ROUND(((new_customers_this_month - new_customers_prev_month)::numeric
                    / new_customers_prev_month::numeric) * 100.0, 2)
      WHEN new_customers_prev_month = 0 AND new_customers_this_month > 0
        THEN 100
      ELSE 0
    END;

  -- Total customers kumulatif & posisi akhir bulan lalu
  SELECT COUNT(*)::bigint
    INTO total_customers_all_time
  FROM public.customers c
  WHERE c.organization_id = v_org;

  SELECT COUNT(*)::bigint
    INTO total_customers_prev_eom
  FROM public.customers c
  WHERE c.organization_id = v_org
    AND c.created_at < start_this_month;

  all_time_customers_growth_rate :=
    CASE
      WHEN total_customers_prev_eom > 0
        THEN ROUND(((total_customers_all_time - total_customers_prev_eom)::numeric
                    / total_customers_prev_eom::numeric) * 100.0, 2)
      WHEN total_customers_prev_eom = 0 AND total_customers_all_time > 0
        THEN 100
      ELSE 0
    END;

  RETURN json_build_object(
    'revenue_this_month',               revenue_this_month,
    'revenue_growth_rate',              revenue_growth_rate,
    'new_customers_this_month',         new_customers_this_month,
    'customer_growth_rate',             customer_growth_rate,
    'total_customers_all_time',         total_customers_all_time,
    'all_time_customers_growth_rate',   all_time_customers_growth_rate
  );
END $$;


ALTER FUNCTION "public"."get_dashboard_cards_data_v2"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ingredient_total_stock_overview_v1"("search_query" "text" DEFAULT NULL::"text", "page_num" integer DEFAULT 1, "page_size" integer DEFAULT 20) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role      text   := public.get_current_role();
  v_org       bigint := public.get_current_organization_id();

  v_page_num  integer := GREATEST(COALESCE(page_num, 1), 1);
  v_page_size integer := LEAST(GREATEST(COALESCE(page_size, 20), 1), 200);
  v_offset    integer := (v_page_num - 1) * v_page_size;

  v_q text := NULLIF(TRIM(search_query), '');
  result json;
BEGIN
  PERFORM public.ensure_membership_in_active_org();

  IF v_role NOT IN ('owner','super_admin_warehouse') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  WITH base AS (
    SELECT
      ing.id,
      ing.name,
      ing.unit,
      COALESCE(ing.cost,0)::numeric AS cost
    FROM public.ingredients ing
    WHERE ing.organization_id = v_org
      AND (v_q IS NULL OR ing.name ILIKE '%'||v_q||'%')
  ),
  inv AS (
    SELECT
      i.ingredient_id,
      i.location_id,
      l.name AS location_name,
      COALESCE(i.quantity,0)::numeric AS quantity
    FROM public.inventory i
    JOIN public.locations l ON l.id = i.location_id
    JOIN base b ON b.id = i.ingredient_id
    WHERE l.organization_id = v_org
  ),
  totals AS (
    SELECT
      b.id   AS ingredient_id,
      b.name AS ingredient_name,
      b.unit,
      b.cost,
      COALESCE(SUM(inv.quantity),0)::numeric                      AS total_qty,
      COALESCE(SUM(inv.quantity * COALESCE(b.cost,0)),0)::numeric AS total_value
    FROM base b
    LEFT JOIN inv ON inv.ingredient_id = b.id
    GROUP BY b.id, b.name, b.unit, b.cost
  ),
  per_loc_json AS (
    SELECT
      ingredient_id,
      json_agg(
        jsonb_build_object(
          'location_id',   location_id,
          'location_name', location_name,
          'quantity',      quantity
        )
        ORDER BY location_name
      ) AS per_location
    FROM inv
    GROUP BY ingredient_id
  ),
  rows AS (
    SELECT
      t.ingredient_id,
      t.ingredient_name,
      t.unit,
      t.cost,
      t.total_qty,
      t.total_value,
      COALESCE(p.per_location, '[]'::json) AS per_location
    FROM totals t
    LEFT JOIN per_loc_json p ON p.ingredient_id = t.ingredient_id
  ),
  counted AS (
    SELECT COUNT(*)::bigint AS total_count FROM rows
  ),
  page AS (
    SELECT * FROM rows
    ORDER BY ingredient_name ASC, ingredient_id ASC
    LIMIT v_page_size OFFSET v_offset
  )
  SELECT json_build_object(
    'data',        COALESCE(json_agg(to_jsonb(page) ORDER BY ingredient_name, ingredient_id), '[]'::json),
    'total_count', (SELECT total_count FROM counted)
  )
  INTO result
  FROM page;

  RETURN COALESCE(result, json_build_object('data','[]'::json,'total_count',0));
END $$;


ALTER FUNCTION "public"."get_ingredient_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_inventory_by_location"("p_location_id" bigint) RETURNS TABLE("ingredient_id" bigint, "ingredient_name" "text", "unit" "text", "quantity" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    i.id as ingredient_id,
    i.name as ingredient_name,
    i.unit,
    COALESCE(inv.quantity, 0) as quantity
  FROM
    public.ingredients AS i
  LEFT JOIN
    public.inventory AS inv ON i.id = inv.ingredient_id AND inv.location_id = p_location_id
  ORDER BY
    i.name;
END;
$$;


ALTER FUNCTION "public"."get_inventory_by_location"("p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_inventory_report"("p_location_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_most_used_ingredients JSONB;
  v_low_stock_ingredients JSONB;
BEGIN
  -- 1. Kalkulasi Bahan Baku Paling Banyak Terpakai (30 hari terakhir)
  SELECT
    jsonb_agg(
      jsonb_build_object(
        'name', i.name,
        'unit', i.unit,
        'total_used', usage.total_quantity_used
      ) ORDER BY usage.total_quantity_used DESC
    )
  INTO v_most_used_ingredients
  FROM (
    -- Subquery ini HANYA menghitung total pemakaian per ID bahan
    SELECT
      pr.ingredient_id,
      SUM(oi.quantity * pr.quantity_needed) as total_quantity_used
    FROM
      public.order_items oi
    JOIN
      public.orders o ON oi.order_id = o.id
    JOIN
      public.product_recipes pr ON oi.product_id = pr.product_id
    WHERE
      o.location_id = p_location_id AND o.created_at >= NOW() - INTERVAL '30 days' AND o.status <> 'canceled'
    GROUP BY
      pr.ingredient_id
    LIMIT 10
  ) AS usage
  -- Setelah perhitungan selesai, baru kita JOIN untuk mendapatkan nama dan unit
  JOIN
    public.ingredients i ON usage.ingredient_id = i.id;

  -- 2. Kalkulasi Bahan Baku Stok Menipis (dengan logika sederhana)
  SELECT
    jsonb_agg(
      jsonb_build_object(
        'name', i.name,
        'unit', i.unit,
        'remaining_stock', inv.quantity
      ) ORDER BY inv.quantity ASC
    )
  INTO v_low_stock_ingredients
  FROM
    public.inventory inv
  JOIN
    public.ingredients i ON inv.ingredient_id = i.id
  WHERE
    inv.location_id = p_location_id
    AND (
      (i.unit IN ('gram', 'ml') AND inv.quantity < 1000) OR
      (i.unit = 'pcs' AND inv.quantity < 20)
    );

  -- Gabungkan hasil
  RETURN jsonb_build_object(
    'most_used', COALESCE(v_most_used_ingredients, '[]'::jsonb),
    'low_stock', COALESCE(v_low_stock_ingredients, '[]'::jsonb)
  );
END;
$$;


ALTER FUNCTION "public"."get_inventory_report"("p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_main_warehouse_location_id"() RETURNS bigint
    LANGUAGE "sql" STABLE
    AS $$
  SELECT l.id
  FROM public.locations l
  WHERE l.organization_id = public.get_current_organization_id()
    AND COALESCE(l.is_main_warehouse, false) = true
  LIMIT 1
$$;


ALTER FUNCTION "public"."get_main_warehouse_location_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_main_warehouse_v1"() RETURNS TABLE("id" bigint, "name" "text", "address" "text", "email" "text", "phone_number" "text", "is_main_warehouse" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  perform public.ensure_membership_in_active_org();

  return query
  select l.id, l.name, l.address, l.email, l.phone_number, l.is_main_warehouse
  from public.locations l
  where l.organization_id = public.get_current_organization_id()
    and l.is_main_warehouse = true
  limit 1;
end;
$$;


ALTER FUNCTION "public"."get_main_warehouse_v1"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_order_list"("p_location_id" bigint) RETURNS TABLE("id" bigint, "customer_name" "text", "table_name" "text", "staff_name" "text", "status" "public"."order_status_enum", "total_items" bigint, "final_amount" numeric, "created_at" timestamp with time zone, "order_details" "jsonb", "location_details" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.id,
    c.full_name AS customer_name,
    rt.name AS table_name,
    p.full_name AS staff_name,
    o.status,
    (SELECT SUM(oi.quantity) FROM public.order_items oi WHERE oi.order_id = o.id) AS total_items,
    o.final_amount,
    o.created_at,
    jsonb_build_object(
      'id', o.id, 'status', o.status, 'order_type', o.order_type, 'created_at', o.created_at,
      'customer_name', c.full_name, 'customer_phone', c.phone_number, 'table_name', rt.name,
      'staff_name', p.full_name, 'subtotal', o.total_price, 'discount_amount', o.discount_amount,
      'tax_amount', o.tax_amount, 'final_amount', o.final_amount,
      'items', (SELECT jsonb_agg(item) FROM (
        SELECT prod.name, oi.quantity, oi.price_per_unit, oi.selected_options
        FROM public.order_items oi JOIN public.products prod ON oi.product_id = prod.id
        WHERE oi.order_id = o.id
      ) item)
    ) as order_details,
    jsonb_build_object(
      'id', l.id, 'name', l.name, 'address', l.address, 'email', l.email, 'phone_number', l.phone_number
    ) as location_details
  FROM
    public.orders AS o
  LEFT JOIN public.customers c ON o.customer_id = c.id
  LEFT JOIN public.restaurant_tables rt ON o.table_id = rt.id
  LEFT JOIN public.profiles p ON o.staff_id = p.id
  LEFT JOIN public.locations l ON o.location_id = l.id
  WHERE
    o.location_id = p_location_id
    -- V V V PERUBAHAN LOGIKA FILTER V V V
    AND (o.created_at AT TIME ZONE 'Asia/Jakarta')::DATE = (NOW() AT TIME ZONE 'Asia/Jakarta')::DATE
    -- ^ ^ ^ AKHIR PERUBAHAN LOGIKA ^ ^ ^
  ORDER BY
    o.created_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_order_list"("p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_order_list_v2"("p_location_id" bigint, "p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0) RETURNS TABLE("id" bigint, "customer_name" "text", "table_name" "text", "status" "public"."order_status_enum", "total_items" integer, "final_amount" numeric, "created_at" timestamp with time zone, "order_details" "jsonb", "location_details" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$BEGIN
  -- pastikan lokasi berada pada organisasi aktif & user adalah member org tsb
  PERFORM public.ensure_location_in_current_org(p_location_id);

  RETURN QUERY
  WITH scoped AS (
    SELECT
      o.id,
      o.customer_id,
      o.staff_id,
      o.table_id,
      o.order_type,
      o.status,
      o.total_price,
      o.discount_amount,
      o.tax_amount,
      o.final_amount,
      o.created_at,
      o.location_id
    FROM public.orders o
    WHERE
      o.location_id = p_location_id
      AND (o.created_at AT TIME ZONE 'Asia/Jakarta')::DATE
          = (NOW() AT TIME ZONE 'Asia/Jakarta')::DATE   -- ⬅️ only today
    ORDER BY o.created_at DESC, o.id DESC               -- (tetap di CTE)
    LIMIT LEAST(GREATEST(p_limit,0), 500)
   OFFSET GREATEST(p_offset,0)
  ),
  item_rows AS (
    SELECT
      oi.order_id,
      jsonb_agg(
        jsonb_build_object(
          'name', p.name,
          'quantity', oi.quantity,
          'price_per_unit', oi.price_per_unit,
          'selected_options',
            COALESCE(
              (
                SELECT jsonb_agg(
                         jsonb_build_object(
                           'groupName', e.value->>'groupName',
                           'optionName', e.value->>'optionName',
                           'priceModifier', COALESCE((e.value->>'priceModifier')::numeric, 0)
                         )
                       )
                FROM jsonb_array_elements(oi.selected_options) AS e
                WHERE jsonb_typeof(oi.selected_options) = 'array'
                  AND jsonb_typeof(e.value) = 'object'
              ),
              (
                SELECT jsonb_agg(
                         jsonb_build_object(
                           'groupName', og.name,
                           'optionName', ov.name,
                           'priceModifier', ov.price_modifier
                         )
                       )
                FROM jsonb_array_elements(oi.selected_options) AS e2(value)
                JOIN public.option_values ov
                  ON ov.id = (e2.value)::bigint
                JOIN public.option_groups og
                  ON og.id = ov.option_group_id
                WHERE jsonb_typeof(oi.selected_options) = 'array'
                  AND jsonb_typeof(e2.value) IN ('number','string')
              ),
              '[]'::jsonb
            )
        )
      ) AS items,
      COUNT(*)::int AS cnt
    FROM public.order_items oi
    JOIN scoped s2 ON s2.id = oi.order_id
    JOIN public.products p ON p.id = oi.product_id
    GROUP BY oi.order_id
  )
  SELECT
    s.id,
    cu.full_name AS customer_name,
    rt.name      AS table_name,
    s.status,
    COALESCE(ir.cnt, 0) AS total_items,
    s.final_amount,
    s.created_at,
    jsonb_build_object(
      'id', s.id,
      'status', s.status,
      'order_type', s.order_type,
      'created_at', s.created_at,
      'customer_name', cu.full_name,
      'customer_phone', cu.phone_number,
      'table_name', rt.name,
      'staff_name', pf.full_name,
      'subtotal', s.total_price,
      'discount_amount', s.discount_amount,
      'tax_amount', s.tax_amount,
      'final_amount', s.final_amount,
      'items', COALESCE(ir.items, '[]'::jsonb)
    ) AS order_details,
    jsonb_build_object(
      'id', l.id,
      'name', l.name,
      'address', l.address,
      'email', l.email,
      'phone_number', l.phone_number
    ) AS location_details
  FROM scoped s
  LEFT JOIN item_rows ir        ON ir.order_id = s.id
  LEFT JOIN public.customers cu ON cu.id = s.customer_id
  LEFT JOIN public.restaurant_tables rt ON rt.id = s.table_id
  LEFT JOIN public.profiles pf  ON pf.id = s.staff_id
  JOIN public.locations l       ON l.id = s.location_id
  ORDER BY s.created_at DESC, s.id DESC;  -- ⬅️ kunci urutan output
END;$$;


ALTER FUNCTION "public"."get_order_list_v2"("p_location_id" bigint, "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_paginated_cashier_sessions_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role      text   := public.get_current_role();
  v_viewer    uuid   := auth.uid();
  v_org       bigint := public.get_current_organization_id();
  tz          text   := 'Asia/Jakarta';

  v_page_num  integer := GREATEST(COALESCE(page_num, 1), 1);
  v_page_size integer := LEAST(GREATEST(COALESCE(page_size, 10), 1), 200);
  v_offset    integer := (v_page_num - 1) * v_page_size;

  v_q     text := NULLIF(TRIM(search_query), '');
  v_start timestamptz := COALESCE(start_date, (now() AT TIME ZONE tz) - interval '30 days');
  v_end   timestamptz := COALESCE(end_date,   (now() AT TIME ZONE tz));
  result  json;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  IF v_role NOT IN ('owner','branch_manager','kasir') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  WITH sessions_raw AS (
    SELECT
      cs.id                         AS session_id,
      cs.staff_id,
      cs.location_id,
      COALESCE(cs.opening_balance,0)::numeric  AS opening_balance,
      cs.closing_balance::numeric              AS closing_balance,
      cs.opened_at,
      cs.closed_at
    FROM public.cashier_sessions cs
    JOIN public.locations l ON l.id = cs.location_id
    WHERE l.organization_id = v_org
      AND cs.opened_at >= v_start
      AND cs.opened_at <  v_end
  ),
  sessions_pboc AS (
    SELECT sr.*
    FROM sessions_raw sr
    JOIN public.locations l ON l.id = sr.location_id
    WHERE
      CASE v_role
        WHEN 'owner' THEN TRUE
        WHEN 'branch_manager' THEN EXISTS (
          SELECT 1 FROM public.location_staff ls
          WHERE ls.location_id = sr.location_id
            AND ls.staff_id    = v_viewer
        )
        WHEN 'kasir' THEN sr.staff_id = v_viewer
        ELSE FALSE
      END
  ),
  sessions_enriched AS (
    SELECT
      s.session_id,
      s.location_id,
      l.name                                AS location_name,
      s.staff_id,
      p.full_name                           AS staff_name,
      (s.opened_at AT TIME ZONE tz)         AS opened_at_local,
      (s.closed_at AT TIME ZONE tz)         AS closed_at_local,
      (s.closed_at IS NULL)                 AS is_open,
      s.opening_balance,
      s.closing_balance,
      s.opened_at                           AS t_from,
      COALESCE(s.closed_at, now())          AS t_to
    FROM sessions_pboc s
    JOIN public.locations l ON l.id = s.location_id
    LEFT JOIN public.profiles  p ON p.id = s.staff_id
  ),
  agg_staff AS (
    SELECT
      e.session_id,
      COALESCE(SUM(o.final_amount),0)::numeric AS expected_revenue_staff,
      COUNT(o.id)::bigint                      AS orders_count_staff
    FROM sessions_enriched e
    LEFT JOIN public.orders o
      ON o.location_id = e.location_id
     AND o.staff_id    = e.staff_id
     AND o.created_at >= e.t_from
     AND o.created_at <  e.t_to
     AND o.status::text = 'completed'
    GROUP BY e.session_id
  ),
  agg_location AS (
    SELECT
      e.session_id,
      COALESCE(SUM(o.final_amount),0)::numeric AS expected_revenue_location,
      COUNT(o.id)::bigint                      AS orders_count_location
    FROM sessions_enriched e
    LEFT JOIN public.orders o
      ON o.location_id = e.location_id
     AND o.created_at >= e.t_from
     AND o.created_at <  e.t_to
     AND o.status::text = 'completed'
    GROUP BY e.session_id
  ),
  base AS (
    SELECT
      e.session_id,
      e.location_id,
      e.location_name,
      e.staff_id,
      e.staff_name,
      e.opened_at_local  AS opened_at,
      e.closed_at_local  AS closed_at,
      e.is_open,
      e.opening_balance,
      e.closing_balance,
      a_s.expected_revenue_staff      AS expected_revenue,
      a_s.orders_count_staff          AS orders_count,
      a_l.expected_revenue_location   AS expected_revenue_location,
      a_l.orders_count_location       AS orders_count_location,
      (e.opening_balance + a_s.expected_revenue_staff)::numeric AS expected_cash,
      CASE
        WHEN e.closing_balance IS NULL THEN NULL
        ELSE (e.closing_balance - (e.opening_balance + a_s.expected_revenue_staff))::numeric
      END AS delta_amount,
      CASE
        WHEN e.closing_balance IS NULL THEN 'open'
        WHEN (e.closing_balance - (e.opening_balance + a_s.expected_revenue_staff)) = 0 THEN 'balanced'
        WHEN (e.closing_balance - (e.opening_balance + a_s.expected_revenue_staff)) < 0 THEN 'short'
        ELSE 'over'
      END AS delta_flag,
      -- ✅ perbaikan: pakai *_local, bukan e.closed_at/e.opened_at
      ROUND(
        EXTRACT(
          EPOCH FROM (
            COALESCE(e.closed_at_local, (now() AT TIME ZONE tz)) - e.opened_at_local
          )
        ) / 60.0
      )::bigint AS duration_minutes
    FROM sessions_enriched e
    LEFT JOIN agg_staff    a_s ON a_s.session_id = e.session_id
    LEFT JOIN agg_location a_l ON a_l.session_id = e.session_id
  ),
  filtered AS (
    SELECT *
    FROM base
    WHERE v_q IS NULL OR (
      CAST(session_id AS text) ILIKE '%' || v_q || '%'
      OR COALESCE(location_name,'') ILIKE '%' || v_q || '%'
      OR COALESCE(staff_name,'')   ILIKE '%' || v_q || '%'
    )
  ),
  counted AS (
    SELECT COUNT(*)::bigint AS total_count FROM filtered
  ),
  page AS (
    SELECT *
    FROM filtered
    ORDER BY opened_at DESC, session_id DESC
    LIMIT v_page_size OFFSET v_offset
  )
  SELECT json_build_object(
           'data', COALESCE(json_agg(to_jsonb(page) ORDER BY opened_at DESC, session_id DESC), '[]'::json),
           'total_count', (SELECT total_count FROM counted)
         )
  INTO result
  FROM page;

  RETURN COALESCE(result, json_build_object('data','[]'::json,'total_count',0));
END $$;


ALTER FUNCTION "public"."get_paginated_cashier_sessions_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_paginated_stock_transfers_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "status_filter" "text", "page_num" integer, "page_size" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role      text   := public.get_current_role();
  v_viewer    uuid   := auth.uid();
  v_org       bigint := public.get_current_organization_id();
  tz          text   := 'Asia/Jakarta';

  v_page_num  integer := GREATEST(COALESCE(page_num, 1), 1);
  v_page_size integer := LEAST(GREATEST(COALESCE(page_size, 10), 1), 200);
  v_offset    integer := (v_page_num - 1) * v_page_size;

  v_q     text := NULLIF(TRIM(search_query), '');
  v_stat  text := NULLIF(TRIM(status_filter), '');
  v_start timestamptz := COALESCE(start_date, (now() AT TIME ZONE tz) - interval '30 days');
  v_end   timestamptz := COALESCE(end_date,   (now() AT TIME ZONE tz));
  result  json;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  IF v_role NOT IN ('owner','super_admin_warehouse','branch_manager') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  WITH base AS (
    SELECT
      t.id                                                  AS transfer_id,
      (t.request_date    AT TIME ZONE tz)                   AS request_date_local,
      (t.completion_date AT TIME ZONE tz)                   AS completion_date_local,
      t.status::text                                        AS status,
      fl.id                                                 AS from_location_id,
      tl.id                                                 AS to_location_id,
      fl.name                                               AS from_location_name,
      tl.name                                               AS to_location_name,
      pr.full_name                                          AS requested_by_name
    FROM public.stock_transfers t
    JOIN public.locations fl ON fl.id = t.from_location_id
    JOIN public.locations tl ON tl.id = t.to_location_id
    LEFT JOIN public.profiles pr ON pr.id = t.requested_by_id
    WHERE t.organization_id = v_org
      AND t.request_date >= v_start
      AND t.request_date <  v_end
      AND (v_stat IS NULL OR t.status::text = v_stat)
  ),
  pbac AS (
    SELECT b.*
    FROM base b
    WHERE
      CASE v_role
        WHEN 'owner' THEN TRUE
        WHEN 'super_admin_warehouse' THEN TRUE
        WHEN 'branch_manager' THEN EXISTS (
          SELECT 1
          FROM public.location_staff ls
          WHERE ls.staff_id = v_viewer
            AND ls.location_id IN (b.from_location_id, b.to_location_id)
        )
        ELSE FALSE
      END
  ),
  filtered AS (
    SELECT *
    FROM pbac
    WHERE v_q IS NULL OR (
      CAST(transfer_id AS text) ILIKE '%' || v_q || '%'
      OR COALESCE(from_location_name,'') ILIKE '%' || v_q || '%'
      OR COALESCE(to_location_name,'')   ILIKE '%' || v_q || '%'
      OR COALESCE(requested_by_name,'')  ILIKE '%' || v_q || '%'
      OR EXISTS (
        SELECT 1
        FROM public.stock_transfer_items sti
        JOIN public.ingredients ing ON ing.id = sti.ingredient_id
        WHERE sti.transfer_id = pbac.transfer_id
          AND (ing.name ILIKE '%' || v_q || '%')
      )
    )
  ),
  counted AS (
    SELECT COUNT(*)::bigint AS total_count FROM filtered
  ),
  page AS (
    SELECT *
    FROM filtered
    ORDER BY request_date_local DESC, transfer_id DESC
    LIMIT v_page_size OFFSET v_offset
  ),
  page_with_items AS (
    SELECT
      p.*,
      -- ringkasan item (limited untuk page row)
      COALESCE((
        SELECT json_agg(
                 jsonb_build_object(
                   'ingredient_id',  sti.ingredient_id,
                   'ingredient_name', ing.name,
                   'unit',           ing.unit,
                   'quantity',       sti.quantity
                 )
                 ORDER BY sti.id
               )
        FROM public.stock_transfer_items sti
        JOIN public.ingredients ing ON ing.id = sti.ingredient_id
        WHERE sti.transfer_id = p.transfer_id
      ), '[]'::json) AS items_json,
      -- agregat
      COALESCE((
        SELECT COUNT(*)::bigint FROM public.stock_transfer_items sti
        WHERE sti.transfer_id = p.transfer_id
      ), 0)::bigint AS items_count,
      COALESCE((
        SELECT SUM(sti.quantity) FROM public.stock_transfer_items sti
        WHERE sti.transfer_id = p.transfer_id
      ), 0)::numeric AS total_quantity,
      COALESCE((
        SELECT SUM(sti.quantity * COALESCE(ing.cost,0))
        FROM public.stock_transfer_items sti
        JOIN public.ingredients ing ON ing.id = sti.ingredient_id
        WHERE sti.transfer_id = p.transfer_id
      ), 0)::numeric AS total_cost_estimate
    FROM page p
  )
  SELECT json_build_object(
           'data',
             COALESCE(
               json_agg(
                 jsonb_build_object(
                   'transfer_id',         x.transfer_id,
                   'request_date',        x.request_date_local,
                   'completion_date',     x.completion_date_local,
                   'status',              x.status,
                   'from_location_name',  x.from_location_name,
                   'to_location_name',    x.to_location_name,
                   'requested_by_name',   x.requested_by_name,
                   'items_count',         x.items_count,
                   'total_quantity',      x.total_quantity,
                   'total_cost_estimate', x.total_cost_estimate,
                   'items',               x.items_json
                 )
                 ORDER BY x.request_date_local DESC, x.transfer_id DESC
               ),
               '[]'::json
             ),
           'total_count', (SELECT total_count FROM counted)
         )
  INTO result
  FROM page_with_items x;

  RETURN COALESCE(result, json_build_object('data','[]'::json,'total_count',0));
END $$;


ALTER FUNCTION "public"."get_paginated_stock_transfers_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "status_filter" "text", "page_num" integer, "page_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_paginated_transaction_list"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  query_result JSONB;
  total_count INT;
BEGIN
  -- Hitung total baris yang cocok dengan filter untuk pagination
  SELECT COUNT(*)
  INTO total_count
  FROM public.orders o
  LEFT JOIN public.locations l ON o.location_id = l.id
  LEFT JOIN public.profiles s ON o.staff_id = s.id
  WHERE
    o.created_at BETWEEN start_date AND end_date
    AND (
      -- Logika pencarian: cari di ID order atau nama staf
      o.id::TEXT ILIKE '%' || search_query || '%' OR
      s.full_name ILIKE '%' || search_query || '%'
    );

  -- Ambil data per halaman
  SELECT jsonb_agg(t)
  INTO query_result
  FROM (
    SELECT
      o.id as order_id,
      l.name as location_name,
      s.full_name as staff_name,
      o.order_type,
      o.status,
      o.total_price,
      o.tax_amount,
      o.discount_amount,
      o.final_amount,
      o.created_at,
      -- Kita sertakan detail lengkap untuk dialog
      (SELECT get_order_list.order_details FROM get_order_list(o.location_id) WHERE get_order_list.id = o.id) as order_details
    FROM
      public.orders o
    LEFT JOIN
      public.locations l ON o.location_id = l.id
    LEFT JOIN
      public.profiles s ON o.staff_id = s.id
    WHERE
      o.created_at BETWEEN start_date AND end_date
      AND (
        o.id::TEXT ILIKE '%' || search_query || '%' OR
        s.full_name ILIKE '%' || search_query || '%'
      )
    ORDER BY o.created_at DESC
    LIMIT page_size
    OFFSET (page_num - 1) * page_size
  ) t;

  -- Kembalikan hasil sebagai satu objek JSON
  RETURN jsonb_build_object(
    'data', COALESCE(query_result, '[]'::jsonb),
    'total_count', total_count
  );
END;
$$;


ALTER FUNCTION "public"."get_paginated_transaction_list"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_paginated_transaction_list_v2"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role      text   := public.get_current_role();
  v_org       bigint := public.get_current_organization_id();
  tz          text   := 'Asia/Jakarta';

  v_page_num  integer := GREATEST(COALESCE(page_num, 1), 1);
  v_page_size integer := LEAST(GREATEST(COALESCE(page_size, 10), 1), 200);
  v_offset    integer := (v_page_num - 1) * v_page_size;

  v_q     text := NULLIF(TRIM(search_query), '');
  v_start timestamptz := COALESCE(start_date, (now() AT TIME ZONE tz) - interval '30 days');
  v_end   timestamptz := COALESCE(end_date,   (now() AT TIME ZONE tz));
  result  json;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  IF v_role <> 'owner' THEN
    RAISE EXCEPTION 'Not allowed (owner only)';
  END IF;

  WITH base AS (
    SELECT
      o.id                                                  AS order_id,
      (o.created_at AT TIME ZONE tz)                        AS created_at_local,
      o.status::text                                        AS status,
      o.order_type::text                                    AS order_type,
      COALESCE(o.total_price,     0)::numeric               AS total_price,
      COALESCE(o.tax_amount,      0)::numeric               AS tax_amount,
      COALESCE(o.discount_amount, 0)::numeric               AS discount_amount,
      COALESCE(o.final_amount,    0)::numeric               AS final_amount,
      l.name                                                AS location_name,
      pr.full_name                                          AS staff_name,
      cu.full_name                                          AS customer_name,
      cu.phone_number                                       AS customer_phone,
      rt.name                                               AS table_name
    FROM public.orders o
    JOIN public.locations l         ON l.id = o.location_id
    LEFT JOIN public.profiles pr    ON pr.id = o.staff_id
    LEFT JOIN public.customers cu   ON cu.id = o.customer_id
    LEFT JOIN public.restaurant_tables rt ON rt.id = o.table_id
    WHERE l.organization_id = v_org
      AND o.created_at >= v_start
      AND o.created_at <  v_end
  ),
  filtered AS (
    SELECT *
    FROM base
    WHERE v_q IS NULL OR (
      CAST(order_id AS text) ILIKE '%' || v_q || '%'
      OR COALESCE(customer_name,'')  ILIKE '%' || v_q || '%'
      OR COALESCE(customer_phone,'') ILIKE '%' || v_q || '%'
      OR COALESCE(location_name,'')  ILIKE '%' || v_q || '%'
      OR COALESCE(staff_name,'')     ILIKE '%' || v_q || '%'
      OR COALESCE(order_type,'')     ILIKE '%' || v_q || '%'
      OR COALESCE(status,'')         ILIKE '%' || v_q || '%'
    )
  ),
  page AS (
    SELECT
      f.order_id,
      f.location_name,
      f.staff_name,
      f.order_type,
      f.status,
      f.total_price,
      f.tax_amount,
      f.discount_amount,
      f.final_amount,
      f.created_at_local AS created_at,
      (
        SELECT COALESCE(
          json_agg(
            jsonb_build_object(
              'name',            p.name,
              'quantity',        oi.quantity,       -- ⬅️ diubah dari 'qty'
              'price_per_unit',  oi.price_per_unit,
              'selected_options', COALESCE(oi.selected_options, '[]'::jsonb)
            )
            ORDER BY oi.id
          ),
          '[]'::json
        )
        FROM public.order_items oi
        JOIN public.products p ON p.id = oi.product_id
        WHERE oi.order_id = f.order_id
      ) AS items_json,
      f.customer_name,
      f.customer_phone,
      f.table_name
    FROM filtered f
    ORDER BY f.created_at_local DESC, f.order_id DESC
    LIMIT v_page_size OFFSET v_offset
  )
  SELECT json_build_object(
           'data',
             COALESCE(
               json_agg(
                 jsonb_build_object(
                   'order_id',        p.order_id,
                   'location_name',   p.location_name,
                   'staff_name',      p.staff_name,
                   'order_type',      p.order_type,
                   'status',          p.status,
                   'total_price',     p.total_price,
                   'tax_amount',      p.tax_amount,
                   'discount_amount', p.discount_amount,
                   'final_amount',    p.final_amount,
                   'created_at',      p.created_at,
                   'order_details',   jsonb_build_object(
                     'id',              p.order_id,
                     'status',          p.status,
                     'order_type',      p.order_type,
                     'created_at',      p.created_at,
                     'customer_name',   p.customer_name,
                     'customer_phone',  p.customer_phone,
                     'table_name',      p.table_name,
                     'staff_name',      p.staff_name,
                     'subtotal',        p.total_price,
                     'discount_amount', p.discount_amount,
                     'tax_amount',      p.tax_amount,
                     'final_amount',    p.final_amount,
                     'items',           p.items_json
                   )
                 )
                 ORDER BY p.created_at DESC, p.order_id DESC
               ),
               '[]'::json
             ),
           'total_count', (SELECT COUNT(*)::bigint FROM filtered)
         )
  INTO result
  FROM page p;

  RETURN COALESCE(result, json_build_object('data','[]'::json,'total_count',0));
END $$;


ALTER FUNCTION "public"."get_paginated_transaction_list_v2"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_potential_owners"() RETURNS TABLE("id" "uuid", "full_name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  IF public.get_user_role() != 'system_admin' THEN
    RAISE EXCEPTION 'Access denied.';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name
  FROM public.profiles p
  -- Perbaikan di sini: memastikan perbandingan antara tipe UUID
  WHERE p.id NOT IN (SELECT o.owner_id FROM public.organizations o WHERE o.owner_id IS NOT NULL);
END;
$$;


ALTER FUNCTION "public"."get_potential_owners"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_product_total_stock_overview_v1"("search_query" "text" DEFAULT NULL::"text", "page_num" integer DEFAULT 1, "page_size" integer DEFAULT 20) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role      text   := public.get_current_role();
  v_org       bigint := public.get_current_organization_id();

  v_page_num  integer := GREATEST(COALESCE(page_num, 1), 1);
  v_page_size integer := LEAST(GREATEST(COALESCE(page_size, 20), 1), 200);
  v_offset    integer := (v_page_num - 1) * v_page_size;

  v_q text := NULLIF(TRIM(search_query), '');
  result json;
BEGIN
  PERFORM public.ensure_membership_in_active_org();

  -- Owner & SA Warehouse boleh lihat BI warehouse
  IF v_role NOT IN ('owner', 'super_admin_warehouse') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  WITH vp AS (
    SELECT
      p.id,
      p.name,
      p.organization_id,
      p.stock,                         -- global stock (fallback bila tanpa resep)
      c.name AS category_name,
      EXISTS (
        SELECT 1 FROM public.product_recipes r WHERE r.product_id = p.id
      ) AS has_recipe
    FROM public.products p
    LEFT JOIN public.categories c ON c.id = p.category_id
    WHERE p.organization_id = v_org
      AND (
        v_q IS NULL OR
        p.name ILIKE '%'||v_q||'%' OR
        COALESCE(c.name,'') ILIKE '%'||v_q||'%'
      )
  ),
  -- Stok per lokasi hanya untuk produk yang punya resep (berbasis inventory ingredients)
  loc_avail AS (
    SELECT
      lp.product_id,
      lp.location_id,
      l.name AS location_name,
      MIN(
        FLOOR(
          COALESCE(inv.quantity, 0) / NULLIF(r.quantity_needed, 0)
        )
      )::bigint AS available_stock
    FROM public.location_products lp
    JOIN vp                    ON vp.id = lp.product_id AND vp.has_recipe
    JOIN public.locations l    ON l.id = lp.location_id AND l.organization_id = v_org
    JOIN public.product_recipes r
         ON r.product_id = lp.product_id
    LEFT JOIN public.inventory inv
         ON inv.location_id = lp.location_id
        AND inv.ingredient_id = r.ingredient_id
    GROUP BY lp.product_id, lp.location_id, l.name
  ),
  totals AS (
    SELECT
      vp.id            AS product_id,
      vp.name          AS product_name,
      vp.category_name,
      vp.has_recipe,
      CASE
        WHEN vp.has_recipe THEN COALESCE(SUM(loc_avail.available_stock), 0)::bigint
        ELSE COALESCE(vp.stock, 0)::bigint
      END AS total_stock
    FROM vp
    LEFT JOIN loc_avail ON loc_avail.product_id = vp.id
    GROUP BY vp.id, vp.name, vp.category_name, vp.has_recipe, vp.stock
  ),
  per_loc_json AS (
    SELECT
      product_id,
      json_agg(
        jsonb_build_object(
          'location_id',     location_id,
          'location_name',   location_name,
          'available_stock', available_stock
        )
        ORDER BY location_name
      ) AS per_location
    FROM loc_avail
    GROUP BY product_id
  ),
  rows AS (
    SELECT
      t.product_id,
      t.product_name,
      t.category_name,
      t.total_stock,
      t.has_recipe AS derived_from_recipe,
      COALESCE(pl.per_location, '[]'::json) AS per_location
    FROM totals t
    LEFT JOIN per_loc_json pl ON pl.product_id = t.product_id
  ),
  counted AS (
    SELECT COUNT(*)::bigint AS total_count FROM rows
  ),
  page AS (
    SELECT * FROM rows
    ORDER BY product_name ASC, product_id ASC
    LIMIT v_page_size OFFSET v_offset
  )
  SELECT json_build_object(
    'data',        COALESCE(json_agg(to_jsonb(page) ORDER BY product_name, product_id), '[]'::json),
    'total_count', (SELECT total_count FROM counted)
  )
  INTO result
  FROM page;

  RETURN COALESCE(result, json_build_object('data','[]'::json,'total_count',0));
END $$;


ALTER FUNCTION "public"."get_product_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_products_with_details"("p_location_id" bigint) RETURNS TABLE("id" bigint, "category_id" bigint, "name" "text", "description" "text", "price" numeric, "unit" "text", "image_url" "text", "created_at" timestamp with time zone, "updated_at" timestamp with time zone, "stock" bigint, "category_name" "text", "product_options" "jsonb", "product_recipes" "jsonb")
    LANGUAGE "plpgsql"
    AS $$BEGIN
  -- Blok Keamanan untuk memastikan user punya akses ke lokasi
  IF (
    (SELECT public.get_user_role()) NOT IN ('owner', 'super_admin') AND
    NOT EXISTS (
      SELECT 1 FROM public.location_staff
      WHERE staff_id = auth.uid() AND location_id = p_location_id
    )
  ) THEN
    RAISE EXCEPTION 'Access denied: User does not have permission for this location.';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.category_id,
    p.name,
    p.description,
    p.price,
    p.unit,
    p.image_url,
    p.created_at,
    p.updated_at,
    p.stock,
    c.name as category_name,
    (
      SELECT jsonb_agg(jsonb_build_object('option_group_id', po.option_group_id))
      FROM public.product_options AS po WHERE po.product_id = p.id
    ) AS product_options,
    (
      SELECT jsonb_agg(jsonb_build_object(
        'ingredient_id', pr.ingredient_id,
        'quantity_needed', pr.quantity_needed
      ))
      FROM public.product_recipes AS pr WHERE pr.product_id = p.id
    ) AS product_recipes
  FROM
    public.products AS p
  INNER JOIN
    public.location_products AS lp ON p.id = lp.product_id
  LEFT JOIN
    public.categories AS c ON p.category_id = c.id
  WHERE
    lp.location_id = p_location_id
    AND p.deleted_at IS NULL
  ORDER BY
    p.name;
END;$$;


ALTER FUNCTION "public"."get_products_with_details"("p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_settings_for_active_org"() RETURNS TABLE("key" "text", "value" "text")
    LANGUAGE "sql"
    AS $$
  SELECT s."key" AS key, s."value" AS value
  FROM public.settings s
  WHERE s.organization_id = public.get_current_organization_id()
  ORDER BY s."key";
$$;


ALTER FUNCTION "public"."get_settings_for_active_org"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transaction_report_data"("start_date" timestamp with time zone, "end_date" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_summary JSONB;
  v_details JSONB;
BEGIN
  -- 1. Hitung data ringkasan (summary) - (Tidak ada perubahan di sini)
  SELECT
    jsonb_build_object(
      'start_date', start_date, 'end_date', end_date,
      'total_transactions', COUNT(o.id), 'gross_sales', COALESCE(SUM(o.total_price), 0),
      'total_discount', COALESCE(SUM(o.discount_amount), 0), 'total_tax', COALESCE(SUM(o.tax_amount), 0),
      'net_sales', COALESCE(SUM(o.final_amount), 0),
      'total_items_sold', (SELECT COALESCE(SUM(oi.quantity), 0) FROM public.order_items oi WHERE oi.order_id = ANY(ARRAY_AGG(o.id)))
    )
  INTO v_summary
  FROM public.orders AS o
  WHERE o.status <> 'canceled' AND o.created_at BETWEEN start_date AND end_date;

  -- 2. Ambil daftar detail semua transaksi DENGAN DETAIL FINANSIAL
  SELECT
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'created_at', o.created_at,
        'customer_name', COALESCE(c.full_name, 'Walk-in'),
        'staff_name', s.full_name,
        'total_price', o.total_price,         -- <-- TAMBAHAN BARU
        'discount_amount', o.discount_amount, -- <-- TAMBAHAN BARU
        'tax_amount', o.tax_amount,           -- <-- TAMBAHAN BARU
        'final_amount', o.final_amount,
        'items', (
          SELECT jsonb_agg(
            jsonb_build_object(
              'name', p.name, 'quantity', oi.quantity, 'price_per_unit', oi.price_per_unit,
              'options', oi.selected_options
            )
          )
          FROM public.order_items oi JOIN public.products p ON oi.product_id = p.id
          WHERE oi.order_id = o.id
        )
      ) ORDER BY o.created_at ASC
    )
  INTO v_details
  FROM public.orders o
  LEFT JOIN public.customers c ON o.customer_id = c.id
  LEFT JOIN public.profiles s ON o.staff_id = s.id
  WHERE o.status <> 'canceled' AND o.created_at BETWEEN start_date AND end_date;

  -- 3. Gabungkan keduanya menjadi satu hasil JSON (Tidak ada perubahan)
  RETURN jsonb_build_object(
    'summary', v_summary,
    'details', COALESCE(v_details, '[]'::jsonb)
  );
END;
$$;


ALTER FUNCTION "public"."get_transaction_report_data"("start_date" timestamp with time zone, "end_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transaction_summary"("start_date" timestamp with time zone, "end_date" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  summary JSONB;
BEGIN
  SELECT
    jsonb_build_object(
      'start_date', start_date,
      'end_date', end_date,
      'total_transactions', COUNT(o.id),
      'gross_sales', COALESCE(SUM(o.total_price), 0),
      'total_discount', COALESCE(SUM(o.discount_amount), 0),
      'total_tax', COALESCE(SUM(o.tax_amount), 0),
      'net_sales', COALESCE(SUM(o.final_amount), 0),
      'total_items_sold', (SELECT COALESCE(SUM(oi.quantity), 0) FROM public.order_items oi WHERE oi.order_id = ANY(ARRAY_AGG(o.id)))
    )
  INTO summary
  FROM
    public.orders AS o
  WHERE
    o.status <> 'canceled'
    AND o.created_at BETWEEN start_date AND end_date;

  RETURN summary;
END;
$$;


ALTER FUNCTION "public"."get_transaction_summary"("start_date" timestamp with time zone, "end_date" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_organizations"() RETURNS TABLE("id" bigint, "name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.id,
    o.name
  FROM public.organizations o
  JOIN public.organization_staff os ON o.id = os.organization_id
  WHERE os.user_id = auth.uid()
  ORDER BY o.name;
END;
$$;


ALTER FUNCTION "public"."get_user_organizations"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN (
    SELECT role::text
    FROM public.profiles
    WHERE id = auth.uid()
  );
END;
$$;


ALTER FUNCTION "public"."get_user_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_warehouse_bi_overview_v1"("start_date" timestamp with time zone DEFAULT NULL::timestamp with time zone, "end_date" timestamp with time zone DEFAULT NULL::timestamp with time zone, "top_limit" integer DEFAULT 5) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role  text   := public.get_current_role();
  v_org   bigint := public.get_current_organization_id();
  tz      text   := 'Asia/Jakarta';

  v_start timestamptz := COALESCE(start_date, (now() AT TIME ZONE tz) - interval '30 days');
  v_end   timestamptz := COALESCE(end_date,   (now() AT TIME ZONE tz));

  result  json;
BEGIN
  PERFORM public.ensure_membership_in_active_org();

  IF v_role NOT IN ('owner','super_admin_warehouse') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  WITH inv AS (
    SELECT
      i.location_id,
      i.ingredient_id,
      i.quantity,
      ing.cost,
      l.name AS location_name
    FROM public.inventory i
    JOIN public.locations   l   ON l.id = i.location_id
    JOIN public.ingredients ing ON ing.id = i.ingredient_id
    WHERE l.organization_id = v_org
      AND ing.organization_id = v_org
  ),
  totals AS (
    SELECT
      (SELECT COUNT(*)::bigint
       FROM public.ingredients ing
       WHERE ing.organization_id = v_org)                                    AS total_ingredients,
      (SELECT COUNT(*)::bigint
       FROM public.locations l
       WHERE l.organization_id = v_org)                                      AS total_locations,
      COALESCE(SUM(inv.quantity), 0)::numeric                                AS total_inventory_qty,
      COALESCE(SUM(inv.quantity * COALESCE(inv.cost,0)), 0)::numeric         AS total_inventory_value,
      (SELECT COUNT(*)::bigint
       FROM public.stock_transfers t
       WHERE t.organization_id = v_org
         AND t.status::text = 'pending')                                     AS pending_transfers,
      (SELECT COUNT(*)::bigint
       FROM public.stock_transfers t
       WHERE t.organization_id = v_org
         AND t.status::text = 'completed'
         AND t.completion_date IS NOT NULL
         AND t.completion_date >= v_start AND t.completion_date < v_end)     AS completed_transfers_in_range,
      (SELECT COALESCE(AVG(EXTRACT(EPOCH FROM (t.completion_date - t.request_date))/60.0), 0)
       FROM public.stock_transfers t
       WHERE t.organization_id = v_org
         AND t.status::text = 'completed'
         AND t.completion_date IS NOT NULL
         AND t.completion_date >= v_start AND t.completion_date < v_end)     AS avg_lead_time_minutes
    FROM inv
  ),
  per_location AS (
    SELECT
      inv.location_id,
      inv.location_name,
      COUNT(DISTINCT inv.ingredient_id)::bigint                               AS item_count,
      COALESCE(SUM(inv.quantity), 0)::numeric                                 AS total_qty,
      COALESCE(SUM(inv.quantity * COALESCE(inv.cost,0)), 0)::numeric          AS total_value
    FROM inv
    GROUP BY inv.location_id, inv.location_name
  ),
  moved AS (
    SELECT
      sti.ingredient_id,
      ing.name        AS ingredient_name,
      ing.unit        AS unit,
      COALESCE(SUM(sti.quantity), 0)::numeric                                  AS moved_qty,
      COALESCE(SUM(sti.quantity * COALESCE(ing.cost,0)), 0)::numeric           AS moved_value
    FROM public.stock_transfer_items sti
    JOIN public.stock_transfers     t   ON t.id = sti.transfer_id
    JOIN public.ingredients         ing ON ing.id = sti.ingredient_id
    WHERE t.organization_id = v_org
      AND ing.organization_id = v_org
      AND t.status::text = 'completed'
      AND t.completion_date IS NOT NULL
      AND t.completion_date >= v_start AND t.completion_date < v_end
    GROUP BY sti.ingredient_id, ing.name, ing.unit
    ORDER BY moved_qty DESC, moved_value DESC, ingredient_name ASC
    LIMIT LEAST(GREATEST(COALESCE(top_limit,5), 1), 50)
  )
  SELECT json_build_object(
    'totals', json_build_object(
      'total_ingredients',               (SELECT total_ingredients               FROM totals),
      'total_locations',                 (SELECT total_locations                 FROM totals),
      'total_inventory_qty',             (SELECT total_inventory_qty             FROM totals),
      'total_inventory_value',           (SELECT total_inventory_value           FROM totals),
      'pending_transfers',               (SELECT pending_transfers               FROM totals),
      'completed_transfers_in_range',    (SELECT completed_transfers_in_range    FROM totals),
      'avg_lead_time_minutes',           (SELECT avg_lead_time_minutes           FROM totals)
    ),
    'per_location', COALESCE((
      SELECT json_agg(jsonb_build_object(
               'location_id',   pl.location_id,
               'location_name', pl.location_name,
               'item_count',    pl.item_count,
               'total_qty',     pl.total_qty,
               'total_value',   pl.total_value
             ) ORDER BY pl.location_name)
      FROM per_location pl
    ), '[]'::json),
    'top_moved_ingredients', COALESCE((
      SELECT json_agg(jsonb_build_object(
               'ingredient_id',   m.ingredient_id,
               'ingredient_name', m.ingredient_name,
               'unit',            m.unit,
               'moved_qty',       m.moved_qty,
               'moved_value',     m.moved_value
             ))
      FROM moved m
    ), '[]'::json)
  )
  INTO result;

  RETURN result;
END $$;


ALTER FUNCTION "public"."get_warehouse_bi_overview_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "top_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_viewer_role_valid"("roles_to_check" "text"[]) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid() AND role::text = ANY(roles_to_check)
  );
END;
$$;


ALTER FUNCTION "public"."is_viewer_role_valid"("roles_to_check" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_stock_transfer_v2"("p_from_location_id" bigint, "p_to_location_id" bigint, "p_items" "jsonb") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_org_id    bigint := public.get_current_organization_id();
  v_role      text   := public.get_current_role();
  v_main_id   bigint := public.get_main_warehouse_location_id();
  v_from_id   bigint;
  v_to_id     bigint;
  v_id        bigint;
  r           jsonb;
  v_from_is_main boolean;
  v_to_is_main   boolean;
BEGIN
  IF v_main_id IS NULL THEN
    RAISE EXCEPTION 'Main warehouse is not set for this organization';
  END IF;

  PERFORM public.ensure_location_in_current_org(p_from_location_id);
  PERFORM public.ensure_location_in_current_org(p_to_location_id);

  SELECT COALESCE(is_main_warehouse,false) INTO v_from_is_main FROM public.locations WHERE id = p_from_location_id;
  SELECT COALESCE(is_main_warehouse,false) INTO v_to_is_main   FROM public.locations WHERE id = p_to_location_id;

  -- Normalisasi arah: selalu MAIN -> CABANG
  IF v_from_is_main = true AND v_to_is_main = false THEN
    v_from_id := p_from_location_id;
    v_to_id   := p_to_location_id;
  ELSIF v_from_is_main = false AND v_to_is_main = true THEN
    v_from_id := p_to_location_id;   -- swap
    v_to_id   := p_from_location_id;
  ELSIF v_from_is_main = true AND v_to_is_main = true THEN
    RAISE EXCEPTION 'Both locations cannot be main warehouse';
  ELSE
    -- keduanya bukan main: paksa dari MAIN → ke cabang (pilih cabang = p_to_location_id)
    v_from_id := v_main_id;
    v_to_id   := p_to_location_id;
  END IF;

  -- Guard peran
  IF v_role = 'branch_manager' THEN
    -- BM harus assigned ke lokasi tujuan (cabang)
    PERFORM 1 FROM public.location_staff ls
      WHERE ls.location_id = v_to_id AND ls.staff_id = auth.uid();
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Branch Manager can only request for their assigned branch';
    END IF;
  ELSIF v_role NOT IN ('owner','super_admin_warehouse') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  INSERT INTO public.stock_transfers(from_location_id,to_location_id,organization_id,status,requested_by_id)
  VALUES (v_from_id, v_to_id, v_org_id, 'pending', auth.uid())
  RETURNING id INTO v_id;

  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
    INSERT INTO public.stock_transfer_items(transfer_id,ingredient_id,quantity)
    VALUES (v_id, (r->>'ingredient_id')::bigint, (r->>'quantity')::numeric);
  END LOOP;

  RETURN v_id;
END $$;


ALTER FUNCTION "public"."request_stock_transfer_v2"("p_from_location_id" bigint, "p_to_location_id" bigint, "p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_customers_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_customers_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_main_warehouse_v1"("p_location_id" bigint) RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id bigint := public.get_current_organization_id();
  v_role   text   := public.get_current_role();
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  PERFORM public.ensure_location_in_current_org(p_location_id);

  IF v_role <> 'owner' THEN
    RAISE EXCEPTION 'Only owner can set main warehouse' USING ERRCODE='42501';
  END IF;

  -- Matikan main yang sebelumnya (jika ada)
  UPDATE public.locations
     SET is_main_warehouse = false
   WHERE organization_id = v_org_id
     AND is_main_warehouse = true;

  -- Set lokasi terpilih jadi main
  UPDATE public.locations
     SET is_main_warehouse = true
   WHERE id = p_location_id
     AND organization_id = v_org_id;

  RETURN p_location_id;
END $$;


ALTER FUNCTION "public"."set_main_warehouse_v1"("p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_product_recipe_v1"("p_product_id" bigint, "p_items" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text := public.get_current_role();
  r jsonb;
BEGIN
  PERFORM public.ensure_membership_in_active_org();

  -- produk harus milik org-aktif
  PERFORM 1
  FROM public.products p
  WHERE p.id = p_product_id
    AND p.organization_id = public.get_current_organization_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found in your organization';
  END IF;

  -- role yang boleh edit resep (ubah bila mau SAW ikut)
  IF v_role NOT IN ('owner','branch_manager') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  -- hapus semua resep lama untuk produk ini (org-scope implied)
  DELETE FROM public.product_recipes pr
  USING public.products p
  WHERE pr.product_id = p_product_id
    AND p.id = p_product_id
    AND p.organization_id = public.get_current_organization_id();

  -- insert yang baru
  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    INSERT INTO public.product_recipes(product_id, ingredient_id, quantity_needed)
    VALUES (
      p_product_id,
      (r->>'ingredient_id')::bigint,
      (r->>'quantity_needed')::numeric
    );
  END LOOP;
END $$;


ALTER FUNCTION "public"."set_product_recipe_v1"("p_product_id" bigint, "p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_all_product_stocks_by_location"("p_location_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text := public.get_current_role();
  prod RECORD;
BEGIN
  -- Hardening: pastikan user & lokasi dalam org-aktif
  PERFORM public.ensure_membership_in_active_org();
  PERFORM public.ensure_location_in_current_org(p_location_id);

  -- PBAC:
  IF v_role IN ('owner','super_admin_warehouse') THEN
    -- full access dalam org-aktif
    NULL;

  ELSIF v_role IN ('branch_manager','kasir','koki') THEN
    -- hanya boleh untuk lokasi yang di-assign
    PERFORM 1
      FROM public.location_staff ls
     WHERE ls.location_id = p_location_id
       AND ls.staff_id    = auth.uid();
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Access denied: You do not have permission to sync stocks.';
    END IF;

  ELSE
    RAISE EXCEPTION 'Access denied: You do not have permission to sync stocks.';
  END IF;

  -- Loop semua produk yang terhubung ke lokasi ini
  FOR prod IN
    SELECT lp.product_id
      FROM public.location_products lp
     WHERE lp.location_id = p_location_id
  LOOP
    -- Update kolom 'stock' pada products untuk org-aktif
    UPDATE public.products p
       SET stock = public.calculate_single_product_stock(prod.product_id, p_location_id)
     WHERE p.id = prod.product_id
       AND p.organization_id = public.get_current_organization_id();
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."sync_all_product_stocks_by_location"("p_location_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_product_options"("p_product_id" bigint, "p_option_group_ids" bigint[]) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Langkah 1: Hapus semua koneksi varian lama untuk produk ini
  DELETE FROM public.product_options
  WHERE product_id = p_product_id;

  -- Langkah 2: Jika ada ID grup baru yang dikirim, masukkan koneksi yang baru
  IF array_length(p_option_group_ids, 1) > 0 THEN
    INSERT INTO public.product_options (product_id, option_group_id)
    SELECT p_product_id, unnest(p_option_group_ids);
  END IF;
END;
$$;


ALTER FUNCTION "public"."sync_product_options"("p_product_id" bigint, "p_option_group_ids" bigint[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_order_status"("p_order_id" bigint, "p_new_status" "public"."order_status_enum") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  current_status order_status_enum;
  current_status_rank INT;
  new_status_rank INT;
BEGIN
  -- Dapatkan status pesanan saat ini
  SELECT status INTO current_status FROM public.orders WHERE id = p_order_id;
  
  -- ATURAN 1: Pesanan yang sudah selesai tidak bisa diubah.
  IF current_status IN ('completed', 'canceled') THEN
    RAISE EXCEPTION 'Pesanan #% tidak bisa diubah karena sudah selesai.', p_order_id;
  END IF;

  -- Berikan peringkat numerik untuk setiap status
  current_status_rank := (CASE current_status
                            WHEN 'pending' THEN 1
                            WHEN 'on_cooking' THEN 2
                            WHEN 'ready_to_serve' THEN 3
                            WHEN 'served' THEN 4
                            WHEN 'completed' THEN 5
                            ELSE 99 END); -- 'canceled' bisa dianggap di luar urutan utama

  new_status_rank := (CASE p_new_status
                        WHEN 'pending' THEN 1
                        WHEN 'on_cooking' THEN 2
                        WHEN 'ready_to_serve' THEN 3
                        WHEN 'served' THEN 4
                        WHEN 'completed' THEN 5
                        ELSE 99 END);

  -- ATURAN 2: Status tidak bisa mundur (peringkat baru tidak boleh lebih kecil dari yang lama)
  IF new_status_rank < current_status_rank THEN
    RAISE EXCEPTION 'Tidak bisa mengembalikan status dari % ke %.', current_status, p_new_status;
  END IF;

  -- Jika semua aturan lolos, update status
  UPDATE public.orders
  SET status = p_new_status
  WHERE id = p_order_id;
END;
$$;


ALTER FUNCTION "public"."update_order_status"("p_order_id" bigint, "p_new_status" "public"."order_status_enum") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_product_stock"("p_product_id" bigint, "p_new_stock" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  -- Cek izin di dalam fungsi: hanya peran tertentu yang boleh menjalankan
  IF (SELECT public.get_user_role()) NOT IN ('kasir', 'owner', 'super_admin') THEN
    RAISE EXCEPTION 'Permission denied: You are not authorized to update stock.';
  END IF;

  -- Jika diizinkan, update hanya kolom stok
  UPDATE public.products
  SET 
    stock = p_new_stock,
    updated_at = NOW() -- Sekalian update timestamp
  WHERE id = p_product_id;
END;
$$;


ALTER FUNCTION "public"."update_product_stock"("p_product_id" bigint, "p_new_stock" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_product_stock_manual_v1"("p_product_id" bigint, "p_new_stock" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role text := public.get_current_role();
BEGIN
  IF v_role NOT IN ('owner','super_admin_warehouse','branch_manager','kasir') THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  UPDATE public.products
     SET stock = p_new_stock
   WHERE id = p_product_id
     AND organization_id = public.get_current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found in your organization';
  END IF;
END $$;


ALTER FUNCTION "public"."update_product_stock_manual_v1"("p_product_id" bigint, "p_new_stock" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_staff_role"("p_staff_id" "uuid", "p_new_role" "public"."user_role") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_caller_role TEXT := public.get_user_role();
  v_caller_org_id BIGINT := public.get_current_organization_id();
  v_target_user_org_id BIGINT;
BEGIN
  -- Dapatkan organisasi tempat staff target berada
  SELECT organization_id INTO v_target_user_org_id
  FROM public.organization_staff
  WHERE user_id = p_staff_id AND organization_id = v_caller_org_id;

  -- Aturan Keamanan
  IF v_caller_role = 'system_admin' THEN
    -- System admin boleh melakukan apa saja
  ELSIF v_caller_role = 'owner' THEN
    -- Owner tidak boleh membuat seseorang menjadi system_admin
    IF p_new_role = 'system_admin' THEN
      RAISE EXCEPTION 'Owners cannot assign the system_admin role.';
    END IF;
    -- Owner hanya bisa mengubah peran staf di dalam organisasinya sendiri
    IF v_target_user_org_id IS NULL THEN
       RAISE EXCEPTION 'Target user is not in your organization.';
    END IF;
  ELSE
    -- Peran lain tidak boleh mengubah peran sama sekali
    RAISE EXCEPTION 'Access denied: You do not have permission to update roles.';
  END IF;

  -- Jika lolos pengecekan, update peran
  UPDATE public.profiles SET role = p_new_role WHERE id = p_staff_id;
END;
$$;


ALTER FUNCTION "public"."update_staff_role"("p_staff_id" "uuid", "p_new_role" "public"."user_role") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_staff_role_v2"("p_staff_id" "uuid", "p_new_role" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org_id bigint;
  v_my_role text;
  v_row jsonb;
BEGIN
  PERFORM public.ensure_membership_in_active_org();
  v_org_id := public.get_current_organization_id();
  v_my_role := public.get_current_role();

  IF v_my_role <> 'owner' THEN
    RAISE EXCEPTION 'Only owner can change staff roles in this organization.' USING ERRCODE = '42501';
  END IF;

  -- staff harus member org aktif
  IF NOT EXISTS (
    SELECT 1 FROM public.organization_staff os
    WHERE os.organization_id = v_org_id AND os.user_id = p_staff_id
  ) THEN
    RAISE EXCEPTION 'Target staff is not a member of this organization (%).', v_org_id USING ERRCODE = '42501';
  END IF;

  -- Valid roles yang boleh ditetapkan oleh owner (bukan system_admin)
  IF p_new_role NOT IN ('owner','super_admin_warehouse','branch_manager','kasir','koki') THEN
    RAISE EXCEPTION 'Invalid or forbidden role: %', p_new_role USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
     SET role = p_new_role::public.user_role
   WHERE id = p_staff_id
   RETURNING to_jsonb(profiles.*) INTO v_row;

  RETURN v_row;
END;
$$;


ALTER FUNCTION "public"."update_staff_role_v2"("p_staff_id" "uuid", "p_new_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_setting_for_active_org"("p_key" "text", "p_value" "text") RETURNS TABLE("key" "text", "value" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
  v_org_id bigint := public.get_current_organization_id();
  v_role   text   := public.get_user_role();
  r        record;
BEGIN
  IF v_role NOT IN ('owner','branch_manager') THEN
    RAISE EXCEPTION 'Access denied: role % cannot update settings', v_role
      USING ERRCODE = '42501';
  END IF;

  -- Validasi numerik sederhana untuk key tertentu
  IF p_key IN ('tax_percent', 'rupiah_per_point') THEN
    IF trim(p_value) = '' OR trim(p_value) !~ '^[0-9]+(\.[0-9]+)?$' THEN
      RAISE EXCEPTION 'Invalid numeric value for %: "%"', p_key, p_value
        USING ERRCODE = '22P02';
    END IF;
  END IF;

  INSERT INTO public.settings AS s ("organization_id", "key", "value")
  VALUES (v_org_id, p_key, p_value)
  ON CONFLICT ON CONSTRAINT settings_org_key_unique
  DO UPDATE SET "value" = EXCLUDED."value"
  RETURNING s."key", s."value"
  INTO r;

  key := r."key";
  value := r."value";
  RETURN NEXT;
END;
$_$;


ALTER FUNCTION "public"."upsert_setting_for_active_org"("p_key" "text", "p_value" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cashier_sessions" (
    "id" bigint NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "location_id" bigint NOT NULL,
    "opening_balance" numeric(12,2) NOT NULL,
    "closing_balance" numeric(12,2),
    "opened_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "closed_at" timestamp with time zone,
    "status" "public"."session_status_enum" DEFAULT 'open'::"public"."session_status_enum" NOT NULL
);


ALTER TABLE "public"."cashier_sessions" OWNER TO "postgres";


ALTER TABLE "public"."cashier_sessions" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."cashier_sessions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" bigint DEFAULT "public"."get_current_organization_id"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


ALTER TABLE "public"."categories" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."categories_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."customers" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."customers_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."discounts" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "type" "text" NOT NULL,
    "value" numeric NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "unique_code" "text" NOT NULL,
    "organization_id" bigint DEFAULT "public"."get_current_organization_id"() NOT NULL,
    CONSTRAINT "discounts_type_check" CHECK (("type" = ANY (ARRAY['percentage'::"text", 'fixed_amount'::"text"])))
);


ALTER TABLE "public"."discounts" OWNER TO "postgres";


ALTER TABLE "public"."discounts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."discounts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."ingredients" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "unit" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cost" numeric(10,2) DEFAULT 0 NOT NULL,
    "organization_id" bigint DEFAULT "public"."get_current_organization_id"() NOT NULL,
    CONSTRAINT "ingredients_unit_check" CHECK (("unit" = ANY (ARRAY['gram'::"text", 'ml'::"text", 'pcs'::"text"])))
);


ALTER TABLE "public"."ingredients" OWNER TO "postgres";


ALTER TABLE "public"."ingredients" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."ingredients_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."inventory" (
    "id" bigint NOT NULL,
    "ingredient_id" bigint NOT NULL,
    "location_id" bigint NOT NULL,
    "quantity" numeric(10,2) DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."inventory" OWNER TO "postgres";


ALTER TABLE "public"."inventory" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."inventory_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."location_products" (
    "id" bigint NOT NULL,
    "location_id" bigint NOT NULL,
    "product_id" bigint NOT NULL
);


ALTER TABLE "public"."location_products" OWNER TO "postgres";


ALTER TABLE "public"."location_products" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."location_products_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."location_staff" (
    "id" bigint NOT NULL,
    "location_id" bigint NOT NULL,
    "staff_id" "uuid" NOT NULL
);


ALTER TABLE "public"."location_staff" OWNER TO "postgres";


ALTER TABLE "public"."location_staff" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."location_staff_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "is_main_warehouse" boolean DEFAULT false NOT NULL,
    "email" "text",
    "phone_number" "text",
    "organization_id" bigint DEFAULT "public"."get_current_organization_id"() NOT NULL
);


ALTER TABLE "public"."locations" OWNER TO "postgres";


ALTER TABLE "public"."locations" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."locations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."option_groups" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "selection_type" "text" DEFAULT 'single'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" bigint DEFAULT "public"."get_current_organization_id"() NOT NULL,
    CONSTRAINT "option_groups_selection_type_check" CHECK (("selection_type" = ANY (ARRAY['single'::"text", 'multiple'::"text"])))
);


ALTER TABLE "public"."option_groups" OWNER TO "postgres";


ALTER TABLE "public"."option_groups" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."option_groups_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."option_values" (
    "id" bigint NOT NULL,
    "option_group_id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "price_modifier" numeric(10,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."option_values" OWNER TO "postgres";


ALTER TABLE "public"."option_values" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."option_values_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" bigint NOT NULL,
    "order_id" bigint NOT NULL,
    "product_id" bigint NOT NULL,
    "quantity" integer NOT NULL,
    "price_per_unit" numeric(10,2) NOT NULL,
    "notes" "text",
    "selected_options" "jsonb",
    CONSTRAINT "order_items_quantity_check" CHECK (("quantity" > 0))
);


ALTER TABLE "public"."order_items" OWNER TO "postgres";


ALTER TABLE "public"."order_items" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."order_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" bigint NOT NULL,
    "location_id" bigint NOT NULL,
    "customer_id" bigint,
    "staff_id" "uuid" NOT NULL,
    "table_id" bigint,
    "order_type" "public"."order_type_enum" DEFAULT 'dine_in'::"public"."order_type_enum" NOT NULL,
    "status" "public"."order_status_enum" DEFAULT 'pending'::"public"."order_status_enum" NOT NULL,
    "total_price" numeric(12,2) DEFAULT 0 NOT NULL,
    "tax_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "final_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "organization_id" bigint NOT NULL
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


ALTER TABLE "public"."orders" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."orders_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."organization_staff" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "organization_id" bigint NOT NULL
);


ALTER TABLE "public"."organization_staff" OWNER TO "postgres";


ALTER TABLE "public"."organization_staff" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."organization_staff_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "owner_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "subscription_status" "text",
    "industry" "text",
    "address" "text"
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


ALTER TABLE "public"."organizations" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."organizations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."product_options" (
    "id" bigint NOT NULL,
    "product_id" bigint NOT NULL,
    "option_group_id" bigint NOT NULL
);


ALTER TABLE "public"."product_options" OWNER TO "postgres";


ALTER TABLE "public"."product_options" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."product_options_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."product_recipes" (
    "id" bigint NOT NULL,
    "product_id" bigint NOT NULL,
    "ingredient_id" bigint NOT NULL,
    "quantity_needed" numeric(10,2) NOT NULL
);


ALTER TABLE "public"."product_recipes" OWNER TO "postgres";


ALTER TABLE "public"."product_recipes" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."product_recipes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" bigint NOT NULL,
    "category_id" bigint,
    "name" "text" NOT NULL,
    "description" "text",
    "price" numeric(10,2) DEFAULT 0 NOT NULL,
    "unit" "text" DEFAULT 'serving'::"text" NOT NULL,
    "image_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stock" bigint,
    "organization_id" bigint NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."products" OWNER TO "postgres";


COMMENT ON COLUMN "public"."products"."stock" IS 'jumlah stock product';



ALTER TABLE "public"."products" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."products_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "username" "text",
    "avatar_url" "text",
    "phone_number" "text",
    "role" "public"."user_role" DEFAULT 'kasir'::"public"."user_role" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."restaurant_tables" (
    "id" bigint NOT NULL,
    "location_id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "capacity" integer DEFAULT 2 NOT NULL,
    "status" "public"."table_status_enum" DEFAULT 'available'::"public"."table_status_enum" NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "public"."restaurant_tables" OWNER TO "postgres";


ALTER TABLE "public"."restaurant_tables" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."restaurant_tables_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."settings" (
    "id" integer NOT NULL,
    "key" "text" NOT NULL,
    "value" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" bigint NOT NULL
);


ALTER TABLE "public"."settings" OWNER TO "postgres";


ALTER TABLE "public"."settings" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."settings_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."stock_transfer_items" (
    "id" bigint NOT NULL,
    "transfer_id" bigint NOT NULL,
    "ingredient_id" bigint NOT NULL,
    "quantity" numeric(10,2) NOT NULL
);


ALTER TABLE "public"."stock_transfer_items" OWNER TO "postgres";


ALTER TABLE "public"."stock_transfer_items" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."stock_transfer_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."stock_transfers" (
    "id" bigint NOT NULL,
    "from_location_id" bigint NOT NULL,
    "to_location_id" bigint NOT NULL,
    "request_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completion_date" timestamp with time zone,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "requested_by_id" "uuid",
    "organization_id" bigint NOT NULL,
    CONSTRAINT "stock_transfers_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'completed'::"text", 'canceled'::"text"])))
);


ALTER TABLE "public"."stock_transfers" OWNER TO "postgres";


ALTER TABLE "public"."stock_transfers" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."stock_transfers_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."cashier_sessions"
    ADD CONSTRAINT "cashier_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_phone_number_key" UNIQUE ("phone_number");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_unique_code_key" UNIQUE ("unique_code");



ALTER TABLE ONLY "public"."ingredients"
    ADD CONSTRAINT "ingredients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_ingredient_id_location_id_key" UNIQUE ("ingredient_id", "location_id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."location_products"
    ADD CONSTRAINT "location_products_location_id_product_id_key" UNIQUE ("location_id", "product_id");



ALTER TABLE ONLY "public"."location_products"
    ADD CONSTRAINT "location_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."location_staff"
    ADD CONSTRAINT "location_staff_location_id_staff_id_key" UNIQUE ("location_id", "staff_id");



ALTER TABLE ONLY "public"."location_staff"
    ADD CONSTRAINT "location_staff_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."option_groups"
    ADD CONSTRAINT "option_groups_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."option_values"
    ADD CONSTRAINT "option_values_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_staff"
    ADD CONSTRAINT "organization_staff_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organization_staff"
    ADD CONSTRAINT "organization_staff_user_id_organization_id_key" UNIQUE ("user_id", "organization_id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_options"
    ADD CONSTRAINT "product_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_options"
    ADD CONSTRAINT "product_options_product_id_option_group_id_key" UNIQUE ("product_id", "option_group_id");



ALTER TABLE ONLY "public"."product_recipes"
    ADD CONSTRAINT "product_recipes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_recipes"
    ADD CONSTRAINT "product_recipes_product_id_ingredient_id_key" UNIQUE ("product_id", "ingredient_id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."restaurant_tables"
    ADD CONSTRAINT "restaurant_tables_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."settings"
    ADD CONSTRAINT "settings_org_key_unique" UNIQUE ("organization_id", "key");



ALTER TABLE ONLY "public"."settings"
    ADD CONSTRAINT "settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stock_transfer_items"
    ADD CONSTRAINT "stock_transfer_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stock_transfers"
    ADD CONSTRAINT "stock_transfers_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "idx_customers_member_id_unique" ON "public"."customers" USING "btree" ("member_id") WHERE ("member_id" IS NOT NULL);



CREATE INDEX "idx_customers_org_created_at" ON "public"."customers" USING "btree" ("organization_id", "created_at" DESC);



CREATE INDEX "idx_customers_org_createdat" ON "public"."customers" USING "btree" ("organization_id", "created_at");



CREATE INDEX "idx_locations_org" ON "public"."locations" USING "btree" ("organization_id");



CREATE INDEX "idx_orders_location_created_at" ON "public"."orders" USING "btree" ("location_id", "created_at" DESC);



CREATE INDEX "idx_orders_org_status_createdat" ON "public"."orders" USING "btree" ("status", "created_at") INCLUDE ("location_id");



CREATE INDEX "idx_sti_ingredient_id" ON "public"."stock_transfer_items" USING "btree" ("ingredient_id");



CREATE INDEX "idx_sti_transfer_id" ON "public"."stock_transfer_items" USING "btree" ("transfer_id");



CREATE INDEX "idx_stock_transfers_org_status_request_date" ON "public"."stock_transfers" USING "btree" ("organization_id", "status", "request_date" DESC);



CREATE UNIQUE INDEX "uq_discounts_org_code" ON "public"."discounts" USING "btree" ("organization_id", "unique_code");



CREATE UNIQUE INDEX "uq_location_staff_location_staff" ON "public"."location_staff" USING "btree" ("location_id", "staff_id");



CREATE UNIQUE INDEX "uq_locations_one_main_per_org" ON "public"."locations" USING "btree" ("organization_id") WHERE ("is_main_warehouse" = true);



CREATE UNIQUE INDEX "ux_locations_one_main_per_org" ON "public"."locations" USING "btree" ("organization_id") WHERE ("is_main_warehouse" = true);



CREATE OR REPLACE TRIGGER "set_customers_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."set_customers_updated_at"();



ALTER TABLE ONLY "public"."cashier_sessions"
    ADD CONSTRAINT "cashier_sessions_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."cashier_sessions"
    ADD CONSTRAINT "cashier_sessions_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ingredients"
    ADD CONSTRAINT "ingredients_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_ingredient_id_fkey" FOREIGN KEY ("ingredient_id") REFERENCES "public"."ingredients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."location_products"
    ADD CONSTRAINT "location_products_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."location_products"
    ADD CONSTRAINT "location_products_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."location_staff"
    ADD CONSTRAINT "location_staff_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."location_staff"
    ADD CONSTRAINT "location_staff_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."option_groups"
    ADD CONSTRAINT "option_groups_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."option_values"
    ADD CONSTRAINT "option_values_option_group_id_fkey" FOREIGN KEY ("option_group_id") REFERENCES "public"."option_groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_table_id_fkey" FOREIGN KEY ("table_id") REFERENCES "public"."restaurant_tables"("id");



ALTER TABLE ONLY "public"."organization_staff"
    ADD CONSTRAINT "organization_staff_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organization_staff"
    ADD CONSTRAINT "organization_staff_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."product_options"
    ADD CONSTRAINT "product_options_option_group_id_fkey" FOREIGN KEY ("option_group_id") REFERENCES "public"."option_groups"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_options"
    ADD CONSTRAINT "product_options_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_recipes"
    ADD CONSTRAINT "product_recipes_ingredient_id_fkey" FOREIGN KEY ("ingredient_id") REFERENCES "public"."ingredients"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."product_recipes"
    ADD CONSTRAINT "product_recipes_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."restaurant_tables"
    ADD CONSTRAINT "restaurant_tables_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."stock_transfer_items"
    ADD CONSTRAINT "stock_transfer_items_ingredient_id_fkey" FOREIGN KEY ("ingredient_id") REFERENCES "public"."ingredients"("id");



ALTER TABLE ONLY "public"."stock_transfer_items"
    ADD CONSTRAINT "stock_transfer_items_transfer_id_fkey" FOREIGN KEY ("transfer_id") REFERENCES "public"."stock_transfers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stock_transfers"
    ADD CONSTRAINT "stock_transfers_from_location_id_fkey" FOREIGN KEY ("from_location_id") REFERENCES "public"."locations"("id");



ALTER TABLE ONLY "public"."stock_transfers"
    ADD CONSTRAINT "stock_transfers_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stock_transfers"
    ADD CONSTRAINT "stock_transfers_requested_by_id_fkey" FOREIGN KEY ("requested_by_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."stock_transfers"
    ADD CONSTRAINT "stock_transfers_to_location_id_fkey" FOREIGN KEY ("to_location_id") REFERENCES "public"."locations"("id");



CREATE POLICY "Allow admins to manage location products" ON "public"."location_products" TO "authenticated" USING ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"]))) WITH CHECK ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"])));



CREATE POLICY "Allow admins to manage location staff" ON "public"."location_staff" TO "authenticated" USING ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"]))) WITH CHECK ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"])));



CREATE POLICY "Allow admins to manage recipes" ON "public"."product_recipes" TO "authenticated" USING ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"]))) WITH CHECK ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"])));



CREATE POLICY "Allow admins to manage settings" ON "public"."settings" TO "authenticated" USING ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"]))) WITH CHECK ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"])));



CREATE POLICY "Allow admins to manage tables" ON "public"."restaurant_tables" TO "authenticated" USING ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"]))) WITH CHECK ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"])));



CREATE POLICY "Allow admins to view all sessions" ON "public"."cashier_sessions" FOR SELECT TO "authenticated" USING ((( SELECT "public"."get_user_role"() AS "get_user_role") = ANY (ARRAY['owner'::"text", 'super_admin'::"text"])));



CREATE POLICY "Allow authenticated users to read inventory" ON "public"."inventory" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated users to read option values" ON "public"."option_values" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow authenticated users to read order items" ON "public"."order_items" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow authenticated users to read product option" ON "public"."product_options" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Allow authenticated users to read recipes" ON "public"."product_recipes" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated users to read settings" ON "public"."settings" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated users to read tables" ON "public"."restaurant_tables" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow read access to location assignments" ON "public"."location_products" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow read access to staff assignments" ON "public"."location_staff" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow staff to SELECT their own sessions" ON "public"."cashier_sessions" FOR SELECT TO "authenticated" USING (("staff_id" = "auth"."uid"()));



CREATE POLICY "Allow staff to UPDATE their own open session" ON "public"."cashier_sessions" FOR UPDATE TO "authenticated" USING ((("staff_id" = "auth"."uid"()) AND ("status" = 'open'::"public"."session_status_enum"))) WITH CHECK (("staff_id" = "auth"."uid"()));



CREATE POLICY "FINAL-V2: System admin can view all profiles" ON "public"."profiles" FOR SELECT USING ("public"."is_viewer_role_valid"(ARRAY['system_admin'::"text"]));



CREATE POLICY "FINAL-V2: Users can view profiles as intended" ON "public"."profiles" FOR SELECT USING ((("auth"."uid"() = "id") OR ("public"."is_viewer_role_valid"(ARRAY['system_admin'::"text", 'owner'::"text", 'branch_manager'::"text"]) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "public"."get_current_organization_id"()) AND ("os"."user_id" = "profiles"."id")))))));



CREATE POLICY "System Admins can manage all organizations" ON "public"."organizations" USING (("public"."get_user_role"() = 'system_admin'::"text")) WITH CHECK (("public"."get_user_role"() = 'system_admin'::"text"));



CREATE POLICY "System Admins can manage all staff memberships" ON "public"."organization_staff" USING (("public"."get_user_role"() = 'system_admin'::"text")) WITH CHECK (("public"."get_user_role"() = 'system_admin'::"text"));



CREATE POLICY "Users can manage categories within their own organization" ON "public"."categories" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage customers within their own organization" ON "public"."customers" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage data within their own organization" ON "public"."categories" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."customers" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."discounts" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."ingredients" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."locations" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."option_groups" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."orders" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."products" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage data within their own organization" ON "public"."stock_transfers" USING ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text"))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) OR ("public"."get_user_role"() = 'system_admin'::"text")));



CREATE POLICY "Users can manage discounts within their own organization" ON "public"."discounts" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage ingredients within their own organization" ON "public"."ingredients" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage locations within their own organization" ON "public"."locations" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage option_groups within their own organization" ON "public"."option_groups" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage orders within their own organization" ON "public"."orders" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage products within their own organization" ON "public"."products" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can manage stock_transfers within their own organization" ON "public"."stock_transfers" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "Users can only update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can view organizations they belong to" ON "public"."organizations" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "organizations"."id") AND ("os"."user_id" = "auth"."uid"())))));



CREATE POLICY "Users can view/manage staff within their active organization" ON "public"."organization_staff" USING (("organization_id" = "public"."get_current_organization_id"())) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "View profiles in same organization - FINAL" ON "public"."profiles" FOR SELECT USING ((("public"."get_user_role"() = 'system_admin'::"text") OR (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "viewer_staff",
    "public"."organization_staff" "target_staff"
  WHERE (("viewer_staff"."user_id" = "auth"."uid"()) AND ("target_staff"."user_id" = "profiles"."id") AND ("viewer_staff"."organization_id" = "target_staff"."organization_id"))))));



ALTER TABLE "public"."cashier_sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cashier_sessions_insert_staff" ON "public"."cashier_sessions" FOR INSERT TO "authenticated" WITH CHECK ((("staff_id" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."locations" "l"
  WHERE (("l"."id" = "cashier_sessions"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))) AND (("public"."get_current_role"() = 'owner'::"text") OR (("public"."get_current_role"() = ANY (ARRAY['branch_manager'::"text", 'kasir'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."location_staff" "ls"
  WHERE (("ls"."location_id" = "cashier_sessions"."location_id") AND ("ls"."staff_id" = "auth"."uid"()))))))));



ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."discounts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "discounts_delete_owner" ON "public"."discounts" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = 'owner'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "discounts"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "discounts_insert_owner_bm" ON "public"."discounts" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "public"."get_current_organization_id"()) AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "discounts_select_same_org" ON "public"."discounts" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "discounts"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "discounts_update_owner_bm" ON "public"."discounts" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "discounts"."organization_id") AND ("os"."user_id" = "auth"."uid"())))))) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



ALTER TABLE "public"."ingredients" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ingredients_delete_owner" ON "public"."ingredients" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = 'owner'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "ingredients"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "ingredients_insert_owner_wh" ON "public"."ingredients" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "public"."get_current_organization_id"()) AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "ingredients_select_owner_wh" ON "public"."ingredients" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "ingredients"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "ingredients_update_owner_wh" ON "public"."ingredients" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "ingredients"."organization_id") AND ("os"."user_id" = "auth"."uid"())))))) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



ALTER TABLE "public"."inventory" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_mutate_by_role" ON "public"."inventory" TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "inventory"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))) AND (("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) OR (("public"."get_current_role"() = 'branch_manager'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."location_staff" "ls2"
  WHERE (("ls2"."location_id" = "inventory"."location_id") AND ("ls2"."staff_id" = "auth"."uid"())))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "inventory"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



CREATE POLICY "inventory_select_same_org" ON "public"."inventory" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "inventory"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."location_products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "location_products_mutate_by_role" ON "public"."location_products" TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_products"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))) AND (("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) OR (("public"."get_current_role"() = 'branch_manager'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."location_staff" "ls2"
  WHERE (("ls2"."location_id" = "location_products"."location_id") AND ("ls2"."staff_id" = "auth"."uid"())))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_products"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



CREATE POLICY "location_products_select_same_org" ON "public"."location_products" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_products"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."location_staff" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "location_staff_delete_by_admins" ON "public"."location_staff" FOR DELETE TO "authenticated" USING ((("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_staff"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"()))))));



CREATE POLICY "location_staff_insert_by_admins" ON "public"."location_staff" FOR INSERT TO "authenticated" WITH CHECK ((("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_staff"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"()))))));



CREATE POLICY "location_staff_select_same_org" ON "public"."location_staff" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_staff"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



CREATE POLICY "location_staff_update_by_admins" ON "public"."location_staff" FOR UPDATE TO "authenticated" USING ((("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_staff"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "location_staff"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."locations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "locations_delete_owner" ON "public"."locations" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = 'owner'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "locations"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "locations_insert_owner" ON "public"."locations" FOR INSERT TO "authenticated" WITH CHECK ((("public"."get_current_role"() = 'owner'::"text") AND ("organization_id" = "public"."get_current_organization_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "public"."get_current_organization_id"()) AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "locations_mutate_owner" ON "public"."locations" TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = 'owner'::"text"))) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "locations_select_same_org" ON "public"."locations" FOR SELECT TO "authenticated" USING (("organization_id" = "public"."get_current_organization_id"()));



CREATE POLICY "locations_update_owner_or_branch_manager" ON "public"."locations" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "locations"."organization_id") AND ("os"."user_id" = "auth"."uid"())))) AND (("public"."get_current_role"() = 'owner'::"text") OR (("public"."get_current_role"() = 'branch_manager'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."location_staff" "ls"
  WHERE (("ls"."location_id" = "locations"."id") AND ("ls"."staff_id" = "auth"."uid"())))))))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "locations"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



ALTER TABLE "public"."option_groups" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "option_groups_delete_owner" ON "public"."option_groups" FOR DELETE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = 'owner'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "option_groups"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "option_groups_insert_by_owner_or_bm" ON "public"."option_groups" FOR INSERT TO "authenticated" WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "public"."get_current_organization_id"()) AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "option_groups_select_same_org" ON "public"."option_groups" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "option_groups"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



CREATE POLICY "option_groups_update_by_owner_or_bm" ON "public"."option_groups" FOR UPDATE TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "option_groups"."organization_id") AND ("os"."user_id" = "auth"."uid"())))))) WITH CHECK (("organization_id" = "public"."get_current_organization_id"()));



ALTER TABLE "public"."option_values" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "option_values_delete_owner_v2" ON "public"."option_values" FOR DELETE TO "authenticated" USING ((("public"."get_current_role"() = 'owner'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."option_groups" "og"
  WHERE (("og"."id" = "option_values"."option_group_id") AND ("og"."organization_id" = "public"."get_current_organization_id"()))))));



CREATE POLICY "option_values_insert_owner_bm_v2" ON "public"."option_values" FOR INSERT TO "authenticated" WITH CHECK ((("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."option_groups" "og"
  WHERE (("og"."id" = "option_values"."option_group_id") AND ("og"."organization_id" = "public"."get_current_organization_id"()))))));



CREATE POLICY "option_values_select_v2" ON "public"."option_values" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."option_groups" "og"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "og"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("og"."id" = "option_values"."option_group_id") AND ("og"."organization_id" = "public"."get_current_organization_id"())))));



CREATE POLICY "option_values_update_owner_bm_v2" ON "public"."option_values" FOR UPDATE TO "authenticated" USING ((("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."option_groups" "og"
  WHERE (("og"."id" = "option_values"."option_group_id") AND ("og"."organization_id" = "public"."get_current_organization_id"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."option_groups" "og"
  WHERE (("og"."id" = "option_values"."option_group_id") AND ("og"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "order_items_select_same_org" ON "public"."order_items" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM (("public"."orders" "o"
     JOIN "public"."locations" "l" ON (("l"."id" = "o"."location_id")))
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("o"."id" = "order_items"."order_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orders_select_same_org" ON "public"."orders" FOR SELECT TO "authenticated" USING ((("organization_id" = "public"."get_current_organization_id"()) AND (EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "orders"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))));



ALTER TABLE "public"."organization_staff" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_options" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_options_mutate_by_role" ON "public"."product_options" TO "authenticated" USING (((("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."products" "p"
  WHERE (("p"."id" = "product_options"."product_id") AND ("p"."organization_id" = "public"."get_current_organization_id"()))))) OR (("public"."get_current_role"() = 'branch_manager'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."location_products" "lp"
  WHERE (("lp"."product_id" = "product_options"."product_id") AND (EXISTS ( SELECT 1
           FROM "public"."location_staff" "ls"
          WHERE (("ls"."location_id" = "lp"."location_id") AND ("ls"."staff_id" = "auth"."uid"())))))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."products" "p"
  WHERE (("p"."id" = "product_options"."product_id") AND ("p"."organization_id" = "public"."get_current_organization_id"())))));



CREATE POLICY "product_options_select_same_org" ON "public"."product_options" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."products" "p"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "p"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("p"."id" = "product_options"."product_id") AND ("p"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."product_recipes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "product_recipes_mutate_by_role" ON "public"."product_recipes" TO "authenticated" USING ((("public"."get_current_role"() = ANY (ARRAY['owner'::"text", 'super_admin_warehouse'::"text"])) AND (EXISTS ( SELECT 1
   FROM "public"."products" "p"
  WHERE (("p"."id" = "product_recipes"."product_id") AND ("p"."organization_id" = "public"."get_current_organization_id"())))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."products" "p"
  WHERE (("p"."id" = "product_recipes"."product_id") AND ("p"."organization_id" = "public"."get_current_organization_id"())))));



CREATE POLICY "product_recipes_select_same_org" ON "public"."product_recipes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."products" "p"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "p"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("p"."id" = "product_recipes"."product_id") AND ("p"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."restaurant_tables" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "restaurant_tables_mutate_by_role" ON "public"."restaurant_tables" TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "restaurant_tables"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))) AND (("public"."get_current_role"() = 'owner'::"text") OR (("public"."get_current_role"() = 'branch_manager'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."location_staff" "ls2"
  WHERE (("ls2"."location_id" = "restaurant_tables"."location_id") AND ("ls2"."staff_id" = "auth"."uid"())))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "restaurant_tables"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



CREATE POLICY "restaurant_tables_select_same_org" ON "public"."restaurant_tables" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."locations" "l"
     JOIN "public"."organization_staff" "os" ON ((("os"."organization_id" = "l"."organization_id") AND ("os"."user_id" = "auth"."uid"()))))
  WHERE (("l"."id" = "restaurant_tables"."location_id") AND ("l"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."settings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "settings_insert_by_role" ON "public"."settings" FOR INSERT WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_user_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"]))));



CREATE POLICY "settings_select_by_org" ON "public"."settings" FOR SELECT USING ((("organization_id" = "public"."get_current_organization_id"()) AND ((EXISTS ( SELECT 1
   FROM "public"."organization_staff" "os"
  WHERE (("os"."organization_id" = "public"."get_current_organization_id"()) AND ("os"."user_id" = "auth"."uid"())))) OR (EXISTS ( SELECT 1
   FROM "public"."organizations" "o"
  WHERE (("o"."id" = "public"."get_current_organization_id"()) AND ("o"."owner_id" = "auth"."uid"())))))));



CREATE POLICY "settings_update_by_role" ON "public"."settings" FOR UPDATE USING ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_user_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"])))) WITH CHECK ((("organization_id" = "public"."get_current_organization_id"()) AND ("public"."get_user_role"() = ANY (ARRAY['owner'::"text", 'branch_manager'::"text"]))));



ALTER TABLE "public"."stock_transfer_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_transfer_items_select_same_org" ON "public"."stock_transfer_items" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."stock_transfers" "t"
  WHERE (("t"."id" = "stock_transfer_items"."transfer_id") AND ("t"."organization_id" = "public"."get_current_organization_id"())))));



ALTER TABLE "public"."stock_transfers" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."adjust_inventory_stock"("p_location_id" bigint, "p_ingredient_id" bigint, "p_adjustment_quantity" numeric, "p_is_addition" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."adjust_inventory_stock"("p_location_id" bigint, "p_ingredient_id" bigint, "p_adjustment_quantity" numeric, "p_is_addition" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."adjust_inventory_stock"("p_location_id" bigint, "p_ingredient_id" bigint, "p_adjustment_quantity" numeric, "p_is_addition" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_create_organization"("p_name" "text", "p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_create_organization"("p_name" "text", "p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_create_organization"("p_name" "text", "p_owner_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."approve_stock_transfer_v2"("p_transfer_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."approve_stock_transfer_v2"("p_transfer_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_stock_transfer_v2"("p_transfer_id" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."assign_staff_to_location_v2"("p_location_id" bigint, "p_staff_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_staff_to_location_v2"("p_location_id" bigint, "p_staff_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."assign_staff_to_location_v2"("p_location_id" bigint, "p_staff_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_staff_to_location_v2"("p_location_id" bigint, "p_staff_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_staff_to_locations"("p_staff_id" "uuid", "p_location_ids" bigint[]) TO "anon";
GRANT ALL ON FUNCTION "public"."assign_staff_to_locations"("p_staff_id" "uuid", "p_location_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_staff_to_locations"("p_staff_id" "uuid", "p_location_ids" bigint[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."assign_staff_to_locations_v2"("p_staff_id" "uuid", "p_location_ids" bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."assign_staff_to_locations_v2"("p_staff_id" "uuid", "p_location_ids" bigint[]) TO "anon";
GRANT ALL ON FUNCTION "public"."assign_staff_to_locations_v2"("p_staff_id" "uuid", "p_location_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_staff_to_locations_v2"("p_staff_id" "uuid", "p_location_ids" bigint[]) TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_upsert_customer_by_phone"("p_phone" "text", "p_member_id" "uuid", "p_full_name" "text", "p_location_id" bigint, "p_preference" "text", "p_interests" "text"[], "p_gallery_images" "text"[], "p_profile_image_url" "text", "p_date_of_birth" "date", "p_gender" "text", "p_visibility" boolean, "p_search_radius_km" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."auth_upsert_customer_by_phone"("p_phone" "text", "p_member_id" "uuid", "p_full_name" "text", "p_location_id" bigint, "p_preference" "text", "p_interests" "text"[], "p_gallery_images" "text"[], "p_profile_image_url" "text", "p_date_of_birth" "date", "p_gender" "text", "p_visibility" boolean, "p_search_radius_km" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_upsert_customer_by_phone"("p_phone" "text", "p_member_id" "uuid", "p_full_name" "text", "p_location_id" bigint, "p_preference" "text", "p_interests" "text"[], "p_gallery_images" "text"[], "p_profile_image_url" "text", "p_date_of_birth" "date", "p_gender" "text", "p_visibility" boolean, "p_search_radius_km" numeric, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_hpp"("p_product_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_hpp"("p_product_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_hpp"("p_product_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_single_product_stock"("p_product_id" bigint, "p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_single_product_stock"("p_product_id" bigint, "p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_single_product_stock"("p_product_id" bigint, "p_location_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."cancel_stock_transfer_v2"("p_transfer_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_stock_transfer_v2"("p_transfer_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_stock_transfer_v2"("p_transfer_id" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."clone_products_with_options_recipes_v1"("p_src_location_id" bigint, "p_target_location_ids" bigint[], "p_reset_stock_to_zero" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."clone_products_with_options_recipes_v1"("p_src_location_id" bigint, "p_target_location_ids" bigint[], "p_reset_stock_to_zero" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."clone_products_with_options_recipes_v1"("p_src_location_id" bigint, "p_target_location_ids" bigint[], "p_reset_stock_to_zero" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."clone_products_with_options_recipes_v1"("p_src_location_id" bigint, "p_target_location_ids" bigint[], "p_reset_stock_to_zero" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_category_v2"("p_name" "text", "p_description" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_category_v2"("p_name" "text", "p_description" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_category_v2"("p_name" "text", "p_description" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_category_v2"("p_name" "text", "p_description" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_new_order"("p_payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_new_order"("p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_new_order"("p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_new_order_v2"("p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_new_order_v2"("p_payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_new_order_v2"("p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_new_order_v2"("p_payload" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_organization_and_link_owner"("p_organization_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_organization_and_link_owner"("p_organization_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization_and_link_owner"("p_organization_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_product_with_location"("p_location_id" bigint, "p_name" "text", "p_description" "text", "p_price" numeric, "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."create_product_with_location"("p_location_id" bigint, "p_name" "text", "p_description" "text", "p_price" numeric, "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_product_with_location"("p_location_id" bigint, "p_name" "text", "p_description" "text", "p_price" numeric, "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_product_with_location_v2"("p_location_id" bigint, "p_name" "text", "p_price" numeric, "p_description" "text", "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_product_with_location_v2"("p_location_id" bigint, "p_name" "text", "p_price" numeric, "p_description" "text", "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."create_product_with_location_v2"("p_location_id" bigint, "p_name" "text", "p_price" numeric, "p_description" "text", "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_product_with_location_v2"("p_location_id" bigint, "p_name" "text", "p_price" numeric, "p_description" "text", "p_unit" "text", "p_category_id" bigint, "p_image_url" "text", "p_stock" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_user_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_user_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_user_profile"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_ingredients_from_order"("p_order_id" bigint, "p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_ingredients_from_order"("p_order_id" bigint, "p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_ingredients_from_order"("p_order_id" bigint, "p_location_id" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."decrement_inventory_for_product_v2"("p_location_id" bigint, "p_product_id" bigint, "p_qty" numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."decrement_inventory_for_product_v2"("p_location_id" bigint, "p_product_id" bigint, "p_qty" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_inventory_for_product_v2"("p_location_id" bigint, "p_product_id" bigint, "p_qty" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_inventory_for_product_v2"("p_location_id" bigint, "p_product_id" bigint, "p_qty" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_organization"("p_org_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."delete_organization"("p_org_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_organization"("p_org_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_location_in_current_org"("p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_location_in_current_org"("p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_location_in_current_org"("p_location_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_membership_in_active_org"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_membership_in_active_org"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_membership_in_active_org"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_all_organizations"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_all_organizations"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_all_organizations"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_assigned_locations_with_details"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_assigned_locations_with_details"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_assigned_locations_with_details"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_assigned_locations_with_details_v2"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_assigned_locations_with_details_v2"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_assigned_locations_with_details_v2"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_assigned_locations_with_details_v2"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_current_organization_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_organization_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_organization_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_current_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_detail_by_member_id"("p_member_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_detail_by_member_id"("p_member_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_detail_by_member_id"("p_member_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_daily_sales_revenue"("days_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_daily_sales_revenue"("days_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_sales_revenue"("days_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_daily_sales_revenue_v2"("days_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_daily_sales_revenue_v2"("days_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_sales_revenue_v2"("days_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dashboard_cards_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_dashboard_cards_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dashboard_cards_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dashboard_cards_data_v2"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_dashboard_cards_data_v2"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dashboard_cards_data_v2"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ingredient_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_ingredient_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_ingredient_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_inventory_by_location"("p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_inventory_by_location"("p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_inventory_by_location"("p_location_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_inventory_report"("p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_inventory_report"("p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_inventory_report"("p_location_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_main_warehouse_location_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_main_warehouse_location_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_main_warehouse_location_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_main_warehouse_v1"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_main_warehouse_v1"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_main_warehouse_v1"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_order_list"("p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_order_list"("p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_order_list"("p_location_id" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_order_list_v2"("p_location_id" bigint, "p_limit" integer, "p_offset" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_order_list_v2"("p_location_id" bigint, "p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_order_list_v2"("p_location_id" bigint, "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_order_list_v2"("p_location_id" bigint, "p_limit" integer, "p_offset" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_paginated_cashier_sessions_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_paginated_cashier_sessions_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_paginated_cashier_sessions_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_paginated_stock_transfers_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "status_filter" "text", "page_num" integer, "page_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_paginated_stock_transfers_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "status_filter" "text", "page_num" integer, "page_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_paginated_stock_transfers_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "status_filter" "text", "page_num" integer, "page_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_paginated_transaction_list"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_paginated_transaction_list"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_paginated_transaction_list"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_paginated_transaction_list_v2"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_paginated_transaction_list_v2"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_paginated_transaction_list_v2"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "search_query" "text", "page_num" integer, "page_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_potential_owners"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_potential_owners"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_potential_owners"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_product_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_product_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_product_total_stock_overview_v1"("search_query" "text", "page_num" integer, "page_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_products_with_details"("p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_products_with_details"("p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_products_with_details"("p_location_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_settings_for_active_org"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_settings_for_active_org"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_settings_for_active_org"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transaction_report_data"("start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_transaction_report_data"("start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transaction_report_data"("start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transaction_summary"("start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_transaction_summary"("start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transaction_summary"("start_date" timestamp with time zone, "end_date" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_organizations"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_organizations"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_organizations"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_warehouse_bi_overview_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "top_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_warehouse_bi_overview_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "top_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_warehouse_bi_overview_v1"("start_date" timestamp with time zone, "end_date" timestamp with time zone, "top_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."is_viewer_role_valid"("roles_to_check" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."is_viewer_role_valid"("roles_to_check" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_viewer_role_valid"("roles_to_check" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."request_stock_transfer_v2"("p_from_location_id" bigint, "p_to_location_id" bigint, "p_items" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."request_stock_transfer_v2"("p_from_location_id" bigint, "p_to_location_id" bigint, "p_items" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_stock_transfer_v2"("p_from_location_id" bigint, "p_to_location_id" bigint, "p_items" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_customers_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_customers_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_customers_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_main_warehouse_v1"("p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."set_main_warehouse_v1"("p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_main_warehouse_v1"("p_location_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_product_recipe_v1"("p_product_id" bigint, "p_items" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."set_product_recipe_v1"("p_product_id" bigint, "p_items" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_product_recipe_v1"("p_product_id" bigint, "p_items" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_all_product_stocks_by_location"("p_location_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."sync_all_product_stocks_by_location"("p_location_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_all_product_stocks_by_location"("p_location_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_product_options"("p_product_id" bigint, "p_option_group_ids" bigint[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sync_product_options"("p_product_id" bigint, "p_option_group_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_product_options"("p_product_id" bigint, "p_option_group_ids" bigint[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_order_status"("p_order_id" bigint, "p_new_status" "public"."order_status_enum") TO "anon";
GRANT ALL ON FUNCTION "public"."update_order_status"("p_order_id" bigint, "p_new_status" "public"."order_status_enum") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_order_status"("p_order_id" bigint, "p_new_status" "public"."order_status_enum") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_product_stock"("p_product_id" bigint, "p_new_stock" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."update_product_stock"("p_product_id" bigint, "p_new_stock" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_product_stock"("p_product_id" bigint, "p_new_stock" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_product_stock_manual_v1"("p_product_id" bigint, "p_new_stock" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."update_product_stock_manual_v1"("p_product_id" bigint, "p_new_stock" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_product_stock_manual_v1"("p_product_id" bigint, "p_new_stock" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_staff_role"("p_staff_id" "uuid", "p_new_role" "public"."user_role") TO "anon";
GRANT ALL ON FUNCTION "public"."update_staff_role"("p_staff_id" "uuid", "p_new_role" "public"."user_role") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_staff_role"("p_staff_id" "uuid", "p_new_role" "public"."user_role") TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_staff_role_v2"("p_staff_id" "uuid", "p_new_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_staff_role_v2"("p_staff_id" "uuid", "p_new_role" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_staff_role_v2"("p_staff_id" "uuid", "p_new_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_staff_role_v2"("p_staff_id" "uuid", "p_new_role" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."upsert_setting_for_active_org"("p_key" "text", "p_value" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."upsert_setting_for_active_org"("p_key" "text", "p_value" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_setting_for_active_org"("p_key" "text", "p_value" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_setting_for_active_org"("p_key" "text", "p_value" "text") TO "service_role";



GRANT ALL ON TABLE "public"."cashier_sessions" TO "anon";
GRANT ALL ON TABLE "public"."cashier_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."cashier_sessions" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cashier_sessions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cashier_sessions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cashier_sessions_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."categories" TO "anon";
GRANT ALL ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON SEQUENCE "public"."categories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."categories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."categories_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."customers_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."customers_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."customers_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."discounts" TO "anon";
GRANT ALL ON TABLE "public"."discounts" TO "authenticated";
GRANT ALL ON TABLE "public"."discounts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."discounts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."discounts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."discounts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."ingredients" TO "anon";
GRANT ALL ON TABLE "public"."ingredients" TO "authenticated";
GRANT ALL ON TABLE "public"."ingredients" TO "service_role";



GRANT ALL ON SEQUENCE "public"."ingredients_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."ingredients_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."ingredients_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."inventory" TO "anon";
GRANT ALL ON TABLE "public"."inventory" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory" TO "service_role";



GRANT ALL ON SEQUENCE "public"."inventory_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."inventory_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."inventory_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."location_products" TO "anon";
GRANT ALL ON TABLE "public"."location_products" TO "authenticated";
GRANT ALL ON TABLE "public"."location_products" TO "service_role";



GRANT ALL ON SEQUENCE "public"."location_products_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."location_products_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."location_products_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."location_staff" TO "anon";
GRANT ALL ON TABLE "public"."location_staff" TO "authenticated";
GRANT ALL ON TABLE "public"."location_staff" TO "service_role";



GRANT ALL ON SEQUENCE "public"."location_staff_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."location_staff_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."location_staff_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."locations" TO "anon";
GRANT ALL ON TABLE "public"."locations" TO "authenticated";
GRANT ALL ON TABLE "public"."locations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."locations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."locations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."locations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."option_groups" TO "anon";
GRANT ALL ON TABLE "public"."option_groups" TO "authenticated";
GRANT ALL ON TABLE "public"."option_groups" TO "service_role";



GRANT ALL ON SEQUENCE "public"."option_groups_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."option_groups_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."option_groups_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."option_values" TO "anon";
GRANT ALL ON TABLE "public"."option_values" TO "authenticated";
GRANT ALL ON TABLE "public"."option_values" TO "service_role";



GRANT ALL ON SEQUENCE "public"."option_values_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."option_values_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."option_values_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."order_items_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."order_items_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."order_items_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON SEQUENCE "public"."orders_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."orders_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."orders_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."organization_staff" TO "anon";
GRANT ALL ON TABLE "public"."organization_staff" TO "authenticated";
GRANT ALL ON TABLE "public"."organization_staff" TO "service_role";



GRANT ALL ON SEQUENCE "public"."organization_staff_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."organization_staff_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."organization_staff_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT ALL ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."organizations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."organizations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."organizations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."product_options" TO "anon";
GRANT ALL ON TABLE "public"."product_options" TO "authenticated";
GRANT ALL ON TABLE "public"."product_options" TO "service_role";



GRANT ALL ON SEQUENCE "public"."product_options_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."product_options_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."product_options_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."product_recipes" TO "anon";
GRANT ALL ON TABLE "public"."product_recipes" TO "authenticated";
GRANT ALL ON TABLE "public"."product_recipes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."product_recipes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."product_recipes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."product_recipes_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."restaurant_tables" TO "anon";
GRANT ALL ON TABLE "public"."restaurant_tables" TO "authenticated";
GRANT ALL ON TABLE "public"."restaurant_tables" TO "service_role";



GRANT ALL ON SEQUENCE "public"."restaurant_tables_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."restaurant_tables_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."restaurant_tables_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."settings" TO "anon";
GRANT ALL ON TABLE "public"."settings" TO "authenticated";
GRANT ALL ON TABLE "public"."settings" TO "service_role";



GRANT ALL ON SEQUENCE "public"."settings_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."settings_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."settings_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."stock_transfer_items" TO "anon";
GRANT ALL ON TABLE "public"."stock_transfer_items" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_transfer_items" TO "service_role";



GRANT ALL ON SEQUENCE "public"."stock_transfer_items_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."stock_transfer_items_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."stock_transfer_items_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."stock_transfers" TO "anon";
GRANT ALL ON TABLE "public"."stock_transfers" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_transfers" TO "service_role";



GRANT ALL ON SEQUENCE "public"."stock_transfers_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."stock_transfers_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."stock_transfers_id_seq" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






RESET ALL;
