# Plano de correção (13/11/2026)


> **Atualização 13/11 (tarde):** o Henrique confirmou que push, email (SMTP), login com Google, pesquisa de moradas e mapa estão configurados e a funcionar em produção. AUD-01, AUD-02 e a parte Google do AUD-06 passam a **confirmado pelo dono** (não verificado por mim: continuam nos testes manuais). AUD-05 e AUD-12 foram corrigidos no PR #53. Ficam 6 P1 abertos.

Todos os problemas encontrados nesta auditoria, por severidade, e a ordem recomendada para os resolver. **Nada foi corrigido durante a auditoria**: só foi acrescentado um teste novo da BD (`supabase/tests/audit/40_help_slot_race.sh`).

Severidade: **P0** bloqueador crítico, **P1** grave, **P2** médio, **P3** baixo (definições do pedido de auditoria).
Esforço: S (até 1 h), M (meio dia), L (1 a 3 dias), XL (mais).
"Quem": **H** = só o Henrique (painel, contas, dispositivos, dinheiro, decisões); **C** = código, pode ser feito por um PR.

## Resumo

| Severidade | N.º | Antes do lançamento |
|---|---|---|
| P0 | 0 conhecidos | |
| P1 | 10 (3 confirmados pelo dono, 2 corrigidos, 5 abertos e 1 só para iOS) | os abertos |
| P2 | 11 | 6 (mais 2 recomendados) |
| P3 | 8 | nenhum |

Não encontrei nenhum P0 no código. Os P1 são quase todos **configuração, verificação e legal**, e é isso que hoje impede o lançamento.

---

## P1

### AUD-01 · Push FCM em produção por configurar ou por verificar · CONFIRMADO PELO DONO (13/11)
- **Funcionalidade:** notificações com a app fechada (novos pedidos, propostas, aceitação, lembretes).
- **Evidência:** `STATUS.md` ("Firebase e push FCM... É o bloqueador nº 1 para jardineiros reais"); `google-services.json` fora do repositório (correto) e sem confirmação de existir num build; Edge Function `send-push` e segredos `FCM_SERVICE_ACCOUNT`/`PUSH_WEBHOOK_SECRET`/Vault sem confirmação de deploy. **NÃO VERIFICADO.**
- **Reproduzir:** instalar a app de release, fechar, criar um pedido noutra conta na zona: não chega nada.
- **Impacto:** o jardineiro só vê pedidos quando abre a app. Os pedidos diretos (24h) e os lembretes perdem o sentido. A cliente não sabe que recebeu propostas.
- **Solução:** `SETUP.md` passo 4 e `push_notifications.md`; depois TM-046 e TM-047.
- **Esforço:** M · **Quem:** H · **Antes do lançamento:** sim.

### AUD-02 · Email real por configurar ou por verificar (SMTP, recuperação, confirmação) · CONFIRMADO PELO DONO (13/11)
- **Funcionalidade:** recuperação de senha, confirmação de email.
- **Evidência:** `STATUS.md` ("Emails pelo SMTP de teste do Supabase, com limite baixo"); o template de recuperação tem de usar `{{ .Token }}` porque a app pede um código. **NÃO VERIFICADO.**
- **Reproduzir:** pedir 3 ou 4 recuperações de senha na mesma hora com o SMTP por omissão.
- **Impacto:** quem se esquece da senha fica sem conta; sem confirmação de email qualquer pessoa regista contas com emails de outros.
- **Solução:** SMTP Brevo, templates "Reset password" e "Confirm signup" com `{{ .Token }}`, ligar "Confirm email". TM-003 e TM-009 num telemóvel.
- **Esforço:** S a M · **Quem:** H · **Antes do lançamento:** sim.

### AUD-03 · Nada validado num telemóvel nem com a build de release
- **Funcionalidade:** todas.
- **Evidência:** a auditoria de 12/11 e esta correram na BD local e na web; os testes no Genymotion estão em pausa desde 13/11 (falta o projeto e o APK nesse PC). Nenhuma build `--release` foi instalada e testada.
- **Impacto:** câmara, GPS, permissões, WhatsApp, Maps, push, voltar do Android, ProGuard/R8 e o comportamento em release estão por ver. Um erro aqui só aparece com utilizadores.
- **Solução:** `manual_test_plan.md`, bloco P0 (10 testes), num Android físico com a build de release e a BD de produção com contas de teste (decisão de 13/11).
- **Esforço:** M (meio dia de testes) · **Quem:** H · **Antes do lançamento:** sim.

