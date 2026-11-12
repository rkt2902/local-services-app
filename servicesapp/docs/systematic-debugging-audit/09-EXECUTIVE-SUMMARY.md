# 09. Resumo executivo

**Data:** 12/11/2026 · **Estado auditado:** ramo do PR #47 (`7c9f539`) = `main` + migrations 0071 a 0073 · **Metodologia:** skill `systematic-debugging` (reproduzir, evidência, causa raiz, hipótese, teste) · **Âmbito:** só documentação e testes; nenhum comportamento da app nem da BD foi alterado; nenhuma migration aplicada; nada tocado em produção.

## Respostas às quatro perguntas

**1. O que existe realmente?** Uma app Flutter com cerca de 50 rotas, 13 features, 59 RPCs chamadas, 11 jobs de cron, push por Edge Function e um painel de admin com segundo fator. Inventariei **80 fluxos** (02), dos 2 papéis principais, ajudantes, admin e processos automáticos. Não encontrei funcionalidades escondidas ou ligadas a nada; as desligadas de propósito estão listadas em 02.

**2. O que foi efetivamente testado e funciona?** A camada de regras (BD com RLS, RPCs, triggers, crons) foi executada de verdade numa BD local montada com todas as migrations, a fazer de app. A lógica e as vistas Flutter passaram nos 621 testes e o `flutter analyze` está a zero. **Nenhum ecrã foi aberto num telemóvel**: a UI, o Auth, o push, o Storage real, o GPS e as APIs externas estão por validar (05).

**3. O que pode falhar, porquê e com que impacto?** 14 registos (04). Os que importam: a app já está à frente da BD viva (0067 a 0073 por aplicar); uma corrida entre "Retirar" e "Aceitar" deixa um trabalho confirmado sem jardineiro; a API deixa criar um pedido "já iniciado"; e a pesquisa de pedidos aceita coordenadas de qualquer sítio e de qualquer papel. Nenhum crítico, nenhuma fuga de morada exata nem de telefone.

**4. O que tenho de testar manualmente antes de produção?** Os 7 testes P0 de 05 (TM-012 eliminar conta, TM-016 criar pedido, TM-021 aceitar, TM-034 propor, TM-036 iniciar e concluir, TM-046 push, TM-054 crons na BD viva) e, logo a seguir, os 26 P1.

## Números

| Indicador | Valor |
|---|---|
| Fluxos identificados | 80 |
| Fluxos executados (backend posto a correr com asserções) | 55 |
| Fluxos aprovados (TESTADO AUTOMATICAMENTE — PASSOU) | 43 |
| Fluxos com falhas (TESTADO AUTOMATICAMENTE — FALHOU) | 12 |
| Fluxos só analisados estaticamente | 18 |
| Fluxos bloqueados | 7 |
| Fluxos não testados | 0 |
| Fluxos testados manualmente | 0 (sem dispositivo nesta auditoria) |
| Asserções na BD | 162 (156 passam) + 17 de reprodução + 5 de concorrência |
| Testes Flutter | 621 passam, 0 falham |
| `flutter analyze` | 0 issues |
| Bugs por severidade | Critical 0 · High 1 · Medium 3 · Low 10 |
| Bugs confirmados / suspeitos | 13 / 1 |
| Testes manuais pendentes | 56 (P0 7 · P1 26 · P2 17 · P3 6) |

"Aprovado" aqui quer dizer: regras do servidor e lógica da app verificadas. Não quer dizer que o ecrã foi visto a funcionar.

## Principais riscos técnicos

1. **App e BD fora de passo (BUG-014).** Sete migrations por aplicar enquanto o código já depende delas. É o maior risco para a próxima publicação e o mais barato de resolver.
2. **Corridas sem bloqueio (BUG-001, BUG-005).** A maior parte das RPCs bloqueia bem (RACE-01 e RACE-04 passam); `withdraw_proposal` e o limite de fotos não.
3. **Regras só na UI (BUG-002, 003, 006, 007, 008).** A chave pública vem dentro da app, por isso tudo o que a BD aceita pode ser feito por quem chamar a API à mão. As regras de negócio graves já estão no servidor; faltam estas.
4. **Privacidade da descoberta (BUG-004).** A morada exata está protegida, mas a zona, a descrição e o `client_id` de todos os pedidos abertos podem ser recolhidos.
5. **Integrações nunca validadas aqui:** push FCM, OAuth, SMTP, Realtime, pg_cron real, Netlify.

## Funcionalidades críticas ainda não validadas

Registo e login reais (incluindo social), confirmação de email, recuperação de senha em release, push com a app fechada, fotos com a câmara, GPS e moradas, eliminação de conta de ponta a ponta, crons agendados na BD viva, navegação ao tocar em notificações.

## Recomendação de prontidão para produção

**Não pronta para publicar uma build nova hoje**, por dois motivos objetivos: (1) a BD viva não tem as migrations de que o código depende; (2) nenhum dos fluxos P0 foi visto a funcionar num dispositivo nesta auditoria. A base é sólida: as regras de servidor dos fluxos principais passaram em 156 de 162 asserções e os 6 falhanços são achados de prioridade P1 a P3, não falhas do caminho principal.

Caminho curto até "pronta":

1. Aplicar 0067 a 0073 por ordem (15 min).
2. Correr TM-054 (crons na BD viva, só leitura).
3. Fazer os 7 testes P0 num Android real.
4. Corrigir BUG-001 e BUG-002 numa 0074 (cerca de 1h com testes).
5. Fazer os P1 de autenticação e push.

## Documentos

- 01 visão geral, 02 inventário, 03 resultados por fluxo, 04 bugs, 05 testes manuais, 06 dependências e regressão, 07 lacunas, 08 correções, 10 matriz.
- `evidence/`: saídas dos comandos.
- `supabase/tests/audit/`: testes da BD (só locais).
