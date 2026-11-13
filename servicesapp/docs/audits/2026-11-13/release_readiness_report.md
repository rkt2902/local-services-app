# Relatório de prontidão para lançamento: ProJardim (13/11/2026)


> **Atualização 13/11 (tarde):** o Henrique confirmou que push, email (SMTP), login com Google, pesquisa de moradas e mapa estão configurados e a funcionar em produção. AUD-01, AUD-02 e a parte Google do AUD-06 passam a **confirmado pelo dono** (não verificado por mim: continuam nos testes manuais). AUD-05 e AUD-12 foram corrigidos no PR #53. Ficam 6 P1 abertos.

**Estado auditado:** `main` em `5cd9c59` (último merge: PR #52), migrations `0001` a `0075`.
**Âmbito:** código Flutter, migrations, Edge Function, configuração Android e iOS, testes automáticos, documentação, histórico Git. Auditoria só de leitura: nenhum comportamento da app nem da BD foi alterado, nenhuma migration aplicada, nada tocado em produção. Única adição: um teste novo da BD (`supabase/tests/audit/40_help_slot_race.sh`).
**Não acessível daqui:** BD de produção, painel do Supabase, Firebase, Google Play, dispositivos. Tudo o que depende disso está marcado **NÃO VERIFICADO**.

## Decisão: **NO-GO** hoje · **CONDITIONAL GO** depois do plano de 2 a 3 semanas

**A ProJardim pode ser lançada hoje? Não.**

Não é por o código estar mau. É o contrário: o código e as regras do servidor estão sólidos e bem testados. O problema é que **nada foi visto a funcionar num telemóvel com a build de release e a produção**, e várias peças sem as quais a app não serve a utilizadores reais (push, email, assinatura, backups, textos legais) estão por configurar ou por confirmar.

## Estado geral

| Área | Estado |
|---|---|
| Regras de negócio e segurança no servidor | **Forte.** RLS em 28/28 tabelas, escritas só por RPC, identidade por `auth.uid()`, 182 asserções e 7 corridas a passar, 0 vulnerabilidades encontradas |
| Código Flutter | **Bom.** `flutter analyze` 0 issues, 645 testes a passar, design system respeitado (0 cores soltas), 0 SnackBars |
| Fluxos | **Completos.** 71 funcionalidades inventariadas, 0 quebradas conhecidas, 53 verificadas fora de dispositivo |
| Integrações reais (push, email, OAuth, moradas, mapa) | **A funcionar, segundo o dono (13/11)**; por ver nos testes manuais |
| Build de release e lojas | **Por fazer** (assinatura, permissões, ficha, Data safety) |
| Operação (monitorização, backups, rollback) | **Inexistente ou por confirmar** |
| Legal | **Rascunho** sem responsável nem revisão jurídica |

## Números

| Indicador | Valor |
|---|---|
| Funcionalidades inventariadas | 71 |
| Verificadas fora de dispositivo (BD local + web E2E ou testes Flutter) | 53 (75%) |
| Verificadas num Android contra produção | **0 (0%)** |
| Implementadas, não testadas / parciais / mock / quebradas | 12 / 5 / 1 / 0 |
| `flutter analyze` | 0 issues |
| `flutter test` | 645 passam, 0 falham |
| BD: `10_flows.sql` / `30_findings.sql` | 162/162 / 20/20 PASS |
| BD: corridas | RACE-01 a 04 e 06 PASS; 05 e 07 informativos e coerentes |
| Segredos no repositório e no histórico | 0 |
| Problemas P0 / P1 / P2 / P3 | **0 / 10 / 11 / 8** |
| Testes manuais pendentes | 33 (P0 10, P1 16, P2 7), mais os de iOS bloqueados |

## O que bloqueia o lançamento (P1, todos antes de publicar)

| ID | O quê | Quem |
|---|---|---|
| ~~AUD-01~~ | Push FCM: confirmado pelo dono a 13/11 | |
| ~~AUD-02~~ | Email real: confirmado pelo dono a 13/11 | |
| AUD-03 | Nenhum teste num Android físico nem com a build de release | Henrique |
| AUD-04 | Release assinado com chave de debug sem aviso; build sem `--dart-define` arranca sem backend | Código (S) |
| ~~AUD-05~~ | `READ_MEDIA_IMAGES` removida no PR #53 | |
| AUD-06 | Google confirmado pelo dono; fica Sign in with Apple, só para iOS | iOS (fase 2) |
| AUD-07 | Sem monitorização de erros | Código (S a M) |
| AUD-08 | Plano Free do Supabase sem backups recuperáveis | Henrique |
| AUD-09 | Termos e Política sem responsável, sem revisão jurídica, desatualizados | Henrique |
| AUD-10 | Links e QR das apps apontam para `projardim.pt` (posse por confirmar) | Henrique |

## Maiores riscos

1. **Lançar sem ter visto a app num telemóvel.** Câmara, GPS, permissões, WhatsApp, Maps, push, voltar do Android e a build minificada nunca foram exercitados. É onde costumam estar os erros que os testes não apanham.
2. **Perda de dados sem volta.** As migrations são aplicadas à mão no SQL Editor e o plano Free não tem backups recuperáveis.
3. **Jardineiros não recebem pedidos.** Sem push, o lado da oferta morre nas primeiras semanas.
4. **Utilizadores presos fora da conta.** O SMTP de teste do Supabase só envia alguns emails por hora.
5. **Erros invisíveis.** Sem monitorização, só se sabe dos crashes pelas avaliações da loja.
6. **Serviços gratuitos de moradas e mapa** (Photon, Nominatim, tiles OSM) sem garantia (AUD-13); a política dos tiles ficou cumprida no PR #53 (AUD-12).

## Segurança (resumo de `security_audit.md`)

- **Sem vulnerabilidades exploráveis encontradas.** Testes negativos desta auditoria: mudar o papel, apagar ou repor a conta, raio fora do limite, avaliação, notificação e proposta forjadas por INSERT, leituras como `anon`: tudo recusado.
- Fotos de pedidos legíveis por URL público sem sessão (decisão, documentada na Política) (AUD-14).
- Regras de senha e anti-abuso só no cliente até se confirmar o painel do Auth (AUD-18).
- Eliminação de conta completa no servidor (o `STATUS.md` diz o contrário e está desatualizado).
- **"A ausência de erros conhecidos não é prova de segurança"**: a BD viva não é comparada com o repositório desde 16/10 (TR-26).

## O que está efetivamente funcional (fora de dispositivo)

Registo, login, papel, setup do jardineiro, eliminar conta, admin com TOTP; criar, editar e cancelar pedidos; descoberta por raio com morada protegida; propostas por hora e valor total, com dias, validade e equipa; aceitar, recusar, retirar; pedidos diretos e pelo cartão; remarcação; iniciar, vários dias, concluir, confirmar, reportar, avaliar em todos os sentidos; ajudantes de ponta a ponta (incluindo a última vaga disputada); Agenda; planos e limite do Grátis; notificações in-app (38 tipos, sem órfãos); cartão partilhável; 11 crons.

## O que está só parcialmente implementado

Push (código feito, configuração por confirmar); login Google (código feito, configuração por fazer) e Facebook (escondido); cartão partilhável nas apps (domínio); Termos e Política (rascunho); cartão frota (demo).

## O que precisa de testes manuais

`manual_test_plan.md`: 10 P0 (build de release, registo com email, recuperar senha, pedido com GPS e câmara, propor e aceitar entre 2 aparelhos, push, iniciar e concluir com fotos, WhatsApp e Maps, eliminar conta, crons na BD viva), 16 P1 e 7 P2. iOS bloqueado.

## O que ainda não foi testado de todo

Push, Realtime, SMTP, OAuth, Storage real, GPS, câmara, moradas e mapa com os serviços reais, a build minificada, iOS, e a BD viva desde 16/10.

## Funcionalidades esquecidas ou mal documentadas

- O `STATUS.md` diz que o A12 está "por integrar", mas o `JobFlowStepper` já está em 4 ecrãs; e diz que eliminar conta não apaga tudo, mas a 0066 e a 0070 resolveram (AUD-19).
- A `0075` está no `main` por aplicar (AUD-11).
- Cartão frota visível como benefício do Pro+ sem parceiro (AUD-28).
- ~~O mapa ainda usa o User-Agent `com.example.servicesapp` e não mostra a atribuição do OpenStreetMap (AUD-12).~~ Corrigido no PR #53.
- O pedido falava de "cerca de 22 tipos de notificação": são **38**, todos implementados e com navegação.
- O pedido falava de preço/hora único com horas mínimas e máximas: desde a 0058 há preço por hora **ou** valor total, com dias e validade.

## Funcionalidades futuras a adiar

Mini-chat (não recomendado: contraria o WhatsApp), feed de descoberta, trabalhos recorrentes do cliente, visita paga, verificação de identidade, admin fases 2 e 3, iOS (para a 1.1). Detalhe em `pending_features.md`.

## Melhorias indispensáveis

As P1 ainda abertas (AUD-03, 04, 07, 08, 09, 10) e, das P2: aplicar a 0075, tirar o Nominatim das sugestões, regras de senha no painel, atualizar a documentação, esconder o cartão frota.

## Sequência ideal até ao lançamento

1. **Dia 1 (Henrique, 2 h):** dump da BD, plano Pro ou dump diário, aplicar a 0075, regras de senha e limites no painel, SMTP e templates.
2. **Dia 1 a 2 (código, um PR sem migrations):** AUD-04, 05, 07, 12, 17, 19, flags do Google e do cartão frota, Nominatim fora das sugestões.
3. **Dia 2 a 3 (Henrique):** Firebase e Edge Function, domínio ou Netlify, Google OAuth ou botão escondido.
4. **Dia 3 a 4:** build de release assinada, testes manuais P0 e P1 num Android, comparar o schema da BD viva.
5. **Semana 2:** Termos e Política finais com advogado, DPAs, página de eliminação.
6. **Semana 2 a 4:** conta Play, ficha, Data safety, teste fechado (14 dias se a conta for pessoal), produção.
7. **Depois:** iOS, testes da BD no CI, fotos privadas, P3.

Com os passos 1 a 5 feitos e os testes P0 a passar, a recomendação passa a **CONDITIONAL GO** para Android (condição: testes P1 sem falhas graves e Crashlytics ativo na primeira semana).

## Critérios de aprovação (secção 15 do pedido)

| # | Critério | Estado |
|---|---|---|
| 1 | Sem P0 conhecidos | ✓ |
| 2 | Sem P1 sem mitigação | ✗ 10 P1 abertos |
| 3 | Fluxos essenciais verificados | ✗ só fora de dispositivo |
| 4 | Políticas de segurança validadas | ✓ na BD local; ? na BD viva |
| 5 | Sem problemas críticos de privacidade | ✓ técnicos; ✗ legais (AUD-09) |
| 6 | Testes automáticos passam | ✓ |
| 7 | Testes manuais críticos concluídos | ✗ 0 de 10 |
| 8 | Builds de lançamento verificadas | ✗ |
| 9 | Sem funcionalidades essenciais escondidas ou incompletas | ✗ push e email |
| 10 | Requisitos das lojas e legais tratados | ✗ |

## Documentos desta auditoria

`feature_inventory.md`, `security_audit.md`, `flow_test_matrix.md`, `manual_test_plan.md`, `pending_features.md`, `launch_checklist.md`, `remediation_plan.md` (todos os problemas com evidência, impacto, solução e esforço).