### AUD-04 · Build de release sem rede de segurança (assinatura e `--dart-define`) · CORRIGIDO no PR #53
- **Funcionalidade:** publicação.
- **Evidência:** `android/app/build.gradle.kts:59-65` cai para `signingConfigs.getByName("debug")` sem `key.properties`; `lib/main.dart:17-20` inicializa o Supabase com `SupabaseConfig.url` vazio quando falta o `--dart-define`, sem aviso.
- **Reproduzir:** `flutter build appbundle --release` sem `key.properties` nem `--dart-define`: o build passa, a Play recusa o AAB (chave debug) ou, pior, uma build interna sai sem backend e mostra só erros.
- **Impacto:** perda de tempo no lançamento; risco de distribuir uma build partida a testers.
- **Solução:** no `release`, falhar o Gradle se `key.properties` não existir; em `main.dart`, se `SupabaseConfig.url` ou `anonKey` estiverem vazios em release, mostrar um ecrã de erro claro (ou `assert` + verificação no CI do comando de build).
- **Esforço:** S · **Quem:** C · **Antes do lançamento:** sim.

### AUD-05 · Permissão `READ_MEDIA_IMAGES` desnecessária · CORRIGIDO no PR #53 (falta TR-13 num Android)
- **Funcionalidade:** fotos do pedido, avatar, antes e depois.
- **Evidência:** `android/app/src/main/AndroidManifest.xml:5-6`. O `image_picker` 1.2 usa o Photo Picker do Android, que não precisa desta permissão.
- **Impacto:** a política "Photo and Video Permissions" da Google Play só aceita `READ_MEDIA_IMAGES` para apps cujo uso principal é aceder a toda a galeria; aqui leva a declaração extra e rejeição provável.
- **Solução:** remover `READ_MEDIA_IMAGES` (e avaliar `READ_EXTERNAL_STORAGE`), testar a escolha de fotos em Android 13+ e em Android 10 a 12.
- **Esforço:** S · **Quem:** C, depois H testa · **Antes do lançamento:** sim.

### AUD-06 · Login social: Google sem configuração confirmada; Apple em falta para iOS · Google CONFIRMADO PELO DONO (13/11); fica só a parte iOS
- **Funcionalidade:** "Continuar com Google".
- **Evidência:** `lib/features/auth/presentation/widgets/social_sign_in_buttons.dart:32` mostra sempre o botão; `STATUS.md` diz "falta configurar; os botões dão erro". **NÃO VERIFICADO** no painel. A App Store (regra 4.8) exige "Sign in with Apple" quando há login com Google.
- **Impacto:** o primeiro botão que muita gente toca dá erro; o iOS é recusado na revisão.
- **Solução:** configurar o Google (SETUP passo 7) e testar TM-006, **ou** esconder o botão por `--dart-define` como o Facebook até estar pronto. Para iOS: Sign in with Apple ou esconder o login social no iOS.
- **Esforço:** S (esconder) a M (configurar) · **Quem:** H (configuração) e C (flag) · **Antes do lançamento:** sim.

### AUD-07 · Sem monitorização de erros em produção · CORRIGIDO no PR #53 (Crashlytics; falta ativar no Firebase e testar)
- **Funcionalidade:** operação.
- **Evidência:** nenhum `FlutterError.onError`, `PlatformDispatcher.instance.onError`, Crashlytics ou Sentry em `lib/` nem no `pubspec.yaml`.
- **Impacto:** crashes e erros não tratados nos telemóveis dos utilizadores ficam invisíveis; só se sabe pelas avaliações da loja.
- **Solução:** Firebase Crashlytics (o Firebase já entra pelo push) com `FlutterError.onError` e `PlatformDispatcher.instance.onError`, sem dados pessoais nas mensagens. Atualizar a Política.
- **Esforço:** S a M · **Quem:** C, depois H ativa no Firebase · **Antes do lançamento:** sim.

