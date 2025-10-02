-- Security hardening: REVOKE EXECUTE for Org5 RPCs from PUBLIC/anon
-- Keep EXECUTE only for authenticated and service_role.

-- Helper to revoke if function exists
DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN (
    SELECT 'public'::text AS nsp, p.proname AS name, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        -- Login/Profile/Presence/Locations/Discounts
        'auth_sync_customer_login_org5',
        'get_customer_detail_by_member_id_org5',
        'update_customer_profile_org5',
        'presence_check_in_org5',
        'presence_heartbeat_org5',
        'presence_check_out_org5',
        'get_current_presence_org5',
        'get_locations_org5',
        'get_discounts_org5',
        -- Connect + Members + Connections
        'get_members_org5',
        'get_member_detail_org5',
        'send_connection_request_org5',
        'accept_connection_request_org5',
        'decline_connection_request_org5',
        'unfriend_org5',
        -- Notifications
        'get_notifications_org5',
        'mark_notification_read_org5',
        'mark_all_notifications_read_org5',
        'create_notification_org5'
      )
  ) LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC, anon', rec.nsp, rec.name, rec.args);
    -- Ensure grants (idempotent)
    EXECUTE format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO authenticated, service_role', rec.nsp, rec.name, rec.args);
  END LOOP;
END $$;

-- Refresh PostgREST schema cache (optional)
NOTIFY pgrst, 'reload schema';

