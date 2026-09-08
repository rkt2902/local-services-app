-- ============================================================
-- 0037_worker_fleet_cards.sql
-- NOT APLICADA — aplicar manualmente via SQL Editor.
--
-- "Cartão Frota" — sem parceria real com nenhuma gasolineira ainda (ver
-- improvements.md, secção "Carteira digital de cartões" — anteriormente
-- bloqueada por essa razão; passa a demo/fictício, item atualizado numa
-- migration à parte desta, ver decisions_log.md). O worker fotografa um
-- cartão que já tem, o OCR corre localmente no telemóvel, extrai até 3
-- campos de texto e a FOTO É DESCARTADA IMEDIATAMENTE a seguir — nunca é
-- guardada localmente para além do necessário ao OCR, e nunca chega ao
-- Supabase Storage. Só os 3 campos de texto chegam a esta tabela. Por
-- isso não há bucket nenhum nesta migration — não é preciso.
--
-- Ativação sem fluxo automático: o status só muda de 'pending' para
-- 'active'/'rejected' manualmente via SQL Editor/service role — mesmo
-- padrão já em uso para moderação de job_reports (ver database_schema.md,
-- RLS de job_reports: "moderação é feita via Studio/service role"). Por
-- isso NÃO existe nenhuma policy de UPDATE para 'authenticated' — o
-- worker só pode criar o pedido (INSERT) e ver o seu próprio estado
-- (SELECT); sem policy de UPDATE, um PATCH via REST direto é rejeitado
-- pela RLS antes de chegar à tabela. A única forma de mudar `status` é
-- via service role (que ignora RLS), nunca pelo próprio worker.
--
-- Sem UNIQUE em worker_id de propósito: depois de um `rejected`, o worker
-- tenta outra vez fotografando de novo — como não há UPDATE, isso insere
-- uma linha NOVA em vez de reescrever a antiga. O estado "atual" do
-- worker é sempre a linha mais recente (`ORDER BY created_at DESC
-- LIMIT 1`), não "a" linha — ver `FleetCardRepository.fetchMyFleetCard`.
-- Isto preserva o histórico de tentativas em vez de o apagar.
--
-- `uuid_generate_v4()` em vez de `gen_random_uuid()`: por consistência
-- com todas as outras tabelas deste schema, que usam sempre a extensão
-- uuid-ossp (ver qualquer PRIMARY KEY em 0001_consolidated_baseline.sql).
-- Ambos funcionariam — escolhido para não introduzir uma segunda
-- convenção de geração de UUID no mesmo projeto.
-- ============================================================

CREATE TABLE IF NOT EXISTS worker_fleet_cards (
  id            uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  worker_id     uuid        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  card_number   text,
  barcode_value text        NOT NULL,
  holder_name   text,
  status        text        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'active', 'rejected')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Índice explícito: toda leitura desta tabela filtra por worker_id (ver
-- princípio de indexação já seguido para help_acceptances.worker_id,
-- notifications.user_id, etc. — colunas avaliadas pela RLS em toda
-- query precisam de índice próprio).
CREATE INDEX IF NOT EXISTS idx_worker_fleet_cards_worker_id
  ON worker_fleet_cards (worker_id);

ALTER TABLE worker_fleet_cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Worker vê os seus cartões frota"
  ON worker_fleet_cards FOR SELECT TO authenticated
  USING (worker_id = auth.uid());

CREATE POLICY "Worker pede um cartão frota"
  ON worker_fleet_cards FOR INSERT TO authenticated
  WITH CHECK (worker_id = auth.uid());

-- Sem policy de UPDATE nem DELETE para 'authenticated' — de propósito,
-- ver nota no cabeçalho. A mudança de status ('pending' → 'active' ou
-- 'rejected') é sempre manual, via SQL Editor ou service role:
--   UPDATE worker_fleet_cards SET status = 'active' WHERE id = '<id>';
