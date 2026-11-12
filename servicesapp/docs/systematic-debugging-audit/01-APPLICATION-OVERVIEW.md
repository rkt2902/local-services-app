# 01. Visão geral da aplicação

Auditoria feita a 12/11/2026 sobre o ramo do PR #47 (`claude/project-thread-4zzdn3`, commit `7c9f539`), que é o `main` (commit `5dbe2af`) mais as migrations 0071, 0072 e 0073. Escolhi este ramo porque tem as correções mais recentes e é o que vai entrar a seguir. A referência técnica completa continua a ser `docs/ARCHITECTURE.md`; aqui fica só o que a auditoria confirmou e o que difere.

Metodologia: skill `systematic-debugging` (raiz do problema antes de qualquer correção: reproduzir, recolher evidência, hipótese, teste mínimo, registo). Nesta primeira auditoria não alterei comportamento: só documentação e testes que correm numa BD local.

## O que é

Marketplace de serviços locais (jardinagem no lançamento), Flutter + Supabase. Sem pagamentos nem chat: contacto por WhatsApp depois de a proposta ser aceite. Receita vem dos planos dos jardineiros (Grátis, Pro, Pro+), atribuídos à mão no painel `/admin`.

## Tecnologias (confirmado no código e no ambiente)

| Camada | O quê |
|---|---|
| App | Flutter 3.44.1, Dart 3.12, `flutter_riverpod` 3.3, `go_router` 17, `supabase_flutter` 2.12; Android, iOS, web (Netlify) |
| Backend | Supabase: Postgres com RLS, 155 funções no schema `public` (contadas na BD local), 28 tabelas, views, triggers, Storage (2 buckets públicos), Auth (email, OTP, OAuth Google/Facebook, TOTP para admin), Realtime |
| Processos automáticos | 11 jobs de `pg_cron` (lista em 06) |
| Push | Firebase Cloud Messaging via Edge Function `send-push` (Deno), chamada por trigger com `pg_net` e segredo no Vault |
| Serviços externos | Photon e Nominatim (moradas), tiles OSM, geocoder do sistema, Google ML Kit (OCR local), WhatsApp, `url_launcher`, `share_plus` |
| CI | GitHub Actions: `flutter analyze` (falha com qualquer aviso) e `flutter test` em cada PR; deploy web manual |

## Estrutura

- `servicesapp/lib`: 308 ficheiros Dart. `core/` (router, tema, widgets partilhados, utils) e 13 features: admin, agenda, auth, client, fleet_card, help_requests, jobs, notifications, onboarding, proposals, ratings, worker.
- `servicesapp/supabase/migrations`: 41 ficheiros ativos (0001 consolidada, 0033 a 0073, sem a 0050) e `archive/` com o histórico antigo.
- `servicesapp/supabase/functions/send-push`: Edge Function do push.
- `servicesapp/test`: 67 ficheiros, 621 testes (lógica, presenters e vistas puras, sem rede).
- `servicesapp/supabase/tests/audit` (novo nesta auditoria): BD de teste e cenários com asserções.

## Utilizadores e permissões

| Papel | Como se obtém | O que pode (verificado na BD) |
|---|---|---|
| Visitante | sem sessão | cartão público `/w/:id` (view `worker_public_card`), registar visita, ler avaliações (BUG-009) |
| Cliente | `profiles.role = 'client'` | criar pedidos (5 por hora), editar enquanto abertos, aceitar/recusar propostas, remarcar, cancelar, confirmar, reportar, avaliar; vê o telefone do jardineiro só com trabalho confirmado |
| Jardineiro | `role = 'worker'` + perfil completo | ver pedidos abertos mascarados, propor (Grátis: 5 aceites por mês), iniciar, concluir, pedir ajudantes, candidatar-se como ajudante, Agenda própria, cartão, ganhos (Pro) |
| Ajudante | jardineiro com candidatura aceite | ver o trabalho de ajudante e o telefone do responsável (não o da cliente), avaliar o responsável |
| Admin | linha em `admin_users` + segundo fator TOTP (`aal2`) | painel, lista e ficha de jardineiros, mudar planos (fica em `admin_actions`) |
| Sistema | `pg_cron` / `service_role` | expirar, confirmar, lembrar, limpar |

O papel é escolhido uma vez e não muda (trigger `tg_prevent_profile_role_change`, T-PROF-01). As escritas de negócio passam por RPCs `SECURITY DEFINER` com identidade sempre por `auth.uid()`; as tabelas que a app escreve diretamente (pedido, fotos, perfil, agenda, relatos, cartão frota) têm RLS testada (ver 03).

## Relação app, backend e BD

App → repositórios (`*_repository.dart`, únicos que falam com o Supabase) → `rpc(...)` (59 RPCs distintas) ou `from(...)` (18 tabelas e views) → Postgres com RLS. Notificações nascem sempre no servidor (RPCs, triggers, cron); a app ouve-as por Realtime e invalida os providers certos; o push sai da BD para a Edge Function.

Verificação de contrato feita nesta auditoria: as 59 RPCs chamadas pela app existem na BD montada com as migrations, com os parâmetros certos, e os tipos de notificação criados pelo SQL batem com os que a app conhece.

## Ambientes disponíveis para a auditoria

| Ambiente | Disponível | Usado para |
|---|---|---|
| Flutter SDK 3.44.1 (contentor) | sim | `flutter analyze`, `flutter test` |
| Postgres 16 local com stubs de `auth`, `storage`, `cron`, `vault`, `pg_net` | sim | aplicar todas as migrations e correr os fluxos com RLS |
| Supabase real (Auth, Storage, Realtime, Edge Functions) | não, e não devia | nada; marcado BLOQUEADO |
| Emulador ou telemóvel | não | nada; vai para o plano manual (05) |
| Firebase, Google/Meta OAuth, SMTP, Netlify | não | nada; BLOQUEADO |

## Documentação comparada com a implementação

| Documento | Diferença encontrada |
|---|---|
| `ARCHITECTURE.md` cabeçalho e secção 7 | Diz "todas as migrations aplicadas até à 0065" e "próxima 0066". Hoje: aplicadas até à 0066, 0067 a 0073 por aplicar, próxima 0074 (ver BUG-014). |
| `ARCHITECTURE.md` secção 9 | Fala em 38 tipos de notificação; os tipos do SQL e da app batem (contagem não refeita tipo a tipo). |
| `ARCHITECTURE.md` secção 14 | "62 ficheiros e cerca de 560 testes"; hoje 67 ficheiros e 621 testes. |
| `ARCHITECTURE.md` secção 7 (Storage) | Confirmado: 2 buckets públicos; políticas por pasta testadas (T-STOR). |
| `ARCHITECTURE.md` secção 7 (pg_cron) | Confirmado: 11 jobs na BD montada; os nomes e horários estão em 06. |
| Revisões anteriores (`relatorios/2026-11-*`) | Os cenários antigos continuam a correr; os pontos corrigidos nas partes 1 a 5 não voltaram a falhar nesta bateria. |

Não alterei nenhum destes documentos; a atualização fica proposta em 08.