### AUD-08 · Backups e plano do Supabase · FEITO a 13/11 (backup diário por GitHub Action; falta testar um restauro)
- **Funcionalidade:** dados de produção.
- **Evidência:** `ARCHITECTURE.md` secção 16, ponto 7: projeto `twpflvcoyeiysnychkom` no plano Free (dump de 16/10). O plano Free não tem backups recuperáveis pelo painel nem PITR. **NÃO VERIFICADO** se o plano mudou.
- **Impacto:** um erro numa migration aplicada à mão no SQL Editor (o processo atual) ou um `DELETE` errado não tem volta.
- **Solução:** passar ao Pro antes do lançamento (backups diários de 7 dias) **ou**, no mínimo, `supabase db dump` diário por GitHub Action para um sítio privado, e um procedimento escrito de restauro testado uma vez. Fazer um dump antes de cada migration.
- **Esforço:** S (plano Pro) a M (dump automático) · **Quem:** H · **Antes do lançamento:** sim.

### AUD-09 · Termos e Política: responsável, revisão jurídica e versões desatualizadas
- **Funcionalidade:** legal.
- **Evidência:** `projardim/legal/notas-antes-de-publicar.md` (sem nome, NIF, morada, decisão de 21/10); secção 3.7 da Agenda por publicar; visitas ao cartão, Photon/OSM e dicas da época em falta na versão publicada (`STATUS.md`, gaps); DPAs por aceitar (NÃO VERIFICADO); Livro de Reclamações e RAL por ver.
- **Impacto:** o RGPD (art. 13.º) exige a identidade e o contacto do responsável; as lojas pedem uma Política que bata com a ficha de dados; risco legal e de rejeição.
- **Solução:** fechar a forma jurídica, preencher a secção 1, publicar a versão com a Agenda, rever com advogado (uma hora), aceitar os DPAs, página web de eliminação de conta para a Play.
- **Esforço:** M · **Quem:** H · **Antes do lançamento:** sim.

### AUD-10 · Domínio placeholder nos links e QR das apps · FEITO a 13/11 (`projardim.pt`)
- **Funcionalidade:** cartão partilhável, QR, link `/w/:id`.
- **Evidência:** `lib/core/config/app_links.dart:17` e `:70`: sem `APP_PUBLIC_URL`, as apps usam `https://projardim.pt`. **Posse do domínio NÃO VERIFICADA.**
- **Impacto:** se o domínio não for do Henrique, cada QR e link partilhado por jardineiros leva a um site de terceiros (ou a nada). QR impressos não se corrigem depois.
- **Solução:** registar o domínio e passar `APP_PUBLIC_URL` no build de release, ou usar o endereço do Netlify até lá. Pôr isto na lista de `--dart-define` obrigatórios (AUD-04).
- **Esforço:** S · **Quem:** H · **Antes do lançamento:** sim.

---

## P2

### AUD-11 · Migration 0075 por aplicar · APLICADA a 13/11
- **Evidência:** cabeçalho "NOVA, NÃO APLICADA"; `migrations-state` (memória do projeto). **NÃO VERIFICADO** na BD viva.
- **Impacto:** pela API ainda se cria um pedido sem morada (a app já não deixa) e o painel admin conta contas eliminadas.
- **Solução:** aplicar no SQL Editor depois de um dump. **Esforço:** S · **Quem:** H · **Antes:** sim.

### AUD-12 · Mapa OSM com User-Agent de exemplo e sem atribuição · CORRIGIDO no PR #53
- **Evidência:** `lib/features/client/presentation/widgets/job_location_picker.dart:377-380` (`userAgentPackageName: 'com.example.servicesapp'`); nenhum `RichAttributionWidget` nem texto "© OpenStreetMap" em `lib/`.
- **Impacto:** a política dos tiles do OSM bloqueia User-Agents genéricos e exige atribuição visível (licença ODbL). Mapa em branco possível em produção.
- **Solução:** `userAgentPackageName: 'pt.projardim.app'` e `RichAttributionWidget` com "© OpenStreetMap contributors". **Esforço:** S · **Quem:** C · **Antes:** sim.

### AUD-13 · Pesquisa de moradas dependente de serviços gratuitos sem garantia (a funcionar hoje, segundo o dono; o risco é de escala) · parte curta CORRIGIDA no PR #53 (Nominatim só na pesquisa explícita)
- **Evidência:** `lib/core/services/geocoding_service.dart:214` usa o Nominatim como alternativa às sugestões ao escrever quando o Photon falha. A política do Nominatim proíbe autocompletar e limita a 1 pedido por segundo por aplicação; o Photon público não tem SLA. O W-2 de 12/11 mostrou o efeito de uma falha (pedidos sem morada).
- **Impacto:** com crescimento, sugestões e morada por GPS falham ou são bloqueadas.
- **Solução:** curto prazo, não usar o Nominatim nas sugestões (só no botão "procurar") e garantir a morada escrita à mão; médio prazo, fornecedor com contrato (Google Places, Mapbox, ou Photon próprio).
- **Esforço:** S (curto) / M (fornecedor) · **Quem:** C e H (orçamento) · **Antes:** a parte curta, sim.

