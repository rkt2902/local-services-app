-- ==============================================================
-- supabase/migrations/0018_avatar_storage_policy_fix.sql
--
-- P-FA3 (CRÍTICO): a policy de UPDATE de avatars em storage.objects
-- usava storage.foldername(name)[1], que devolve NULL para paths
-- root-level como '$userId.jpg' — o padrão real usado pelo app
-- (worker_repository.dart:142, client_repository.dart:24).
--
-- Confirmado via query directa ao pg_policy (2026-06-26): a policy
-- "Update avatar pelo próprio utilizador" continha a expressão
-- foldername(name)[1], incompatível com ficheiros sem subpasta.
--
-- Consequência: FileOptions(upsert: true) num .upload() passa pelo
-- UPDATE policy a partir do 2.º upload (quando o ficheiro já existe).
-- Qualquer re-upload de avatar falha silenciosamente em produção.
-- O primeiro upload (INSERT) foi corrigido interactivamente em
-- 2026-06-15 e está funcional — esta migration toca apenas UPDATE
-- e DELETE.
--
-- storage.filename(name) devolve o nome completo do ficheiro
-- incluindo extensão (ex.: '$userId.jpg'). regexp_replace remove
-- a extensão antes de comparar com auth.uid()::text.
-- Alternativa equivalente para paths root-level sem subpastas:
--   split_part(name, '.', 1)
-- Optou-se por storage.filename() + regexp_replace por ser mais
-- explícito e por storage.filename() ser da mesma extensão
-- pg_storage que storage.foldername() (já confirmada funcional).
-- ==============================================================

-- ── UPDATE policy (corrigida) ─────────────────────────────────
-- Drop da policy confirmada como quebrada via pg_policy 2026-06-26.
-- Drop adicional do nome original do 0001 por idempotência
-- (caso ambas coexistam).
DROP POLICY IF EXISTS "Update avatar pelo próprio utilizador" ON storage.objects;
DROP POLICY IF EXISTS "avatars: update pelo dono"             ON storage.objects;

CREATE POLICY "avatars: update pelo próprio utilizador"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text
          = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text
          = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  );

-- ── DELETE policy (nova) ──────────────────────────────────────
-- Confirmada ausente da BD viva via pg_policy 2026-06-26.
-- Drop de ambas as denominações possíveis por idempotência.
DROP POLICY IF EXISTS "Apagar avatar pelo próprio utilizador" ON storage.objects;
DROP POLICY IF EXISTS "avatars: delete pelo dono"             ON storage.objects;

CREATE POLICY "avatars: delete pelo próprio utilizador"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text
          = regexp_replace(storage.filename(name), '\.[^.]+$', '')
  );
