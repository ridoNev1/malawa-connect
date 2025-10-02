-- Storage buckets for member profile images and gallery (Org 5)
-- Creates public buckets 'memberavatars' and 'membergallery' with RLS policies
-- to allow authenticated users to manage files under path prefix 'org5/<uid>/*'.

-- Create bucket if not exists (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'memberavatars'
  ) THEN
    PERFORM storage.create_bucket(
      id => 'memberavatars',
      name => 'memberavatars',
      public => true
    );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'membergallery'
  ) THEN
    PERFORM storage.create_bucket(
      id => 'membergallery',
      name => 'membergallery',
      public => true
    );
  END IF;
END $$;

-- RLS policies on storage.objects (memberavatars)
DROP POLICY IF EXISTS "memberavatars_insert_own_org5" ON storage.objects;
CREATE POLICY "memberavatars_insert_own_org5"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'memberavatars'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
);

DROP POLICY IF EXISTS "memberavatars_update_own_org5" ON storage.objects;
CREATE POLICY "memberavatars_update_own_org5"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'memberavatars'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
)
WITH CHECK (
  bucket_id = 'memberavatars'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
);

DROP POLICY IF EXISTS "memberavatars_delete_own_org5" ON storage.objects;
CREATE POLICY "memberavatars_delete_own_org5"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'memberavatars'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
);

DROP POLICY IF EXISTS "memberavatars_select_any_authenticated" ON storage.objects;
CREATE POLICY "memberavatars_select_any_authenticated"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'memberavatars');

-- RLS policies on storage.objects (membergallery)
DROP POLICY IF EXISTS "membergallery_insert_own_org5" ON storage.objects;
CREATE POLICY "membergallery_insert_own_org5"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'membergallery'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
);

DROP POLICY IF EXISTS "membergallery_update_own_org5" ON storage.objects;
CREATE POLICY "membergallery_update_own_org5"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'membergallery'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
)
WITH CHECK (
  bucket_id = 'membergallery'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
);

DROP POLICY IF EXISTS "membergallery_delete_own_org5" ON storage.objects;
CREATE POLICY "membergallery_delete_own_org5"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'membergallery'
  AND position(('org5/' || auth.uid() || '/') in name) = 1
);

DROP POLICY IF EXISTS "membergallery_select_any_authenticated" ON storage.objects;
CREATE POLICY "membergallery_select_any_authenticated"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'membergallery');