### AUD-14 · Fotos de pedidos abertas a quem tiver o URL
- **Evidência:** `storage.buckets`: `avatars` e `job-photos` com `public = true`; TM-050 de 12/11.
- **Impacto:** fotos do jardim e de antes/depois na morada ficam acessíveis sem sessão a quem tiver o link (os caminhos têm UUIDs, por isso não se adivinham). Documentado na Política.
- **Solução:** decisão. Manter (documentado) ou passar `job-photos` a privado com URLs assinadas (exige mexer em todos os sítios que mostram fotos). **Esforço:** M · **Quem:** H decide, C faz · **Antes:** não, se a Política o disser.

### AUD-15 · iOS não está pronto para a App Store
- **Evidência:** sem conta Apple; `ios/Runner/` sem `Runner.entitlements` (push `aps-environment`), sem `PrivacyInfo.xcprivacy` da app; Sign in with Apple em falta (AUD-06); `IPHONEOS_DEPLOYMENT_TARGET = 15.0` e bundle `pt.projardim.app` estão bem.
- **Impacto:** sem push no iPhone; revisão recusada.
- **Solução:** lançar primeiro só Android e tratar o iOS numa segunda fase. **Esforço:** L · **Quem:** H e C · **Antes:** não (se o lançamento for só Android).

### AUD-16 · Testes da BD fora do CI; ecrãs sem testes de integração
- **Evidência:** `.github/workflows/ci.yml` só corre `flutter analyze` e `flutter test`; os 162 + 20 testes da BD e as corridas só correm à mão; nenhum `integration_test/`.
- **Impacto:** uma migration nova pode partir um fluxo e só se descobre na BD viva, que não tem backups (AUD-08).
- **Solução:** job de CI com Postgres 16 em serviço que corre `run.sh`, `30_findings.sql`, `20_concurrency.sh` e `40_help_slot_race.sh`. **Esforço:** M · **Quem:** C · **Antes:** recomendado.

### AUD-17 · Fonte descarregada em runtime · CORRIGIDO no PR #53
- **Evidência:** `lib/core/theme/app_theme.dart:43-45` usa `GoogleFonts.plusJakartaSans...` sem a fonte nos assets.
- **Impacto:** no primeiro arranque sem rede a app usa a fonte do sistema; o IP vai à Google (a Política tem de o dizer).
- **Solução:** pôr os `.ttf` em `assets/fonts` e `GoogleFonts.config.allowRuntimeFetching = false`. **Esforço:** S · **Quem:** C · **Antes:** recomendado.

### AUD-18 · Regras de senha e anti-abuso só no cliente · senha no painel FEITA a 13/11
- **Evidência:** `password_policy.dart` valida na app; o mínimo do Supabase Auth, os limites de taxa e o CAPTCHA estão no painel. **NÃO VERIFICADO.**
- **Impacto:** pela API dá para criar contas com senha fraca e em massa (contas falsas a fazer propostas ou pedidos).
- **Solução:** no painel: mínimo 8, exigir letras e números, limites de taxa, Turnstile/hCaptcha no registo (a app tem de enviar o token). **Esforço:** S (painel) / M (CAPTCHA) · **Quem:** H e C · **Antes:** a parte do painel, sim.

### AUD-19 · Documentação de estado desatualizada · CORRIGIDO no PR #53
- **Evidência:** `STATUS.md` diz que eliminar conta "não apaga tudo" (corrigido nas 0066 e 0070, ver `security_audit.md` 4.6) e "Próxima: 0075"; `ARCHITECTURE.md` secção 7 diz "Próxima migration: 0066" e não tem a 0075; `STATUS.md` diz que o A12 está "por integrar" mas o `JobFlowStepper` já está em 4 ecrãs.
- **Impacto:** decisões tomadas sobre premissas erradas (por exemplo, achar que o RGPD está incompleto ou que falta integrar o A12).
- **Solução:** atualizar `STATUS.md`, `ARCHITECTURE.md` e `supabase/migrations/README.md`. **Esforço:** S · **Quem:** C · **Antes:** sim (barato).

