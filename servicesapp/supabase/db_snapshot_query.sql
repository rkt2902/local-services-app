SELECT
  '1_tables' AS section,
  'column' AS object_type,
  t.table_name || '.' || c.column_name AS object_name,
  c.data_type
  || CASE WHEN c.column_default IS NOT NULL
     THEN ' DEFAULT ' || c.column_default ELSE '' END
  || CASE WHEN c.is_nullable = 'NO'
     THEN ' NOT NULL' ELSE '' END AS definition
FROM information_schema.tables t
JOIN information_schema.columns c
  ON c.table_name = t.table_name
  AND c.table_schema = 'public'
WHERE t.table_schema = 'public'
  AND t.table_type = 'BASE TABLE'
  AND t.table_name IN (
    'profiles','worker_profiles','worker_service_types',
    'service_types','job_requests','job_proposals',
    'job_reports','help_requests','help_acceptances',
    'ratings','notifications'
  )

UNION ALL

SELECT
  '2_constraints',
  tc.constraint_type,
  tc.table_name || '.' || tc.constraint_name,
  pg_get_constraintdef(pgc.oid)
FROM information_schema.table_constraints tc
JOIN pg_constraint pgc ON pgc.conname = tc.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.table_name IN (
    'profiles','worker_profiles','worker_service_types',
    'service_types','job_requests','job_proposals',
    'job_reports','help_requests','help_acceptances',
    'ratings','notifications'
  )

UNION ALL

SELECT
  '3_indexes',
  'index',
  tablename || '.' || indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles','worker_profiles','worker_service_types',
    'service_types','job_requests','job_proposals',
    'job_reports','help_requests','help_acceptances',
    'ratings','notifications'
  )
  AND indexname NOT LIKE '%_pkey'

UNION ALL

SELECT
  '4_rls_policies',
  'policy_' || cmd,
  tablename || '.' || policyname,
  'USING: ' || COALESCE(qual, 'none')
  || ' | WITH_CHECK: ' || COALESCE(with_check, 'none')
FROM pg_policies
WHERE schemaname = 'public'

UNION ALL

SELECT
  '5_functions',
  CASE WHEN prosecdef THEN 'security_definer'
       ELSE 'security_invoker' END,
  proname || '(' || pg_get_function_identity_arguments(oid) || ')',
  pg_get_functiondef(oid)
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN (
    'accept_help_candidate','accept_proposal',
    'approve_help_request','auto_confirm_completed_jobs',
    'auto_expire_jobs','cancel_job',
    'check_rater_not_ratee',
    'client_has_confirmed_job_with_worker',
    'create_job','create_proposal',
    'get_accepted_helpers_for_job',
    'get_help_requests_in_radius',
    'get_jobs_in_radius','get_my_help_acceptances',
    'is_principal_worker_for_help_request',
    'mark_job_done','propose_reschedule',
    'accept_reschedule','reject_reschedule',
    'reject_help_candidate',
    'submit_client_rating','submit_helper_rating',
    'submit_principal_rating',
    'sync_worker_service_types',
    'withdraw_help_acceptance'
  )

UNION ALL

SELECT
  '6_views',
  'view',
  viewname,
  definition
FROM pg_views
WHERE schemaname = 'public'
  AND viewname IN (
    'worker_profiles_public',
    'worker_rating_summary'
  )

UNION ALL

SELECT
  '7_storage_buckets',
  'bucket',
  name,
  'public=' || public::text
  || ' size_limit=' || COALESCE(file_size_limit::text, 'none')
FROM storage.buckets
WHERE name IN ('avatars', 'job-photos')

UNION ALL

SELECT
  '8_storage_policies',
  'storage_policy',
  bucket_id || '.' || name,
  definition
FROM storage.policies
WHERE bucket_id IN ('avatars', 'job-photos')

ORDER BY section, object_type, object_name;
