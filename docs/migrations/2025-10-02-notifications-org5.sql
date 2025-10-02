-- Notifications (Org 5) — Table, RLS, RPCs, and integration with Connections RPCs

-- 1) Table: public.notifications (idempotent-ish)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='notifications'
  ) THEN
    CREATE TABLE public.notifications (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id uuid NOT NULL,         -- recipient (customers.member_id)
      sender_id uuid NULL,           -- actor (customers.member_id)
      type text NOT NULL CHECK (type IN (
        'newMessage', 'connectionRequest', 'connectionAccepted', 'connectionRejected'
      )),
      title text NOT NULL,
      message text,
      is_read boolean NOT NULL DEFAULT false,
      requires_action boolean NOT NULL DEFAULT false,
      payload jsonb NULL,
      organization_id bigint NOT NULL DEFAULT 5,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS idx_notifications_user_created
      ON public.notifications (user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_notifications_unread
      ON public.notifications (user_id) WHERE is_read = false;
  END IF;
END $$;

-- 2) RLS: enable and restrict
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Select: recipient can read their notifications (Org 5)
DROP POLICY IF EXISTS notifications_select_self_org5 ON public.notifications;
CREATE POLICY notifications_select_self_org5
  ON public.notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid() AND organization_id = 5);

-- We will not allow generic UPDATE from client. Use RPCs to mark as read.
DROP POLICY IF EXISTS notifications_update_self_org5 ON public.notifications;

-- 3) RPCs

-- 3.a) get_notifications_org5: list notifications for current user (Org 5)
CREATE OR REPLACE FUNCTION public.get_notifications_org5(
  p_only_unread boolean DEFAULT false,
  p_limit int DEFAULT 50
) RETURNS TABLE(
  id uuid,
  type text,
  title text,
  message text,
  senderId uuid,
  senderName text,
  senderAvatar text,
  created_at timestamptz,
  isRead boolean,
  requiresAction boolean,
  payload jsonb
) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT n.id,
         n.type,
         n.title,
         COALESCE(n.message,'') AS message,
         n.sender_id AS "senderId",
         s.full_name AS "senderName",
         s.profile_image_url AS "senderAvatar",
         n.created_at AS created_at,
         n.is_read AS "isRead",
         n.requires_action AS "requiresAction",
         n.payload
  FROM public.notifications n
  LEFT JOIN public.customers s
    ON s.member_id = n.sender_id AND s.organization_id = 5
  WHERE n.user_id = auth.uid()
    AND n.organization_id = 5
    AND (p_only_unread IS NOT TRUE OR n.is_read = false)
  ORDER BY n.created_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 50), 1);
$$;

ALTER FUNCTION public.get_notifications_org5(boolean, int) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.get_notifications_org5(boolean, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_notifications_org5(boolean, int) TO service_role;

-- 3.b) mark_notification_read_org5: mark a single notification as read for current user
CREATE OR REPLACE FUNCTION public.mark_notification_read_org5(
  p_id uuid
) RETURNS public.notifications LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public' AS $$
DECLARE v_row public.notifications%ROWTYPE; BEGIN
  UPDATE public.notifications
     SET is_read = true,
         requires_action = false
   WHERE id = p_id
     AND user_id = auth.uid()
     AND organization_id = 5
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification not found'; END IF;
  RETURN v_row;
END; $$;

ALTER FUNCTION public.mark_notification_read_org5(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.mark_notification_read_org5(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_read_org5(uuid) TO service_role;

-- 3.c) mark_all_notifications_read_org5: mark all as read for current user
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read_org5()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count int; BEGIN
  UPDATE public.notifications
     SET is_read = true
   WHERE user_id = auth.uid()
     AND organization_id = 5
     AND is_read = false;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$;

ALTER FUNCTION public.mark_all_notifications_read_org5() OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read_org5() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read_org5() TO service_role;

-- 4) Helper RPC to create notification (server-side use)
CREATE OR REPLACE FUNCTION public.create_notification_org5(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_message text DEFAULT NULL,
  p_sender_id uuid DEFAULT NULL,
  p_requires_action boolean DEFAULT false,
  p_payload jsonb DEFAULT NULL
) RETURNS public.notifications LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public' AS $$
DECLARE v_row public.notifications%ROWTYPE; BEGIN
  IF p_type NOT IN ('newMessage','connectionRequest','connectionAccepted','connectionRejected') THEN
    RAISE EXCEPTION 'Invalid notification type';
  END IF;
  INSERT INTO public.notifications(user_id, sender_id, type, title, message, requires_action, payload, organization_id)
  VALUES (p_user_id, p_sender_id, p_type, p_title, p_message, COALESCE(p_requires_action,false), p_payload, 5)
  RETURNING * INTO v_row;
  RETURN v_row;
