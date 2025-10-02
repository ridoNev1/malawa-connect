-- Chat (Org 5) with DB-side Realtime Broadcasts (no replication)
-- Tables, RLS, RPCs and supabase_realtime.broadcast integration

-- 0) Extensions (idempotent) — no DB realtime extension required
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1) Tables (idempotent-ish)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='chat_rooms'
  ) THEN
    CREATE TABLE public.chat_rooms (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      is_group boolean NOT NULL DEFAULT false,
      last_message_text text,
      last_message_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='chat_participants'
  ) THEN
    CREATE TABLE public.chat_participants (
      chat_id uuid NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
      user_id uuid NOT NULL,
      unread_count int NOT NULL DEFAULT 0,
      archived boolean NOT NULL DEFAULT false,
      PRIMARY KEY (chat_id, user_id)
    );
    CREATE INDEX IF NOT EXISTS idx_chat_participants_user ON public.chat_participants(user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='chat_messages'
  ) THEN
    CREATE TABLE public.chat_messages (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      chat_id uuid NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
      sender_id uuid NOT NULL,
      text text,
      is_image boolean NOT NULL DEFAULT false,
      image_url text,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS idx_chat_messages_room_created ON public.chat_messages(chat_id, created_at DESC);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='chat_read_state'
  ) THEN
    CREATE TABLE public.chat_read_state (
      chat_id uuid NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
      user_id uuid NOT NULL,
      last_read_at timestamptz,
      last_read_message_id uuid,
      PRIMARY KEY (chat_id, user_id)
    );
  END IF;
END $$;

-- 2) RLS Policies
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_read_state ENABLE ROW LEVEL SECURITY;

-- Helper: is participant
CREATE OR REPLACE FUNCTION public.is_chat_participant(p_chat_id uuid, p_user uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_participants cp
    WHERE cp.chat_id = p_chat_id AND cp.user_id = p_user
  );
$$;

-- chat_rooms select: only if participant
DROP POLICY IF EXISTS chat_rooms_select_participant ON public.chat_rooms;
CREATE POLICY chat_rooms_select_participant ON public.chat_rooms
FOR SELECT TO authenticated
USING (public.is_chat_participant(id));

-- chat_participants: select own rows; update only own row
DROP POLICY IF EXISTS chat_participants_select_own ON public.chat_participants;
CREATE POLICY chat_participants_select_own ON public.chat_participants
FOR SELECT TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS chat_participants_update_own ON public.chat_participants;
CREATE POLICY chat_participants_update_own ON public.chat_participants
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- chat_messages: select if participant; insert if participant
DROP POLICY IF EXISTS chat_messages_select ON public.chat_messages;
CREATE POLICY chat_messages_select ON public.chat_messages
FOR SELECT TO authenticated
USING (public.is_chat_participant(chat_id));

DROP POLICY IF EXISTS chat_messages_insert ON public.chat_messages;
CREATE POLICY chat_messages_insert ON public.chat_messages
FOR INSERT TO authenticated
WITH CHECK (public.is_chat_participant(chat_id) AND sender_id = auth.uid());

-- chat_read_state: select/upsert own
DROP POLICY IF EXISTS chat_read_state_select_own ON public.chat_read_state;
CREATE POLICY chat_read_state_select_own ON public.chat_read_state
FOR SELECT TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS chat_read_state_upsert_own ON public.chat_read_state;
CREATE POLICY chat_read_state_upsert_own ON public.chat_read_state
FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS chat_read_state_update_own ON public.chat_read_state;
CREATE POLICY chat_read_state_update_own ON public.chat_read_state
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 3) Storage bucket for chat images (optional, idempotent)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'chatimages') THEN
    INSERT INTO storage.buckets (id, name, public) VALUES ('chatimages', 'chatimages', false);
  END IF;
END $$;

-- Helper: extract chat_id from storage.objects.name path 'org5/<chat_id>/...'
CREATE OR REPLACE FUNCTION public.chat_image_chat_id(p_name text)
RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT NULLIF(split_part(p_name, '/', 2), '')::uuid;
$$;

-- Read policy: allow if user participates in chat_id from path
DROP POLICY IF EXISTS chatimages_read_participant ON storage.objects;
CREATE POLICY chatimages_read_participant ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'chatimages'
  AND split_part(name, '/', 1) = 'org5'
  AND public.is_chat_participant(public.chat_image_chat_id(name))
);

-- Write policy: allow insert under own rooms only (participant)
DROP POLICY IF EXISTS chatimages_insert_participant ON storage.objects;
CREATE POLICY chatimages_insert_participant ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'chatimages'
  AND split_part(name, '/', 1) = 'org5'
  AND public.is_chat_participant(public.chat_image_chat_id(name))
);

-- 4) RPCs (Org 5) with DB-side broadcast

