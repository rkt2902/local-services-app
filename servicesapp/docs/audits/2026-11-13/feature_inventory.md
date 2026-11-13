# Inventário de funcionalidades (13/11/2026)

**Estado auditado:** `main` em `5cd9c59` (PR #52), migrations `0001` a `0075` no repositório.
**Fontes:** código (`lib/`, 309 ficheiros Dart, 82 mil linhas), `app_router.dart` (52 rotas), migrations, testes Flutter, testes da BD local (`supabase/tests/audit/`), relatórios de 12/11 (auditoria sistemática e testes web com várias contas).

## Como ler os estados

| Estado | Critério usado nesta auditoria |
|---|---|
| **Verificada** | Existe e há evidência automática do comportamento: asserções na BD local com RLS (`10_flows.sql`, `30_findings.sql`, corridas) **e** teste de ponta a ponta na web com Supabase local (12/11) ou testes Flutter da lógica e da vista. **Nunca vista num telemóvel nem contra a BD de produção.** |
| **Implementada, não testada** | Existe código, mas falta evidência de execução (serviço externo, dispositivo ou configuração). |
| **Parcial** | Parte do fluxo existe; falta configuração ou um pedaço. |
| **Mock / Placeholder** | Dados ou ações fictícias. |
| **Quebrada** | Problema identificado e ainda aberto. |
| **Planeada** | Só na documentação. |
| **Obsoleta** | Já não pertence ao produto. |
| **Necessita decisão** | Comportamento por definir. |

Nenhuma funcionalidade foi validada num dispositivo físico nem na BD viva nesta auditoria (sem acesso a nenhum dos dois a partir deste ambiente).

## 1. Conta, autenticação e sessão

| # | Funcionalidade | Onde | Estado | Evidência / nota |
|---|---|---|---|---|
| 1 | Onboarding de 3 slides | `/onboarding` | Verificada | TM-001 web 12/11 |
| 2 | Registo por email com política de senha | `/signup` | Verificada | TM-002 web; `password_policy` testada |
| 3 | Confirmação de email por código | `/verify-email` | Implementada, não testada | Depende de SMTP e de ligar "Confirm email" no Supabase (AUD-02) |
| 4 | Login por email | `/login` | Verificada | TM-004 web |
| 5 | Login com Google | `social_sign_in_buttons.dart` | Implementada, não testada | Botão sempre visível; configuração OAuth por confirmar (AUD-06) |
| 6 | Login com Facebook | idem | Parcial | Escondido por `FACEBOOK_LOGIN_ENABLED`; app da Meta em Development |
| 7 | Recuperação de senha por código | `/forgot-password/*` | Implementada, não testada | Depende de SMTP e template com `{{ .Token }}` (AUD-02); bypass só em `kDebugMode` |
| 8 | Escolha de papel | `/choose-role` | Verificada | TM-007 web; trigger impede mudar `role` (testado) |
| 9 | Setup do jardineiro (raio, base, serviços, ferramentas, foto) | `/worker/setup` | Verificada | TM-008 web (morada por coordenadas por bloqueio do OSM) |
| 10 | Guardas de rota e papel | `route_guard.dart` | Verificada | `route_guard_test.dart`; TM-015 web |
| 11 | Sessão persistente e logout | `SessionNotifier` | Verificada (web) | TM-004 web; no Android por testar |
| 12 | Eliminar conta (RGPD) | `delete_my_account` | Verificada | TM-012 web; T-DEL na BD; apaga Storage no cliente (melhor esforço) |
| 13 | Bloqueio do email 90 dias depois de eliminar | `deleted_account_emails` | Verificada | TM-005 web |
| 14 | Ecrã de erro de sessão | `/session-error` | Implementada, não testada | |
| 15 | Painel `/admin` com TOTP (aal2) | `features/admin` | Verificada | TM-053 web; T-ADM na BD |

## 2. Cliente

| # | Funcionalidade | Estado | Evidência / nota |
|---|---|---|---|
| 16 | Início com "Precisa de ti", pedidos ativos, "Os teus jardineiros" | Verificada (web) | TM-035 web |
| 17 | Criar pedido em 4 passos (serviço, data, dimensão, morada, fotos, revisão) | Verificada | TM-016 web; T-JOB na BD; RACE-03 (máximo de 2 fotos) |
| 18 | Morada por GPS | Implementada, não testada | Precisa de dispositivo (TM-008 em telemóvel) |
| 19 | Sugestões de morada (Photon, Nominatim) | Implementada, não testada | Bloqueado no ambiente de teste; risco de política (AUD-13) |
| 20 | Mapa para escolher o ponto | Implementada, não testada | Tiles OSM com User-Agent `com.example` e sem atribuição (AUD-12) |
| 21 | Data fixa, flexível e "a combinar" | Verificada | T-JOB; 0073 (expira aos 30 dias) |
| 22 | Urgência e dimensão | Verificada | Campos do pedido; vistas testadas |
| 23 | Editar pedido aberto | Verificada | TM-018 corrigido (W-2, PR #50); T-EDIT |
| 24 | Cancelar pedido (com reabertura) | Verificada | TM-026 web; T-CANC |
| 25 | Propostas recebidas lado a lado, "Recomendada" | Verificada | TM-020 web; `client_proposals_view_test` |
| 26 | Aceitar proposta | Verificada | TM-021 web; RACE-01, RACE-02 |
| 27 | Recusar proposta | Verificada (BD) | `reject_proposal` nas revisões de 02/11 |
| 28 | Pedido sem propostas: alargar a 30 km, ajustar | Verificada | TM-019 web |
| 29 | "Pedir de novo" (24h exclusivo) | Verificada | TM-028 web |
| 30 | Pedido pelo cartão público `/w/:id` | Verificada | TM-029 corrigido (W-1, PR #50) |
| 31 | Trabalho confirmado com WhatsApp e mapa | Parcial | Ecrã verificado na web; abrir WhatsApp e Maps só em telemóvel (TM-030) |
| 32 | Remarcação (propor, aceitar, recusar) | Verificada | TM-027 web; T-RESCH |
| 33 | Confirmar conclusão (automática 48h, 7 dias com relato) | Verificada | TM-023 web; T-EXEC; T-CRON |
| 34 | Reportar problema | Verificada | TM-024 corrigido (W-3) |
| 35 | Avaliar o jardineiro (propaga aos ajudantes) | Verificada | TM-025 web; T-RATE |
| 36 | Aprovar equipa de ajudantes (automática 24h) | Verificada (BD) | T-HELP; cron `process_help_request_deadlines` |
| 37 | Dicas da época e interruptor | Verificada | TM-032 web |
| 38 | Editar perfil do cliente | Implementada, não testada | |

## 3. Jardineiro

| # | Funcionalidade | Estado | Evidência / nota |
|---|---|---|---|
| 39 | Início (pendentes, agendados, próximo trabalho) | Verificada (web) | TM-035 web |
| 40 | Pedidos disponíveis no raio, filtro de categorias | Verificada | T-DISC; pesquisa usa sempre a base gravada (0074) |
| 41 | Pedidos diretos no topo, "Não posso desta vez" | Verificada | TM-028 web |
| 42 | Detalhe da oportunidade (zona aproximada, morada só depois de aceite) | Verificada | TM-033 web; 0043 |
| 43 | Proposta por hora ou valor total, validade, dias | Verificada | TM-034 web; T-PROP; RACE-04 |
| 44 | Proposta com ajudantes e equipamento | Verificada | TM-031 web |
| 45 | Retirar proposta | Verificada | RACE-02 |
| 46 | Limite do plano Grátis (5 trabalhos aceites/mês) | Verificada | TM-040 web; T-PLAN |
| 47 | Trabalhos: Agenda (Hoje, Semana, Mês), Propostas, Histórico | Verificada | TM-035, TM-038 web; testes `agenda_*` |
| 48 | Trabalhos de fora da app e indisponibilidades na Agenda | Verificada | TM-038 web; T-AG |
| 49 | Iniciar com fotos de antes, concluir com fotos de depois | Verificada | TM-036 web; câmara por testar em telemóvel |
| 50 | Trabalho em vários dias | Verificada | TM-037 web |
| 51 | Lembretes 1h antes e 30 min depois | Verificada (BD) | 0072; hora real por testar (TM-042) |
| 52 | Pedir ajudantes, lobby, aceitar com taxa, vagas, retirar | Verificada | TM-031 web; T-HELP; **RACE-06 novo (última vaga)** |
| 53 | Candidatar-se como ajudante, desistir | Verificada | T-HELP; TM-031 |
| 54 | Ecrã do trabalho visto pelo ajudante | Verificada (web) | TM-044 web |
| 55 | Avaliar cliente, ajudantes e responsável | Verificada | TM-025 lado do jardineiro corrigido (PR #52) |
| 56 | Cartão partilhável (QR, imagem, link, PDF no Pro) | Parcial | TM-039 web; nas apps aponta para `projardim.pt` sem `APP_PUBLIC_URL` (AUD-10) |
| 57 | Painel de ganhos (Pro) | Verificada (BD) | `get_my_earnings`; `plan_features_and_earnings_test` |
| 58 | Destaques e redes sociais | Verificada | TM-014 web |
| 59 | Editar perfil (3 secções) | Implementada, não testada | |
| 60 | Cartão frota (OCR local, ativação manual) | Mock / Placeholder | Dados fictícios, sem parceiro; só Pro+ (AUD-28) |

## 4. Comum, notificações e operação

| # | Funcionalidade | Estado | Evidência / nota |
|---|---|---|---|
| 61 | Notificações in-app (38 tipos) | Verificada | Contrato SQL e Dart sem tipos órfãos (12/11); TM-043, TM-044 web (9 tipos navegados) |
| 62 | Aviso no topo com a app aberta (Realtime) | Implementada, não testada | Sem Realtime no ambiente de teste (TM-045) |
| 63 | Push FCM com a app fechada | Parcial | Código e Edge Function feitos; configuração em produção por confirmar (AUD-01) |
| 64 | "Limpar tudo" com "Desfazer" | Verificada | TM-043 web |
| 65 | As minhas avaliações (recebidas e dadas) | Implementada, não testada | Sem teste dedicado |
| 66 | Contacto e suporte (email) | Verificada (web) | TM-049 |
| 67 | Termos e Política (Google Docs) | Parcial | Abrem (TM-049); rascunho sem responsável nem revisão jurídica (AUD-09) |
| 68 | Voltar depois de notificação (fallback ao início do papel) | Verificada (web) | TM-044; Android por testar (TM-048) |
| 69 | Crons (11 jobs) | Verificada (BD local) | T-CRON; na BD viva por confirmar (TM-054) |
| 70 | Versão web (Netlify) | Implementada, não testada nesta auditoria | Deploy manual |
| 71 | Layout largo (tablet, PC) | Verificada (testes) | `app_adaptive_shell_test` |

## 5. Funcionalidades esquecidas, desligadas ou só documentadas

| Funcionalidade | Estado | Nota |
|---|---|---|
| Mensagens / mini-chat | Obsoleta | Rotas apagadas a 18/10; contradiz "contacto só por WhatsApp" |
| Filtros "prazo" e "tamanho" nos pedidos disponíveis | Obsoleta | Já não aparecem no código |
| "Ver o local primeiro" (visita paga) | Planeada | Fase 2 (decidido 22/10) |
| Painel admin fases 2 e 3 | Planeada | `admin-dashboard` |
| Verificação de identidade do jardineiro | Planeada | Vem com o selo Pro (decidido 22/10) |
| Feed de descoberta de profissionais | Planeada | Não existe código |
| Trabalhos recorrentes do cliente | Planeada | Só a Agenda do jardineiro tem repetição |
| Integração do A12 (stepper Pedido · Proposta · Equipa · No dia · Feito) | Parcial | `JobFlowStepper` usado em 4 ecrãs; STATUS.md ainda diz "por integrar" |
| Visitas e funil do cartão | Implementada | Só no SQL Editor (`worker_card_funnel`) |
| Admin: mudar plano manualmente | Verificada | Pagamento fora da app |

## Contagem

71 funcionalidades inventariadas nas secções 1 a 4:

| Estado | N.º | % |
|---|---|---|
| Verificada (com as ressalvas acima: fora de dispositivo e fora da BD viva) | 53 | 75% |
| Implementada, não testada | 12 | 17% |
| Parcial | 5 | 7% |
| Mock / Placeholder | 1 | 1% |
| Quebrada | 0 | 0% |

"Verificada" aqui é sempre **fora de um telemóvel e fora da produção**. Com o critério do lançamento (fluxo visto a funcionar no Android contra a BD viva), a percentagem verificada é **0%**.