END; $$;

ALTER FUNCTION public.create_notification_org5(uuid, text, text, text, uuid, boolean, jsonb) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.create_notification_org5(uuid, text, text, text, uuid, boolean, jsonb) TO service_role;
-- Not granted to authenticated to avoid users notifying others directly.

-- 5) Integrate with Connections RPCs (send/accept/decline) to emit notifications
-- Recreate these functions to add INSERTs to notifications

-- send_connection_request_org5: add notification for addressee
CREATE OR REPLACE FUNCTION public.send_connection_request_org5(
  p_addressee_id uuid,
  p_connection_type text DEFAULT 'friend'
) RETURNS public.connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.connections%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Must be authenticated'; END IF;
  IF p_addressee_id IS NULL OR p_addressee_id = v_uid THEN RAISE EXCEPTION 'Invalid addressee'; END IF;
  IF p_connection_type NOT IN ('friend','partner') THEN RAISE EXCEPTION 'Invalid connection_type'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.blocked_users b
    WHERE b.organization_id = 5 AND ((b.blocker_id=v_uid AND b.blocked_id=p_addressee_id) OR (b.blocker_id=p_addressee_id AND b.blocked_id=v_uid))
  ) THEN RAISE EXCEPTION 'Cannot connect: blocked'; END IF;

  SELECT * INTO v_row FROM public.connections c
   WHERE c.organization_id=5
     AND ((c.requester_id=v_uid AND c.addressee_id=p_addressee_id) OR (c.requester_id=p_addressee_id AND c.addressee_id=v_uid))
   ORDER BY c.created_at DESC LIMIT 1;

  IF FOUND THEN
    IF v_row.status = 'accepted' THEN
      RETURN v_row;
    ELSIF v_row.status = 'pending' THEN
      RETURN v_row;
    ELSE
      INSERT INTO public.connections(requester_id, addressee_id, status, connection_type, organization_id)
      VALUES (v_uid, p_addressee_id, 'pending', p_connection_type, 5)
      RETURNING * INTO v_row;
    END IF;
  ELSE
    INSERT INTO public.connections(requester_id, addressee_id, status, connection_type, organization_id)
    VALUES (v_uid, p_addressee_id, 'pending', p_connection_type, 5)
    RETURNING * INTO v_row;
  END IF;

  -- Notify addressee about the connection request (requires action)
  PERFORM public.create_notification_org5(
    p_user_id         => p_addressee_id,
    p_type            => 'connectionRequest',
    p_title           => 'Permintaan koneksi',
    p_message         => 'Anda menerima permintaan koneksi baru',
    p_sender_id       => v_uid,
    p_requires_action => true,
    p_payload         => jsonb_build_object('connection_type', p_connection_type)
  );

  RETURN v_row;
END; $$;

ALTER FUNCTION public.send_connection_request_org5(uuid, text) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.send_connection_request_org5(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_connection_request_org5(uuid, text) TO service_role;

-- accept_connection_request_org5: add notification for requester
CREATE OR REPLACE FUNCTION public.accept_connection_request_org5(
  p_requester_id uuid
) RETURNS public.connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
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

  -- Notify requester that their request was accepted
  PERFORM public.create_notification_org5(
    p_user_id   => p_requester_id,
    p_type      => 'connectionAccepted',
    p_title     => 'Permintaan koneksi diterima',
    p_message   => 'Permintaan koneksi Anda telah diterima',
    p_sender_id => v_uid,
    p_requires_action => false
  );

  RETURN v_row;
END; $$;

ALTER FUNCTION public.accept_connection_request_org5(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.accept_connection_request_org5(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_connection_request_org5(uuid) TO service_role;

-- decline_connection_request_org5: add notification for requester
CREATE OR REPLACE FUNCTION public.decline_connection_request_org5(
  p_requester_id uuid
) RETURNS public.connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
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

  -- Note: By product decision, no notification on decline

  RETURN v_row;
END; $$;

ALTER FUNCTION public.decline_connection_request_org5(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.decline_connection_request_org5(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_connection_request_org5(uuid) TO service_role;

-- Optional: notify PostgREST to reload
NOTIFY pgrst, 'reload schema';
