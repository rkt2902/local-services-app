# 07. Lacunas de cobertura

## O que foi executado (com evidência)

| Execução | Resultado | Evidência |
|---|---|---|
| `flutter analyze` | 0 issues | `evidence/flutter-analyze.txt` |
| `flutter test` | 621 testes, todos passam, sem testes instáveis nesta corrida | `evidence/flutter-test.txt` |
| Migrations 0001 a 0073 numa BD Postgres 16 vazia | 41 ficheiros aplicam sem erro | `evidence/bd-10_flows.txt` (1.ª linha) |
| `10_flows.sql` (fluxos com RLS, como a app) | 162 asserções: 156 passam, 6 falham (achados) | `evidence/bd-10_flows.txt` |
| `30_findings.sql` (reprodução dos bugs) | 17 asserções, todas confirmam o comportamento descrito | `evidence/bd-30_findings.txt` |
| `20_concurrency.sh` (2 sessões em paralelo) | 2 passam, 2 falham (BUG-001, BUG-005), 1 informativo | `evidence/bd-20_concurrency.txt` |
| Contrato RPC app ↔ BD | 59 RPCs; nomes e parâmetros batem | `rpccheck.py` (relatórios de 02/11) + revisão manual |
| Contrato de tipos de notificação | batem | script na secção abaixo |
| Pesquisa de segredos no repositório | nada encontrado | `git grep` (ver 04) |

Mocks e stubs: os testes da BD não usam mocks das regras de negócio; usam stubs só para o que o Supabase fornece por fora do Postgres (`auth.uid()`, `auth.jwt()`, tabelas mínimas de `auth`, `storage.objects`, `cron.schedule`, `vault`, `net.http_post`). Isto quer dizer que **Auth, Storage real, Realtime, pg_net e a Edge Function não foram validados**: um teste com stub não equivale a uma integração real.

## O que não foi possível testar e porquê

| Área | Fluxos | Motivo | Como fechar |
|---|---|---|---|
| UI real (toques, layout, navegação, animações) | todos | sem emulador nem dispositivo; a app precisa de um Supabase real para arrancar | plano manual 05; opcional: testes de integração com `integration_test` contra um projeto Supabase de testes |
| Supabase Auth (registo, OTP, recuperação, OAuth, MFA) | 002 a 005, 008, 080 | não existe localmente; stub só simula `auth.uid()` e `aal` | TM-002 a TM-009, TM-053 |
| Email (SMTP Brevo) | 003, 008 | serviço externo | TM-003, TM-009 |
| Push (FCM, APNs, Edge Function, pg_net, Vault) | 073, 099 | serviços externos e segredos | TM-046, TM-047 |
| Realtime (lista e aviso no topo) | 070, 072 | precisa do servidor Realtime | TM-043, TM-045 |
| Storage real (upload, URLs públicos, compressão) | 012, 020, 046, 048, 077 | só as policies foram testadas sobre `storage.objects` | TM-013, TM-016, TM-036, TM-050 |
| GPS, permissões do SO, câmara, galeria | 007, 012, 020, 046, 058, 078 | precisam de dispositivo | TM-008, TM-013, TM-036, TM-041, TM-051 |
| APIs externas (Photon, Nominatim, tiles OSM) | 078 | rede externa e limites de uso | TM-051 |
| OCR (ML Kit) | 058 | só em Android/iOS | TM-041 |
| WhatsApp, partilha, browser externo | 036, 055, 076 | apps externas | TM-030, TM-039, TM-049 |
| Web (Netlify, recarregar, URLs diretos) | 100 | sem deploy | TM-055 |
| pg_cron real (agendamento e horários) | 090 a 098 | localmente as funções foram chamadas à mão; o agendador não corre | TM-054 (query de leitura na BD viva) |
| Rede lenta, timeouts, modo de avião | 009, 079, 101 | sem dispositivo | TM-010, TM-052 |
| Tempo real (24h, 48h, 7 dias, 30 dias) | 033, 059, 090, 091, 093 | localmente simulado mudando datas; não visto a passar de verdade | TM-028, TM-042 |
| Lista e ficha do admin | 081 | `admin_list_workers` e `admin_get_worker` não estão na bateria | acrescentar ao `10_flows.sql` |
| `reject_proposal`, `decline_direct_job_request`, `release_direct_job_request`, trabalho por dias, relatos | 026, 044, 047, 029 | não repetidos: cobertos pelos cenários das revisões de 02/11 a 12/11 (`relatorios/2026-11-02-teste-fluxos-bd/`) | portar esses cenários para o formato com asserções |

## Fluxos sem nenhum teste automático na app (só vistas e lógica testadas noutros)

Os ecrãs ligados ao Supabase (`*_screen.dart`) não têm testes de widget; só as vistas puras e os presenters. Sem nenhum teste Flutter dedicado: FLOW-010 (terminar sessão), FLOW-022 (editar pedido), FLOW-028 (confirmar), FLOW-029 (reportar), FLOW-030 (avaliar), FLOW-035 (os teus jardineiros), FLOW-039 (dicas da época), FLOW-055 (cartão partilhável), FLOW-058 (cartão frota), FLOW-071 (navegação das notificações), FLOW-072 (aviso no topo), FLOW-073 (push), FLOW-074 (as minhas avaliações), FLOW-075 (voltar), FLOW-078 (moradas).

O mais útil a acrescentar, por esta ordem:

1. Teste do `notification_handler`: para cada tipo, a rota escolhida (tabela pura, sem rede). Apanha regressões em 38 tipos de uma vez.
2. Testes de widget dos botões principais com repositório falso: garante que o botão fica a carregar e não chama a RPC duas vezes (FLOW-101).
3. Portar os cenários antigos da BD para o formato com asserções e ligar `run.sh` ao CI (Postgres em serviço do GitHub Actions), para cada migration nova ser testada antes de ir para o SQL Editor.

## Script de contrato dos tipos de notificação

Usado nesta auditoria (corre contra a BD local):

```bash
psql -d pj_audit -tA -c "select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where nspname='public' and prosrc ilike '%notifications%'" > notif_src.sql
grep -oE "'[a-z_]+'" lib/features/notifications/data/notification_types.dart | tr -d "'" | sort -u > darttypes.txt
# depois comparar as palavras citadas dentro de 'INSERT INTO notifications ... ;' com darttypes.txt
```

Resultado: as únicas diferenças eram `pending_approval` (estado, não tipo), `seasonal_campaign` (`related_type`) e os `help_job_*` que o SQL monta numa variável (`v_type := 'help_job_started'`). Sem tipos órfãos.
