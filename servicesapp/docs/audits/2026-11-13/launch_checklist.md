# Checklist de lançamento (13/11/2026)

Marcado com o que foi **verificado no repositório** nesta auditoria. O resto fica por fazer ou por confirmar (só o Henrique tem acesso aos painéis, às contas e aos aparelhos). Complementa `projardim/play-store/checklist-lancamento.md` (21/10) nas notas do projeto.

Legenda: [x] verificado e certo · [ ] por fazer · [?] NÃO VERIFICADO (depende de painel, conta ou aparelho) · [!] verificado e errado

## Android

- [x] Application ID `pt.projardim.app` (namespace igual)
- [x] Nome "ProJardim" no `AndroidManifest.xml`
- [x] Ícone adaptativo e splash nativo configurados (`flutter_launcher_icons`, `flutter_native_splash`)
- [x] Versão `1.0.0+1` no `pubspec.yaml`
- [x] `minSdk`, `targetSdk` e `compileSdk` do Flutter 3.44.1 (o `targetSdk` exigido pela Play para apps novas)
- [x] Localização só em primeiro plano; sem permissões sensíveis (SMS, contactos, todos os ficheiros)
- [x] `READ_MEDIA_IMAGES` removida (AUD-05, PR #53); testar a escolha de fotos (TR-13)
- [x] Release recusa assinar sem `key.properties` (AUD-04, PR #53)
- [ ] Gerar a upload key e `android/key.properties` (fora do git)
- [ ] `flutter build appbundle --release` com **todos** os `--dart-define`: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APP_PUBLIC_URL`, `SUPPORT_EMAIL` (e `TERMS_URL`/`PRIVACY_POLICY_URL` se mudarem)
- [x] Push a funcionar, confirmado pelo dono a 13/11
- [?] Bibliotecas nativas alinhadas a 16 KB (verificar no APK Analyzer do Android Studio, sobretudo o ML Kit)
- [ ] Testes manuais P0 num Android físico com a build de release (`manual_test_plan.md`)
- [ ] Conta Google Play (pessoal: 14 dias de teste fechado com 12 testadores antes de produção; organização: D-U-N-S)
- [ ] Play App Signing ativo; SHA-1 da chave da Play no Google Cloud (login Google) e no Firebase
- [ ] Ficha: ícone 512, gráfico 1024x500, 4 a 8 capturas, nome, descrições curta e longa
- [ ] Data safety a bater com a Política (nome, email, telefone, localização precisa e aproximada, fotos, avaliações, identificador do aparelho do cartão, tokens de push, dados de diagnóstico se houver Crashlytics)
- [x] URL web para pedir a eliminação de conta: `https://projardim.pt/eliminar-conta.html`
- [ ] Classificação de conteúdo (IARC), público 18+, sem anúncios
- [ ] Credenciais de teste para a revisão (uma conta de cliente e uma de jardineiro)

## iOS (recomendado: segunda fase)

- [x] Bundle ID `pt.projardim.app`
- [x] Nome "ProJardim" (`CFBundleDisplayName`)
- [x] Deployment target 15.0
- [x] Descrições de localização, câmara e galeria em português
- [x] Esquema de URL para o OAuth (`CFBundleURLTypes`)
- [!] Sem `Runner.entitlements` com `aps-environment` (push não funciona no iPhone)
- [!] Sem `PrivacyInfo.xcprivacy` da app
- [!] Sem Sign in with Apple, obrigatório com login Google (regra 4.8)
- [ ] Conta Apple Developer, certificados e provisioning
- [ ] Chave APNs no Firebase
- [ ] Build de release num Mac, TestFlight
- [ ] App Privacy na App Store Connect

## Supabase e backend

- [x] 43 migrations aplicam sem erro numa BD vazia (Postgres 16)
- [x] RLS ligada em todas as tabelas; testes positivos e negativos passam (`security_audit.md`)
- [?] BD viva com todas as migrations até à 0074 (palavra do Henrique a 12/11)
- [x] `0075` e `0076` aplicadas (Henrique, 13/11)
- [ ] Comparar o schema da BD viva com o do repositório, a partir de `servicesapp/`:
  `supabase db dump --schema public -f /tmp/live.sql` e comparar com `pg_dump --schema-only` da BD de `supabase/tests/audit/run.sh keep` (TR-26)
- [x] 11 jobs do `pg_cron` ativos e sem erros (Henrique, 13/11)
- [x] Dump diário automático, cifrado, 30 dias (GitHub Action "Backup BD", primeiro a 13/11)
- [ ] Procedimento de restauro escrito e testado uma vez (TR-25)
- [?] Região do projeto na UE
- [x] Auth: senha mínima 8 com letras e números (13/11); [?] CAPTCHA; limites de envio 30 emails/h
- [x] Email (SMTP) a funcionar, confirmado pelo dono a 13/11 (AUD-02)
- [?] Auth: Redirect URLs com `pt.projardim.app://login-callback` e o domínio web
- [x] Google configurado, confirmado pelo dono a 13/11 (AUD-06)
- [?] Edge Function `send-push` publicada com `--no-verify-jwt`; segredos `FCM_SERVICE_ACCOUNT` e `PUSH_WEBHOOK_SECRET`; `push_webhook_secret` no Vault (AUD-01)
- [?] Realtime ativo na tabela `notifications`
- [?] DPA da Supabase aceite
- [ ] Contas de teste e dados de teste apagados antes de abrir ao público

## Operação

- [x] Crashlytics integrado (AUD-07, PR #53); [ ] ativar no Firebase e forçar um erro de teste
- [ ] Alertas de uso do Supabase (BD, Storage, egress, MAU)
- [ ] Gestão de incidentes: quem vê o email de suporte, prazo de resposta ("1 dia útil" está prometido na app)
- [ ] Controlo de versões: tag Git por versão publicada (`v1.0.0+1`)
- [ ] Plano de rollback: a app não volta atrás numa loja; manter migrations compatíveis com a versão anterior da app durante 2 semanas, e um dump antes de cada migration
- [x] Separação de ambientes: as chaves entram por `--dart-define`; [?] não existe projeto Supabase de staging (só produção e local)
- [x] CI: `flutter analyze` e `flutter test` em cada PR; [ ] testes da BD no CI (AUD-16)
- [ ] Deploy web (Netlify) na mesma versão da app

## Legal e suporte

- [!] Termos e Política sem identificação do responsável (AUD-09)
- [ ] Revisão jurídica (papel de intermediário, Livro de Reclamações Eletrónico, RAL, DSA e P2B para jardineiros)
- [ ] Política com a Agenda (dados de terceiros), visitas ao cartão, Photon/OSM, Crashlytics, retenção e exportação de dados
- [ ] DPAs com Supabase, Firebase, Netlify e Brevo
- [x] `projardim.pt` com HTTPS, remetente `noreply@` autenticado no Brevo e `suporte@` reencaminhado (13/11)
- [ ] Procedimento para reclamações e denúncias (relatos de problema chegam a `job_reports`; quem os lê e em quanto tempo)

## Escala (primeiros meses)

Com o plano Free do Supabase: 500 MB de BD, 1 GB de Storage, 5 GB de saída, 50 mil utilizadores ativos por mês. As fotos (até 2 por pedido + 6 de antes e depois por trabalho, cerca de 100 KB cada) cabem em 1 GB para alguns milhares de trabalhos; o egress das fotos públicas é o primeiro limite. As RPCs de pesquisa por raio fazem contas de distância por linha (sem PostGIS) e chegam para milhares de pedidos abertos. Os serviços de moradas gratuitos (Photon, Nominatim) são o primeiro ponto a partir (AUD-13).