-- get_or_create_direct_chat_org5(peer)
CREATE OR REPLACE FUNCTION public.get_or_create_direct_chat_org5(p_peer_id uuid)
RETURNS public.chat_rooms
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_room public.chat_rooms%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  IF p_peer_id IS NULL OR p_peer_id = v_uid THEN RAISE EXCEPTION 'Invalid peer'; END IF;

  -- Ensure both users exist in customers org 5
  PERFORM 1 FROM public.customers c WHERE c.member_id = v_uid AND c.organization_id = 5;
  IF NOT FOUND THEN RAISE EXCEPTION 'Current user not in org 5'; END IF;
  PERFORM 1 FROM public.customers c WHERE c.member_id = p_peer_id AND c.organization_id = 5;
  IF NOT FOUND THEN RAISE EXCEPTION 'Peer not in org 5'; END IF;

  -- Find existing 1:1 room (exactly two participants)
  SELECT cr.* INTO v_room
  FROM public.chat_rooms cr
  WHERE cr.is_group = false AND EXISTS (
    SELECT 1 FROM public.chat_participants cp1
    JOIN public.chat_participants cp2 ON cp2.chat_id = cp1.chat_id
    WHERE cp1.chat_id = cr.id
      AND cp1.user_id = v_uid
      AND cp2.user_id = p_peer_id
  )
  LIMIT 1;

  IF FOUND THEN
    RETURN v_room;
  END IF;

  INSERT INTO public.chat_rooms(is_group) VALUES(false) RETURNING * INTO v_room;
  INSERT INTO public.chat_participants(chat_id, user_id) VALUES (v_room.id, v_uid);
  INSERT INTO public.chat_participants(chat_id, user_id) VALUES (v_room.id, p_peer_id);
  RETURN v_room;
END; $$;

GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat_org5(uuid) TO authenticated, service_role;

-- get_chat_list_org5
CREATE OR REPLACE FUNCTION public.get_chat_list_org5(
  p_search text DEFAULT '', p_limit int DEFAULT 20, p_offset int DEFAULT 0
) RETURNS TABLE(
  id uuid,
  name text,
  avatar text,
  lastMessage text,
  lastMessageTime timestamptz,
  unreadCount int,
  isOnline boolean
) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH my_rooms AS (
    SELECT cp.chat_id, cp.unread_count
    FROM public.chat_participants cp
    WHERE cp.user_id = auth.uid()
  ), peers AS (
    SELECT mr.chat_id,
           CASE WHEN cr.is_group THEN NULL ELSE (
             SELECT cp2.user_id FROM public.chat_participants cp2
             WHERE cp2.chat_id = mr.chat_id AND cp2.user_id <> auth.uid() LIMIT 1
           ) END AS peer_id,
           mr.unread_count
    FROM my_rooms mr
    JOIN public.chat_rooms cr ON cr.id = mr.chat_id
  ), peer_profiles AS (
    SELECT p.peer_id,
           c.full_name AS name,
           c.profile_image_url AS avatar
    FROM peers p
    LEFT JOIN public.customers c ON c.member_id = p.peer_id AND c.organization_id = 5
  ), presence AS (
    SELECT up.user_id,
           (up.last_heartbeat_at >= now() - interval '120 seconds') AS online
    FROM public.user_presence up
    WHERE up.check_out_at IS NULL
  )
  SELECT cr.id,
         COALESCE(pp.name, 'Unknown') AS name,
         pp.avatar,
         cr.last_message_text AS "lastMessage",
         cr.last_message_at  AS "lastMessageTime",
         COALESCE(peers.unread_count, 0) AS "unreadCount",
         COALESCE(pr.online, false) AS "isOnline"
  FROM peers
  JOIN public.chat_rooms cr ON cr.id = peers.chat_id
  LEFT JOIN peer_profiles pp ON pp.peer_id = peers.peer_id
  LEFT JOIN presence pr ON pr.user_id = peers.peer_id
  WHERE (COALESCE(p_search, '') = '' OR COALESCE(pp.name,'') ILIKE '%'||p_search||'%')
  ORDER BY cr.last_message_at DESC NULLS LAST, cr.created_at DESC
  LIMIT GREATEST(COALESCE(p_limit,20),1) OFFSET GREATEST(COALESCE(p_offset,0),0);
$$;

GRANT EXECUTE ON FUNCTION public.get_chat_list_org5(text, int, int) TO authenticated, service_role;

