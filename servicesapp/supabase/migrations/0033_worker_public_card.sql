-- 0033_worker_public_card.sql
-- NOT APLICADA — aplicar manualmente via SQL Editor.
--
-- Suporte ao cartão digital partilhável do worker (perfil público mínimo,
-- acessível sem sessão via link/QR). View definer-style (sem
-- security_invoker), mesmo padrão de worker_profiles_public (0030) — corre
-- com os privilégios do dono da view, não do caller, para poder expor um
-- subconjunto seguro de colunas a `anon` sem alargar a RLS das tabelas base.
--
-- Expõe apenas: nome, avatar, bio, zona (location_name), serviços, rating
-- agregado. NÃO expõe telefone, morada exata (base_lat/base_lng), raio de
-- atuação nem ferramentas.

CREATE OR REPLACE VIEW public.worker_public_card AS
SELECT
  wp.profile_id AS worker_id,
  p.full_name,
  p.avatar_url,
  wp.bio,
  wp.location_name,
  COALESCE(
    array_agg(DISTINCT st.name) FILTER (WHERE st.name IS NOT NULL),
    ARRAY[]::text[]
  ) AS service_names,
  COALESCE(AVG(r.stars), 0)::numeric(3, 2) AS avg_rating,
  COUNT(DISTINCT r.id) AS rating_count
FROM worker_profiles wp
JOIN profiles p ON p.id = wp.profile_id
LEFT JOIN worker_service_types wst ON wst.worker_id = wp.profile_id
LEFT JOIN service_types st ON st.id = wst.service_type_id
LEFT JOIN ratings r ON r.ratee_id = wp.profile_id
GROUP BY wp.profile_id, p.full_name, p.avatar_url, wp.bio, wp.location_name;

GRANT SELECT ON public.worker_public_card TO anon, authenticated;
