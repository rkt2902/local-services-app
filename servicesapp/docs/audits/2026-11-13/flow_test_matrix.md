# Matriz de fluxos e casos extremos (13/11/2026)

Uma linha por fluxo funcional. As colunas dizem **que tipo de evidência existe hoje**:

- **BD**: asserções numa BD Postgres 16 local com todas as migrations e RLS ligada (`supabase/tests/audit/`), corridas nesta auditoria: `10_flows.sql` 162/162 PASS, `30_findings.sql` 20/20 PASS, `20_concurrency.sh` RACE-01 a 04 PASS, `40_help_slot_race.sh` RACE-06 PASS (novo).
- **Flutter**: 645 testes de lógica e de vistas, todos PASS; `flutter analyze` 0 issues.
- **Web E2E**: Playwright contra Supabase local em Docker, 12/11 (37 testes manuais em browser, achados corrigidos nos PR #50 e #52).
- **Android**: aparelho real. **Nenhum fluxo tem esta evidência.**

✓ testado e passou · ✗ falhou · ○ não testado · n/a não se aplica

## Matriz principal

| Fluxo | Normal | Erros / extremos | BD | Flutter | Web E2E | Android |
|---|---|---|---|---|---|---|
| Onboarding | Saltar, Começar | | n/a | ✓ | ✓ | ○ |
| Registo | email, senha forte, termos | senha fraca, email repetido, email de conta eliminada | ✓ T-PROF | ✓ | ✓ | ○ |
| Confirmação de email | código | código errado, reenviar | n/a | ✓ (vista) | ○ (sem SMTP) | ○ |
| Login | email e senha | senha errada, conta eliminada, sem rede | n/a | ✓ | ✓ | ○ |
| Login Google | | conta nova sem telefone | n/a | ✓ (lógica) | ○ | ○ |
| Recuperar senha | 4 passos | código errado, expirado | n/a | ✓ | ○ | ○ |
| Escolher papel | cliente, jardineiro | mudar papel por API | ✓ | ✓ | ✓ | ○ |
| Setup do jardineiro | raio, base, serviços | sem GPS, raio fora de 1..50 | ✓ | ✓ | ✓ | ○ |
| Sessão e reinício | sessão mantém-se | sessão expirada, perfil não carrega | n/a | ✓ | ✓ | ○ |
| Logout | | | n/a | ○ | ✓ | ○ |
| Rotas protegidas | | sem sessão, papel cruzado, admin | ✓ T-ADM | ✓ `route_guard_test` | ✓ | ○ |
| Criar pedido | 4 passos | data no passado, sem morada, 3.ª foto, 6 pedidos em 1h, estado forjado | ✓ T-JOB, RACE-03 | ✓ | ✓ | ○ |
| GPS e morada | | permissão recusada, Nominatim em baixo | n/a | ○ | ✗ bloqueado no ambiente | ○ |
| Data fixa / flexível / a combinar | | a combinar 27 e 30 dias | ✓ | ✓ | ✓ | ○ |
| Editar pedido | | com propostas, sem morada | ✓ T-EDIT | ✓ | ✓ | ○ |
| Cancelar pedido aberto | | | ✓ T-CANC | ✓ | ✓ | ○ |
| Descobrir pedidos | raio, categorias | coordenadas forjadas, pedido reservado a outro | ✓ T-DISC | ✓ | ✓ | ○ |
| Proposta por hora | | valor 0 ou negativo, horas invertidas, data passada, duplicada | ✓ T-PROP, RACE-04 | ✓ | ✓ | ○ |
| Proposta valor total, dias, validade | | validade passada, aceitar expirada | ✓ | ✓ | ✓ | ○ |
| Proposta com equipa e equipamento | | | ✓ T-HELP | ✓ | ✓ | ○ |
| Limite do plano Grátis | | 6.ª proposta | ✓ T-PLAN | ✓ | ✓ | ○ |
| Comparar e aceitar | | duas aceitações juntas, aceitar enquanto retira | ✓ RACE-01, RACE-02 | ✓ | ✓ | ○ |
| Recusar proposta | | | ✓ (02/11) | ✓ | ○ | ○ |
| Retirar proposta | | | ✓ | ✓ | ○ | ○ |
| Pedido direto / pelo cartão | 24h exclusivo | "Não posso", expirar, interruptor desligado, sem sessão | ✓ T-CARD | ✓ | ✓ | ○ |
| Trabalho confirmado: contactos | WhatsApp, telefone visível | antes de aceite (escondido) | ✓ | ✓ | ✓ (ecrã) | ○ (abrir apps) |
| Remarcação | propor, aceitar, recusar | regra das 24h, a meio de outra | ✓ T-RESCH | ✓ | ✓ | ○ |
| Cancelar trabalho confirmado | com reabertura | cancelar e aceitar ao mesmo tempo | ✓ T-CANC, RACE-05 (info) | ✓ | ✓ | ○ |
| Iniciar | 1h antes | antes da hora, sem fotos, toque duplo | ✓ T-EXEC | ✓ | ✓ | ○ |
| Vários dias | terminar e começar dia | dois dias abertos | ✓ | ✓ | ✓ | ○ |
| Concluir | fotos de depois | antes do dia, sem iniciar | ✓ | ✓ | ✓ | ○ |
| Confirmar pela cliente | | 48h automático, 7 dias com relato | ✓ T-CRON | ✓ | ✓ | ○ |
| Reportar problema | | duas vezes | ✓ | ✓ | ✓ | ○ |
| Pedido de ajuda | criar, aprovar, abrir | aprovação automática 24h, véspera, dia do trabalho | ✓ T-HELP | ✓ | ✓ | ○ |
| Candidatura a ajudante | | duplicada, após vagas cheias, depois de desistir | ✓ T-HELP | ✓ | ✓ | ○ |
| Aceitar ajudante | taxa acordada | **dois para a última vaga** | ✓ **RACE-06 (novo)** | ✓ | ✓ | ○ |
| Mudar vagas | | aceitar e mudar vagas ao mesmo tempo | ✓ RACE-07 info (coerente: 1 aceite, pedido aberto com 2 vagas) | ✓ | ○ | ○ |
| Desistir / retirar ajudante | | no dia do trabalho | ✓ | ✓ | ○ | ○ |
| Cancelar trabalho principal com equipa | cascade | | ✓ | ✓ | ○ | ○ |
| Avaliar (todos os sentidos) | | duplicada, sem participar, depois de cancelado | ✓ T-RATE | ✓ | ✓ | ○ |
| Notificações in-app | 38 tipos | tipos órfãos, lidas, limpar e desfazer | ✓ T-NOTIF | ✓ | ✓ (9 tipos navegados) | ○ |
| Push | | sem Firebase, token inválido | ✓ T-PUSH (stub) | ○ | ○ | ○ |
| Timeline / stepper | estados todos | cancelado, sem resposta, relato | n/a | ✓ | ✓ (7 estados, TM-022) | ○ |
| Agenda | Hoje, Semana, Mês | séries, "Só este dia", sobreposições | ✓ T-AG | ✓ | ✓ | ○ |
| Cartão partilhável | imagem, link, PDF Pro | Grátis sem PDF | ✓ T-CARD | ✓ | ✓ | ○ |
| Cartão frota | | | ✓ T-FLEET | ○ | ○ | ○ |
| Admin | TOTP, planos | sem aal2, não admin | ✓ T-ADM | ✓ | ✓ | n/a |
| Eliminar conta | | com trabalho ativo, email reutilizado | ✓ T-DEL | ✓ | ✓ | ○ |
| Storage | upload próprio | pasta de outro, 3.ª foto | ✓ T-STOR | ✓ | ✓ | ○ |
| Crons | 11 jobs | | ✓ (chamados à mão) | n/a | ✓ (BD local) | ○ BD viva |

## Concorrência (BD local)

| ID | Cenário | Resultado |
|---|---|---|
| RACE-01 | Cliente aceita duas propostas ao mesmo tempo | PASS: só 1 aceite |
| RACE-02 | Aceitar e retirar ao mesmo tempo | PASS: confirmado e aceite, retirada recusada |
| RACE-03 | 2 fotos em paralelo com 1 já gravada | PASS: máximo 2 |
| RACE-04 | Mesma proposta enviada 2 vezes | PASS: só 1 |
| RACE-05 | Aceitar e cancelar ao mesmo tempo | INFO: cancelamento espera e decide sobre o estado final |
| RACE-06 | **Dois candidatos aceites para a última vaga** (novo) | PASS: 1 aceite, pedido `filled`, o segundo recebe "O pedido de ajuda não está aberto" |
| RACE-07 | Aceitar o último candidato e aumentar vagas ao mesmo tempo (novo) | INFO: 1 aceite, pedido volta a `open` com 2 vagas; o outro candidato fica recusado (foi recusado quando encheu) |

## Lacunas desta matriz

- A coluna Android está vazia: é o maior risco (`manual_test_plan.md`).
- Push, Realtime, email, OAuth, moradas e mapa nunca correram com os serviços reais.
- A BD viva nunca foi comparada com a BD local desde 16/10 (TR-26).