-- get_room_header_org5
CREATE OR REPLACE FUNCTION public.get_room_header_org5(p_chat_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH peer AS (
    SELECT cp2.user_id AS peer_id
    FROM public.chat_participants cp2
    WHERE cp2.chat_id = p_chat_id AND cp2.user_id <> auth.uid()
    LIMIT 1
  ), prof AS (
    SELECT c.member_id, c.full_name AS name, c.profile_image_url AS avatar
    FROM public.customers c
    JOIN peer ON peer.peer_id = c.member_id AND c.organization_id = 5
  ), pres AS (
    SELECT up.user_id, up.last_heartbeat_at, up.check_in_at
    FROM public.user_presence up
    WHERE up.check_out_at IS NULL
  )
  SELECT to_jsonb(x) FROM (
    SELECT p_chat_id AS id,
           COALESCE(prof.name,'Unknown') AS name,
           prof.avatar,
           (peer.peer_id)::uuid AS peer_id,
           (pres.user_id IS NOT NULL AND pres.last_heartbeat_at >= now() - interval '120 seconds') AS "isOnline",
           to_char(GREATEST(COALESCE(pres.last_heartbeat_at, timestamp 'epoch'), COALESCE(pres.check_in_at, timestamp 'epoch')), 'YYYY-MM-DD"T"HH24:MI:SSZ') AS "lastSeen"
    FROM prof
    LEFT JOIN pres ON pres.user_id = prof.member_id
    LEFT JOIN peer ON TRUE
  ) x;
$$;

GRANT EXECUTE ON FUNCTION public.get_room_header_org5(uuid) TO authenticated, service_role;

-- get_messages_org5
CREATE OR REPLACE FUNCTION public.get_messages_org5(
  p_chat_id uuid,
  p_limit int DEFAULT 50,
  p_before timestamptz DEFAULT NULL
) RETURNS TABLE(
  id uuid,
  text text,
  isImage boolean,
  imageUrl text,
  created_at timestamptz,
  isMine boolean
) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT m.id,
         m.text,
         m.is_image AS "isImage",
         m.image_url AS "imageUrl",
         m.created_at,
         (m.sender_id = auth.uid()) AS "isMine"
  FROM public.chat_messages m
  WHERE m.chat_id = p_chat_id
    AND (p_before IS NULL OR m.created_at < p_before)
  ORDER BY m.created_at DESC
  LIMIT GREATEST(COALESCE(p_limit,50),1);
$$;

GRANT EXECUTE ON FUNCTION public.get_messages_org5(uuid, int, timestamptz) TO authenticated, service_role;

-- send_message_org5 with DB broadcast
CREATE OR REPLACE FUNCTION public.send_message_org5(
  p_chat_id uuid,
  p_text text,
  p_is_image boolean DEFAULT false,
  p_image_url text DEFAULT NULL,
  p_client_id uuid DEFAULT NULL
) RETURNS public.chat_messages
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_msg public.chat_messages%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  IF NOT public.is_chat_participant(p_chat_id, v_uid) THEN
    RAISE EXCEPTION 'Not a participant of this room';
  END IF;

  INSERT INTO public.chat_messages(id, chat_id, sender_id, text, is_image, image_url)
  VALUES (COALESCE(p_client_id, gen_random_uuid()), p_chat_id, v_uid, p_text, COALESCE(p_is_image,false), p_image_url)
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO v_msg;

  IF v_msg.id IS NULL THEN
    SELECT * INTO v_msg FROM public.chat_messages WHERE id = p_client_id;
  END IF;

  -- Update room last message
  UPDATE public.chat_rooms SET last_message_text = v_msg.text, last_message_at = v_msg.created_at
  WHERE id = p_chat_id;

  -- Increment unread for other participants
  UPDATE public.chat_participants SET unread_count = unread_count + 1
  WHERE chat_id = p_chat_id AND user_id <> v_uid;

  -- Realtime handled via client channels (no DB broadcast)

  RETURN v_msg;
END; $$;

GRANT EXECUTE ON FUNCTION public.send_message_org5(uuid, text, boolean, text, uuid) TO authenticated, service_role;

-- mark_read_org5: reset unread + optional broadcast
CREATE OR REPLACE FUNCTION public.mark_read_org5(p_chat_id uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cnt int; v_uid uuid := auth.uid(); v_last public.chat_messages; BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  IF NOT public.is_chat_participant(p_chat_id, v_uid) THEN
    RAISE EXCEPTION 'Not a participant of this room';
  END IF;
  SELECT * INTO v_last FROM public.chat_messages m WHERE m.chat_id = p_chat_id ORDER BY m.created_at DESC LIMIT 1;
  INSERT INTO public.chat_read_state(chat_id, user_id, last_read_at, last_read_message_id)
  VALUES (p_chat_id, v_uid, now(), COALESCE(v_last.id, NULL))
  ON CONFLICT (chat_id, user_id) DO UPDATE
    SET last_read_at = EXCLUDED.last_read_at,
        last_read_message_id = EXCLUDED.last_read_message_id;
  UPDATE public.chat_participants SET unread_count = 0
    WHERE chat_id = p_chat_id AND user_id = v_uid;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  -- Realtime handled via client channels (no DB broadcast)
  RETURN v_cnt;
END; $$;

GRANT EXECUTE ON FUNCTION public.mark_read_org5(uuid) TO authenticated, service_role;

-- 5) Revoke PUBLIC/anon executes for safety (idempotent)
DO $$
DECLARE rec record; BEGIN
  FOR rec IN (
    SELECT 'public'::text AS nsp, p.proname AS name, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname IN (
      'get_or_create_direct_chat_org5','get_chat_list_org5','get_room_header_org5','get_messages_org5','send_message_org5','mark_read_org5'
    )
  ) LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC, anon', rec.nsp, rec.name, rec.args);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated, service_role', rec.nsp, rec.name, rec.args);
  END LOOP;
END $$;

-- 6) PostgREST schema cache refresh (optional)
NOTIFY pgrst, 'reload schema';
