-- ==============================================================================
-- DigiQ Live Database Migration Status Audit
-- Run this in Supabase Dashboard -> SQL Editor
-- It reads schema metadata only (zero writes, zero risk)
-- ==============================================================================

SELECT 
    '1. TABLE_EXISTS' AS check_category,
    t.table_name AS entity_name,
    'EXISTS' AS status,
    CASE 
        WHEN t.table_name IN ('email_security_settings', 'blocked_email_domains', 'allowed_email_domains') THEN 'Part of Migration 009'
        WHEN t.table_name = 'email_check_rate_limits' THEN 'Part of Migration 008'
        WHEN t.table_name = 'payment_mutations' THEN 'Part of Migration 002'
        ELSE 'Core Schema (001-007)'
    END AS description
FROM information_schema.tables t
WHERE t.table_schema = 'public' 
  AND t.table_name IN ('profiles', 'products', 'transactions', 'payment_mutations', 'app_settings', 'email_security_settings', 'blocked_email_domains', 'email_check_rate_limits')

UNION ALL

SELECT 
    '2. FUNCTION_EXISTS' AS check_category,
    p.proname AS entity_name,
    'EXISTS' AS status,
    CASE 
        WHEN p.proname = 'is_email_verified' THEN 'Migration 009 applied'
        WHEN p.proname IN ('check_email_available', 'update_my_profile') THEN 'Migration 007 applied'
        WHEN p.proname = 'check_username_available' THEN 'Migration 006 applied'
        WHEN p.proname = 'create_purchase_transaction' THEN 'Migration 002/005 applied'
        WHEN p.proname = 'verify_payment_by_amount' THEN 'Migration 002 applied'
        WHEN p.proname = 'expire_pending_transactions' THEN 'Migration 002 applied'
        ELSE 'Core Function'
    END AS description
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('check_username_available', 'check_email_available', 'update_my_profile', 'is_email_verified', 'create_purchase_transaction', 'verify_payment_by_amount', 'expire_pending_transactions', 'is_admin')

UNION ALL

SELECT 
    '3. TRIGGER_EXISTS' AS check_category,
    tg.tgname AS entity_name,
    'EXISTS' AS status,
    CASE 
        WHEN tg.tgname = 'trg_protect_profile_sensitive_columns' THEN 'Migration 007 applied'
        WHEN tg.tgname = 'on_auth_user_created' THEN 'Migration 001/006 applied'
        ELSE 'Trigger'
    END AS description
FROM pg_trigger tg
JOIN pg_class c ON tg.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND tg.tgname IN ('trg_protect_profile_sensitive_columns', 'on_auth_user_created')

UNION ALL

SELECT 
    '4. STORAGE_BUCKET' AS check_category,
    b.id AS entity_name,
    CASE WHEN b.public THEN 'PUBLIC (OK)' ELSE 'PRIVATE' END AS status,
    'Limit: ' || (b.file_size_limit / 1024 / 1024) || ' MB, MIME: ' || array_to_string(b.allowed_mime_types, ', ') AS description
FROM storage.buckets b
WHERE b.id IN ('avatars', 'product-images')

UNION ALL

SELECT 
    '5. REALTIME_PUBLICATION' AS check_category,
    pt.tablename AS entity_name,
    'IN PUBLICATION' AS status,
    'Realtime active on ' || pt.schemaname || '.' || pt.tablename AS description
FROM pg_publication_tables pt
WHERE pt.pubname = 'supabase_realtime' 
  AND pt.tablename IN ('products', 'transactions', 'profiles')

ORDER BY check_category, entity_name;

