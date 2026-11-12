# 08. Correções recomendadas

Nada disto está implementado: fica para aprovação. Ordem por prioridade e, dentro da mesma, por relação impacto/esforço. Todas as correções de BD cabem numa migration nova, a **0074** (confirmar o número com `ls supabase/migrations` no `main` antes de criar), que fica só criada e é aplicada por ti no SQL Editor depois da 0067 a 0073. Nenhuma muda a forma de uma RPC, por isso não precisam de `DROP FUNCTION`.

| # | Bug | O quê | Onde | Esforço | Risco da correção | Impacto |
|---|---|---|---|---|---|---|
| 1 | BUG-014 | Aplicar 0067 a 0073 por ordem, antes da próxima build; depois TM-054 | SQL Editor (só tu) | 15 min | médio (mudanças de regras em trabalhos já em curso; ler os cabeçalhos de cada ficheiro) | alto: app e BD alinhadas |
| 2 | BUG-001 | `withdraw_proposal`: `FOR UPDATE` na proposta e no pedido; `UPDATE ... AND status = 'pending'` com `IF NOT FOUND` | 0074 | 20 min | baixo | médio: acaba com trabalhos confirmados "sem jardineiro" |
| 3 | BUG-002 | No ramo INSERT de `job_request_track_visibility`, pôr a NULL os campos de execução e lembretes (`started_at`, `marked_done_at`, fotos, `*_reminder*`, `overdue_notified_at`, `undated_expiry_warned_at`) | 0074 | 15 min | baixo (a app nunca os envia) | médio |
| 4 | BUG-004 | `get_jobs_in_radius`: exigir papel worker; centro na base gravada (ou coordenadas recebidas só se a menos de N km da base); não devolver `client_id` mascarado | 0074 | 45 min | médio: pode esconder pedidos a quem usa o GPS longe da base. **Decisão tua** sobre o N | médio (privacidade) |
| 5 | BUG-006 | `CHECK (radius_km BETWEEN 1 AND 50)` (com `UPDATE` prévio dos valores fora) e `LEAST(radius_km, 50)` em `job_candidate_workers` | 0074 | 15 min | baixo | baixo a médio (custo de push) |
| 6 | BUG-003 | Policy/trigger de INSERT: data fixa tem de ser `>= today_pt()` | 0074 | 10 min | baixo | baixo |
| 7 | BUG-005 | `job_photos_before_insert`: `PERFORM ... FOR UPDATE` no pedido antes de contar | 0074 | 5 min | baixo | baixo |
| 8 | BUG-007 | `create_proposal`: recusar mínimo > máximo (horas e dias) | 0074 | 10 min | baixo | baixo |
| 9 | BUG-008 | `CHECK (char_length(...) <= N)` em `full_name`, `phone`, `bio`, `job_reports.description` com os mesmos N da UI | 0074 | 20 min | baixo (validar dados existentes antes) | baixo |
| 10 | BUG-013 | Tratar "não está aberto" como `unavailable` em `client_proposal_detail_screen.dart` | app | 10 min | baixo | baixo |
| 11 | BUG-010 | `AppToast` em `app_legal_links.dart` | app | 5 min | baixo | baixo |
| 12 | BUG-011 | Token de cor para o indicador do onboarding | app | 5 min | baixo | baixo |
| 13 | BUG-012 | Avisar "Já avaliaste" (ou permitir editar) | 0074 + app | 20 min | baixo | baixo |
| 14 | BUG-009 | Decidir se `ratings` fica legível por anónimos | decisão | n/a | n/a | baixo |

## Outras melhorias (não são bugs)

- Ligar `supabase/tests/audit/run.sh` ao CI com um serviço Postgres 16: cada migration nova passa a ser montada e testada antes de chegar ao SQL Editor (esforço: 1h).
- Portar os cenários antigos (`relatorios/2026-11-02-teste-fluxos-bd/*.sql`) para o formato com asserções do `00_lib.sql`.
- Teste do `notification_handler` (tipo → rota) e testes de duplo toque nos botões principais (ver 07).
- Atualizar `ARCHITECTURE.md` (cabeçalho, secções 7 e 14) e `STATUS.md` com o estado das migrations e a contagem de testes.

## Como validar cada correção

Para cada linha da tabela, primeiro escrever (ou ativar) o teste que falha hoje, depois corrigir, depois correr a matriz de regressão de 06. Os testes que falham hoje já existem: T-JOB-06, T-JOB-08, T-DISC-07/08, T-PROP-07, RACE-02, RACE-03 e F-006. Ao corrigir, mudar a asserção correspondente no `10_flows.sql` para o comportamento novo (por exemplo, `audit.err` em vez de `audit.ok`).
