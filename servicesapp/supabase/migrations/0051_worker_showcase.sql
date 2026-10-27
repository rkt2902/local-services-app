-- ══════════════════════════════════════════════════════════════
-- 0051 — Destaques e redes sociais no perfil do jardineiro
-- ══════════════════════════════════════════════════════════════
--
-- APLICADA na BD viva (confirmado pelo Henrique a 2026-10-27). Num projeto novo, aplicar via SQL Editor, DEPOIS da 0049
-- (a view worker_public_card abaixo mantém o filtro p.deleted_at da 0049,
-- coluna que só existe a partir dela). Pode correr-se mais do que uma vez
-- sem erro. (A 0050 fica reservada para outra thread.)
--
-- O que faz:
--   1. worker_profiles ganha:
--        highlights   text[]  até 5 frases curtas (1 a 80 caracteres),
--                             ex. "12 anos de experiência".
--        social_links jsonb   até 4 links [{ "kind": ..., "url": ... }],
--                             kind em instagram/facebook/website/other,
--                             url sempre https:// e no máximo 300 caracteres.
--      Validados por CHECK na própria tabela: a app já valida, mas a BD não
--      confia no cliente (são dados mostrados a outras pessoas e a visitantes
--      sem conta, e um javascript: ou http:// nunca deve chegar lá).
--      Escrita: o próprio jardineiro, pelo UPDATE que a app já faz em
--      worker_profiles (policy owner-only existente). Sem RPC nova.
--   2. worker_public_card (pública, anon + authenticated) passa a devolver
--      highlights e social_links, no fim da lista de colunas (CREATE OR
--      REPLACE VIEW só aceita colunas novas no fim).
--
-- Sem selo de verificação: o texto e os links são declarados pelo próprio
-- jardineiro e a app di-lo ao cliente.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Colunas e validação ────────────────────────────────────

ALTER TABLE public.worker_profiles
  ADD COLUMN IF NOT EXISTS highlights text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.worker_profiles
  ADD COLUMN IF NOT EXISTS social_links jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE OR REPLACE FUNCTION public.worker_highlights_valid(p_highlights text[])
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT coalesce(cardinality(p_highlights), 0) <= 5
     AND NOT EXISTS (
       SELECT 1
       FROM unnest(coalesce(p_highlights, '{}'::text[])) AS h
       WHERE h IS NULL
          OR length(btrim(h)) = 0
          OR length(h) > 80
     );
$function$;

CREATE OR REPLACE FUNCTION public.worker_social_links_valid(p_links jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT jsonb_typeof(p_links) = 'array'
     AND jsonb_array_length(p_links) <= 4
     AND NOT EXISTS (
       SELECT 1
       FROM jsonb_array_elements(p_links) AS l
       WHERE jsonb_typeof(l) <> 'object'
          OR (l ->> 'kind') IS NULL
          OR (l ->> 'kind') NOT IN ('instagram', 'facebook', 'website', 'other')
          OR (l ->> 'url') IS NULL
          OR length(l ->> 'url') > 300
          -- https://, um host com pelo menos um ponto, sem espaços.
          OR (l ->> 'url') !~ '^https://[^\s/?#@]+\.[^\s/?#@]+([/?#]\S*)?$'
     );
$function$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'worker_profiles_highlights_valid'
  ) THEN
    ALTER TABLE public.worker_profiles
      ADD CONSTRAINT worker_profiles_highlights_valid
      CHECK (public.worker_highlights_valid(highlights));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'worker_profiles_social_links_valid'
  ) THEN
    ALTER TABLE public.worker_profiles
      ADD CONSTRAINT worker_profiles_social_links_valid
      CHECK (public.worker_social_links_valid(social_links));
  END IF;
END
$$;


-- ── 2. Cartão público ─────────────────────────────────────────

-- Mesmas colunas e filtro da 0049, mais highlights e social_links no fim.
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
  COUNT(DISTINCT r.id) AS rating_count,
  wp.highlights,
  wp.social_links
FROM worker_profiles wp
JOIN profiles p ON p.id = wp.profile_id
LEFT JOIN worker_service_types wst ON wst.worker_id = wp.profile_id
LEFT JOIN service_types st ON st.id = wst.service_type_id
LEFT JOIN ratings r ON r.ratee_id = wp.profile_id
WHERE p.deleted_at IS NULL
GROUP BY wp.profile_id, p.full_name, p.avatar_url, wp.bio, wp.location_name,
         wp.highlights, wp.social_links;

GRANT SELECT ON public.worker_public_card TO anon, authenticated;
