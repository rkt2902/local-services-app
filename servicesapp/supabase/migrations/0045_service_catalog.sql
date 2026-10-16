-- ══════════════════════════════════════════════════════════════
-- 0045 — Catálogo de serviços: jardinagem, agricultura e floresta
-- ══════════════════════════════════════════════════════════════
--
-- Novo:
-- - service_types.icon (nome de um ícone Material, sem o sufixo
--   _outlined; a app traduz o nome em ícone e usa um genérico se não o
--   conhecer) e sort_order nas duas tabelas.
-- - Categorias "Agricultura" e "Floresta" ao lado de "Jardinagem".
-- - 33 tipos de serviço no total, cada um com ícone.
--
-- Os 3 tipos que já existem (lawn_mowing, pruning, garden_setup) mantêm
-- o id e o nome; só ganham ícone e ordem. Pedidos e perfis de jardineiro
-- não mudam. Tipos criados à mão no Supabase que não estejam nesta lista
-- ficam como estão, com o ícone genérico, no fim da lista.
--
-- Não muda RPCs nem policies (as policies de SELECT existentes já cobrem
-- as colunas novas). APLICAR ANTES DA APP NOVA: a app nova lê
-- service_categories.sort_order e, sem esta migration, não carrega a
-- lista de serviços. A app antiga funciona com ela (ignora as colunas
-- novas e mostra os tipos novos com o ícone genérico). Pode ser aplicada
-- várias vezes sem erro.
-- ══════════════════════════════════════════════════════════════

ALTER TABLE service_categories ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 100;
ALTER TABLE service_types      ADD COLUMN IF NOT EXISTS icon       text;
ALTER TABLE service_types      ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 100;


-- ── Categorias ──────────────────────────────────────────────────

INSERT INTO service_categories (slug, name, icon, sort_order) VALUES
  ('gardening',   'Jardinagem',  'yard',        1),
  ('agriculture', 'Agricultura', 'agriculture', 2),
  ('forestry',    'Floresta',    'forest',      3)
ON CONFLICT (slug) DO UPDATE
  SET icon       = EXCLUDED.icon,
      sort_order = EXCLUDED.sort_order,
      active     = true;


-- ── Tipos de serviço ────────────────────────────────────────────
-- ON CONFLICT só atualiza ícone e ordem: o nome de um tipo que já existe
-- não é mexido.

INSERT INTO service_types (category_id, slug, name, icon, sort_order)
SELECT c.id, v.slug, v.name, v.icon, v.sort_order
FROM (VALUES
  -- Jardinagem
  ('gardening', 'lawn_mowing',        'Corte de relva',          'grass',               1),
  ('gardening', 'garden_maintenance', 'Manutenção de jardim',    'local_florist',       2),
  ('gardening', 'pruning',            'Poda',                    'content_cut',         3),
  ('gardening', 'hedge_trimming',     'Corte de sebes',          'fence',               4),
  ('gardening', 'weeding',            'Limpeza de ervas',        'eco',                 5),
  ('gardening', 'leaf_cleanup',       'Recolha de folhas',       'energy_savings_leaf', 6),
  ('gardening', 'planting',           'Plantação de flores',     'filter_vintage',      7),
  ('gardening', 'lawn_sowing',        'Sementeira de relva',     'spa',                 8),
  ('gardening', 'artificial_grass',   'Relva sintética',         'texture',             9),
  ('gardening', 'garden_setup',       'Montagem de jardim',      'yard',               10),
  ('gardening', 'irrigation',         'Sistemas de rega',        'water_drop',         11),
  ('gardening', 'garden_treatments',  'Adubação e tratamentos',  'science',            12),
  ('gardening', 'green_waste',        'Resíduos verdes',         'delete_sweep',       13),
  -- Agricultura
  ('agriculture', 'plowing',          'Lavrar terreno',          'agriculture',         1),
  ('agriculture', 'harrowing',        'Fresar e gradar',         'terrain',             2),
  ('agriculture', 'sowing',           'Sementeira e plantação',  'grain',               3),
  ('agriculture', 'vegetable_garden', 'Horta',                   'compost',             4),
  ('agriculture', 'vineyard_pruning', 'Poda de vinha e pomar',   'content_cut',         5),
  ('agriculture', 'crop_treatments',  'Tratamentos fitossanitários', 'pest_control',    6),
  ('agriculture', 'harvest',          'Colheitas',               'shopping_basket',     7),
  ('agriculture', 'olive_harvest',    'Apanha de azeitona',      'nature',              8),
  ('agriculture', 'grape_harvest',    'Vindima',                 'wine_bar',            9),
  ('agriculture', 'farm_irrigation',  'Rega agrícola',           'water',              10),
  ('agriculture', 'fencing',          'Vedações',                'fence',              11),
  -- Floresta
  ('forestry', 'land_clearing',       'Limpeza de terreno',      'cleaning_services',   1),
  ('forestry', 'fuel_management',     'Gestão de combustível',   'local_fire_department', 2),
  ('forestry', 'brush_cutting',       'Roçagem de mato',         'landscape',           3),
  ('forestry', 'tree_felling',        'Abate de árvores',        'carpenter',           4),
  ('forestry', 'tree_pruning',        'Poda em altura',          'park',                5),
  ('forestry', 'stump_removal',       'Remoção de cepos',        'handyman',            6),
  ('forestry', 'firewood',            'Corte de lenha',          'fireplace',           7),
  ('forestry', 'debris_shredding',    'Destroçamento',           'recycling',           8),
  ('forestry', 'reforestation',       'Reflorestação',           'forest',              9)
) AS v(category_slug, slug, name, icon, sort_order)
JOIN service_categories c ON c.slug = v.category_slug
ON CONFLICT (category_id, slug) DO UPDATE
  SET icon       = EXCLUDED.icon,
      sort_order = EXCLUDED.sort_order;

NOTIFY pgrst, 'reload schema';


-- ── Verificação (correr à parte depois de aplicar) ──────────────
-- Deve dar 3 categorias (13, 11 e 9 tipos), mais os tipos criados à mão:
--   select c.name, count(t.*), count(t.icon)
--   from service_categories c left join service_types t on t.category_id = c.id
--   group by c.name, c.sort_order order by c.sort_order;