### AUD-20 · Telefone sem validação no servidor · 0076 APLICADA a 13/11
- **Evidência:** teste desta auditoria: `update profiles set phone='1'` como o próprio é aceite.
- **Impacto:** só pela API; o link de WhatsApp da própria conta fica partido.
- **Solução:** `CHECK` com o mesmo formato de `phone_utils.dart` (só depois de limpar valores antigos). **Esforço:** S · **Quem:** C (migration 0076) · **Antes:** não.

### AUD-28 · Cartão frota é uma demonstração · DECIDIDO 13/11: fica como está (decisão do Henrique)
- **Evidência:** `STATUS.md`: dados fictícios, ativação manual por SQL, sem parceiro; visível como benefício do Pro+ no Perfil.
- **Impacto:** um jardineiro Pro+ pode pedir um cartão que não existe.
- **Solução:** esconder até haver parceiro (flag), ou deixar só para o pitch fora da build pública. **Esforço:** S · **Quem:** H decide · **Antes:** sim, se houver Pro+ no lançamento.

---

## P3

| ID | Título | Evidência | Solução | Esf. |
|---|---|---|---|---|
| AUD-21 (0076, aplicada) | 14 chaves estrangeiras sem índice | ex. `job_requests(direct_worker_id)` lido pelo cron a cada 5 min | índices numa migration futura quando houver volume | S |
| AUD-22 (corrigido, PR #58) | `debugPrint` também escreve em release | 15 chamadas em `lib/` | trocar por um logger que só escreve em debug ou para o Crashlytics | S |
| AUD-23 | Ficheiros de UI muito grandes | `worker_my_job_detail_view.dart` 2739 linhas, `worker_edit_profile_view.dart` 2375 | partir quando se mexer neles, não antes do lançamento | L |
| AUD-24 | Dependências atrás e 16 KB do ML Kit | `flutter pub outdated`; ML Kit 0.15 | atualizar depois do lançamento; verificar 16 KB no AAB antes | M |
| AUD-25 (imagens corrigidas, PR #58) | Lista de pedidos do cliente sem paginação; 21 `Image.network` sem `cacheWidth` | `job_repository.dart:155` | imagens: avatares e miniaturas descodificados no tamanho certo (`network_image_sizes.dart`); paginar quando um cliente tiver dezenas de pedidos (por fazer) | S |
| AUD-26 (corrigido, PR #58) | Botões abaixo de 48 px | remover foto (26 px), contador de ajudantes (36 px) (`STATUS.md`) | aumentar a área de toque | S |
| AUD-27 (corrigido) | `allowBackup` por omissão | `AndroidManifest.xml` sem `android:allowBackup` | `android:allowBackup="false"` ou regras de backup sem as preferências da sessão | S |
| AUD-29 (0076, aplicada) | Grants por omissão do `anon` incluem `TRUNCATE` | `information_schema.role_table_grants` | `REVOKE TRUNCATE ... FROM anon, authenticated` numa migration futura | S |

---

## Ordem recomendada até ao lançamento (Android primeiro)

**Semana 1, configuração (Henrique, sem código):**
1. AUD-08: passar o Supabase a Pro ou montar o dump diário; fazer um dump agora.
2. AUD-11: aplicar a 0075.
3. AUD-02: SMTP Brevo, templates com `{{ .Token }}`, ligar a confirmação de email.
4. AUD-18 (painel): senha mínima, limites de taxa.
5. AUD-01: Firebase, `google-services.json`, Edge Function, segredos, Vault.
6. AUD-10: domínio (ou Netlify) para `APP_PUBLIC_URL`.
7. AUD-06: decidir Google agora ou esconder.

**Semana 1, código (um PR pequeno, sem migrations):**
8. AUD-04, AUD-05, AUD-12, AUD-17, AUD-07, AUD-19, flag do Google (AUD-06) e do cartão frota (AUD-28), parte curta do AUD-13.

**Semana 2, verificação:**
9. Build de release assinada com todos os `--dart-define`.
10. AUD-03: testes manuais P0 e P1 num Android físico (`manual_test_plan.md`).
11. Comparar o schema da BD viva com a BD local (`launch_checklist.md`, secção Supabase).

**Semana 2 a 3, legal e loja:**
12. AUD-09: responsável, advogado, DPAs, página de eliminação.
13. Conta Play (pessoal obriga a 14 dias de teste fechado com 12 testadores: começar cedo), ficha, Data safety, AAB.

**Depois do lançamento:** AUD-14, AUD-15 (iOS), AUD-16, AUD-20 e os P3.
