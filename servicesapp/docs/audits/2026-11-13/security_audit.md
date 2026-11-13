# Auditoria de segurança e privacidade (13/11/2026)

**Estado auditado:** `main` em `5cd9c59`, migrations `0001` a `0075`.
**Método:** BD Postgres 16 local com todas as migrations aplicadas por ordem (43 ficheiros, sem erros), consultas ao catálogo (`pg_policies`, `pg_proc`, grants), testes positivos e negativos com o papel `authenticated`/`anon` e `auth.uid()` de cada conta, leitura do código Flutter, da Edge Function e da configuração Android/iOS, pesquisa de segredos em todo o histórico Git (209 commits).
**Limites:** a BD viva, o Supabase Auth real, o Storage real e o painel do Supabase não estão acessíveis daqui (rede bloqueada a `*.supabase.co`). Tudo o que depende deles está marcado **NÃO VERIFICADO**.

## Resumo

- **Nenhuma vulnerabilidade explorável encontrada** na camada de dados. RLS ligada nas 28 tabelas, escritas de negócio só por RPC, identidade sempre por `auth.uid()`, morada exata só depois de aceite.
- Os riscos de segurança que sobram são de **configuração e operação** (Auth, SMTP, backups, assinatura, monitorização), não de código.
- Privacidade: a eliminação de conta está completa no servidor (o `STATUS.md` está desatualizado neste ponto). Falta a parte legal (responsável, revisão jurídica) e a decisão sobre os buckets públicos.

## 4.1 Autenticação e sessões

| Ponto | Resultado | Evidência |
|---|---|---|
| Registo e login por email | OK (web, Supabase local) | TM-002, TM-004 de 12/11 |
| Política de senha (8+, maiúscula, número) | Só no cliente. **Mínimo do Supabase Auth NÃO VERIFICADO** (AUD-18) | `core/constants/password_policy.dart` |
| Recuperação de senha | Código OK; bypass só com `kDebugMode` (constante falsa em release). **Envio de email real NÃO VERIFICADO** (AUD-02) | `auth_repository.dart:286` |
| Confirmação de email | Pronta no código, desligada no Supabase até haver SMTP (NÃO VERIFICADO) | `STATUS.md` |
| Expiração e renovação de tokens | Gerida pelo `supabase_flutter`; duração do JWT no painel NÃO VERIFICADA | |
| Logout | Global por omissão; local depois de eliminar conta (de propósito) | `signOutLocally` |
| Utilizadores eliminados | Login bloqueado (`banned_until` 1000 anos), sessões, identidades, refresh tokens e fatores MFA apagados, email trocado e bloqueado 90 dias | `delete_my_account`, TM-005, TM-012 |
| Deep link OAuth | `pt.projardim.app://login-callback` (Android e iOS); o Supabase troca o código. Redirect URLs no painel NÃO VERIFICADOS | `AndroidManifest.xml`, `route_guard.dart` |
| Acesso direto a rotas protegidas | Sem sessão vai para `/` ou onboarding; papel cruzado vai para o início do papel | `route_guard_test.dart`, TM-015 |
| CAPTCHA / limites no registo | Não existe CAPTCHA; limites de taxa do Auth NÃO VERIFICADOS (AUD-18) | |
| Admin | `admin_users` + `aal2` (TOTP) dentro de cada RPC `admin_*` | T-ADM, TM-053 |

## 4.2 Autorização e separação de utilizadores

Testes negativos feitos nesta auditoria (como `authenticated`, com o `auth.uid()` indicado), todos **recusados** como esperado:

| Tentativa | Resultado |
|---|---|
| Cliente muda o próprio `role` para `worker` | `Não é permitido alterar o role do perfil.` |
| Cliente marca-se como eliminado (`deleted_at`) | `Estes dados do perfil não se podem alterar.` |
| Conta eliminada repõe `deleted_at = null` e o nome | `Estes dados do perfil não se podem alterar.` |
| Jardineiro põe o raio a 5000 km | violação de `worker_profiles_radius_km_range` |
| Cliente insere uma avaliação por INSERT direto | violação de RLS em `ratings` |
| Cliente insere uma notificação para outra pessoa | violação de RLS em `notifications` |
| Jardineiro insere uma proposta já `accepted` por INSERT direto | violação de RLS em `job_proposals` |
| `anon` lê `job_requests` e `ratings` | 0 linhas |
| Jardineiro lê `profiles` | só o próprio e clientes com proposta aceite |

Somam-se às 162 asserções do `10_flows.sql` (todas PASS hoje) e às 20 do `30_findings.sql` (todas PASS), que cobrem acessos horizontais e verticais por fluxo (T-PROF, T-PROP, T-HELP, T-RATE, T-ADM, T-STOR, entre outros).

Aceites pela API mas inofensivos ou já mitigados na app:

- `profiles.phone` aceita `"1"` (AUD-20): a app valida, a API não. Só estraga o link de WhatsApp do próprio.
- `profiles.avatar_url` aceita um URL externo: a app só mostra URLs do Storage do projeto (`StorageUrls`), por isso não há rastreio por imagem.
- `notifications`: o dono pode mudar título e corpo das suas próprias notificações (só ele as vê).

## 4.3 Row Level Security

- **28 tabelas em `public`, todas com RLS ligada.** Tabelas internas (`admin_users`, `admin_actions`, `worker_plans`, `worker_card_visits`, `client_referrals`, `seasonal_*`, `deleted_account_emails`, `job_work_days`, `device_tokens` para escrita) sem policies de escrita: só por RPC `SECURITY DEFINER` ou SQL Editor.
- **52 policies** revistas (lista completa obtida de `pg_policies`). Todas para `authenticated`; nenhuma para `anon`. Leituras com `USING (true)`: `ratings`, `service_categories`, `service_types`, `proposal_include_options`, `worker_service_types`. Só `ratings` tem dados de pessoas (ids, estrelas, comentário): qualquer conta pode ver quem avaliou quem. Aceitável para um marketplace, mas convém dizê-lo na Política.
- **INSERT diretos permitidos** e verificados: `job_requests` (WITH CHECK com 17 condições e trigger que limpa os campos do servidor), `job_photos` (máximo 2, RACE-03), `help_requests`, `help_acceptances`, `job_reports`, `worker_calendar_*`, `worker_fleet_cards` (só `pending`), `profiles`, `worker_profiles`.
- **Funções `SECURITY DEFINER`: 125**, todas com `search_path` fixo. Executáveis por `anon`: só `log_worker_card_visit` e helpers do cartão público (`worker_public_tier`, `worker_can_*`), mais funções de trigger (não chamáveis diretamente). Das executáveis por `authenticated` sem `auth.uid()` no corpo, todas delegam a verificação (`assert_verified_admin`, `lock_started_job_for_worker`, `is_principal_worker_for_help_request`, `can_see_*`).
- **Views:** `worker_profiles_public`, `worker_public_card` e `worker_card_funnel` sem `security_invoker` de propósito (expõem colunas escolhidas, sem telefone nem coordenadas); `worker_card_funnel` sem grant a ninguém.
- **Grants:** o `anon` tem os grants por omissão do Supabase em todas as tabelas (inclui `TRUNCATE`). A RLS bloqueia leituras e escritas e o PostgREST não expõe `TRUNCATE`; fica como nota (P3), igual a qualquer projeto Supabase.
- **NÃO VERIFICADO:** que a BD viva tem exatamente estas policies (último dump real a 16/10, até à 0040). Recomendação: `supabase db dump --schema public` e comparar com esta BD local (comando em `launch_checklist.md`).

## 4.4 Chaves, segredos e configuração

| Verificação | Resultado |
|---|---|
| Segredos no código e em todo o histórico Git | **Nenhum.** Procurados JWT, chaves Google `AIza`, chaves privadas PEM, tokens `sbp_`, Brevo, `storePassword`. Os únicos resultados são o URL do projeto Supabase (público por natureza) e o código que lê a chave da service account na Edge Function |
| Ficheiros sensíveis versionados | Nenhum (`google-services.json`, `GoogleService-Info.plist`, `key.properties`, `*.env`, `.vscode/` no `.gitignore`; nunca entraram no histórico) |
| Chave do Supabase na app | Só a publicável/anon por `--dart-define` (`SupabaseConfig`). A `service_role` só existe na Edge Function |
| Edge Function `send-push` | Sem JWT de propósito, protegida por `x-webhook-secret`; **falha fechada** quando o segredo não está definido |
| Build sem `--dart-define` | A app arranca com URL vazio, sem aviso (AUD-04) |
| Logs | `debugPrint` também escreve em release (Android logcat): mensagens de erro de rede e do servidor, sem tokens (AUD-22) |
| Assinatura Android | Sem `key.properties`, o release é assinado com a chave de debug sem aviso (AUD-04) |

## 4.5 Storage e fotografias

| Ponto | Resultado |
|---|---|
| Buckets | `avatars` e `job-photos`, **ambos públicos**, 2 MB, só JPEG/PNG/WebP |
| Upload | Só autenticado e só para a própria pasta (`job-photos/<uid>/...`) ou o próprio ficheiro (`avatars/<uid>.jpg`) (T-STOR) |
| Leitura | Pela API, só o dono. **Pelo URL público, qualquer pessoa, sem sessão** (TM-050). Inclui fotos do jardim e fotos de antes e depois tiradas na morada (AUD-14) |
| Remover e substituir | Só o dono |
| Compressão | 800 px, qualidade 60, antes do upload |
| Fotos órfãs | Fotos de pedidos cancelados ou de propostas não ficam órfãs na BD (cascade), mas os ficheiros no Storage ficam até eliminar a conta. Não há limpeza periódica (P3) |
| Ao eliminar conta | A app apaga o avatar e a pasta `job-photos/<uid>/` (melhor esforço; se falhar, os ficheiros ficam) |
| URLs assinadas | Não usadas |

## 4.6 Privacidade e RGPD (revisão técnica, não jurídica)

| Dado | Recolhido | Quem vê | Nota |
|---|---|---|---|
| Nome, email, telefone | Sim | Telefone só à contraparte depois de aceite | OK |
| Morada exata e coordenadas | Sim | Jardineiro só depois de aceite; antes, localidade e coordenadas arredondadas a ~1 km | OK (0043) |
| Base do jardineiro | Sim | Ninguém (só o próprio) | OK |
| Fotos | Sim | URL público (AUD-14) | Política já o diz |
| Avaliações e comentários | Sim | Qualquer conta; primeiro nome no cartão público | Dizer na Política |
| Agenda: nomes e telefones de terceiros | Sim | Só o jardineiro | Secção 3.7 da Política escrita a 26/10, **por publicar** (AUD-09) |
| Visitas ao cartão (id de aparelho aleatório) | Sim | Só SQL Editor | Falta na Política publicada |
| Tokens de push | Sim | Ninguém | Apagados ao eliminar conta |
| IP para Google Fonts, OSM tiles, Photon, Nominatim | Sim (por terceiros) | Terceiros | Google Fonts pode ser empacotada (AUD-17) |

- **Eliminação de conta:** completa no servidor (`erase_account_data`: perfil, perfil de jardineiro, serviços, tokens, cartão frota, notificações, preferências, plano, Agenda, visitas, admin, fotos e moradas de pedidos, notas de propostas, mensagens, comentários de avaliações). O `STATUS.md` ainda diz o contrário (AUD-19).
- **Exportação de dados (art. 20.º):** não existe na app. Pode ser feita a pedido por email; a Política tem de o dizer.
- **Retenção:** notificações limpas apagadas ao fim de 1 dia; o resto indefinido. Definir prazos na Política.
- **Consentimento:** termos aceites no registo; localização pedida só em uso; push pedido no Android 13+. Dicas da época com opt-out.
- **Precisa de revisão jurídica antes do lançamento:** identificação do responsável, base legal por finalidade, Livro de Reclamações Eletrónico, entidade RAL, Regulamento dos Serviços Digitais e P2B para jardineiros, DPAs com Supabase, Firebase, Netlify e Brevo, região do Supabase (UE?). **Não declaro conformidade legal.**

## 4.7 Dependências e permissões

- `flutter pub outdated`: 12 dependências diretas atrás da última versão (as maiores: `go_router` 17 → 18, `share_plus` 11 → 13, `google_mlkit_text_recognition` 0.15 → 1.0, `geocoding` 4 → 5, `google_fonts` 6 → 9). Nenhum aviso de segurança publicado no pub.dev para as versões em uso. Nada abandonado.
- **Android:** `INTERNET`, localização fina e aproximada (só em primeiro plano), `POST_NOTIFICATIONS`, `READ_MEDIA_IMAGES` e `READ_EXTERNAL_STORAGE` (até API 32). **`READ_MEDIA_IMAGES` é desnecessária** porque o `image_picker` usa o Photo Picker, e a política de fotos e vídeos da Google Play recusa-a a apps que só escolhem fotos de vez em quando (AUD-05). `allowBackup` por omissão (AUD-27).
- **iOS:** descrições de localização, câmara e galeria em português. Falta o `PrivacyInfo.xcprivacy` da app, os entitlements de push e o Sign in with Apple (AUD-15, AUD-06).
- **16 KB page size** (Google Play, apps com `targetSdk` 35+): o motor do Flutter 3.44 cumpre; as bibliotecas nativas do ML Kit 0.15 **NÃO VERIFICADAS**. Verificar no AAB final.

## Problemas de segurança e privacidade encontrados

Detalhe completo em `remediation_plan.md` e `release_readiness_report.md`.

| ID | Título | Sev. |
|---|---|---|
| AUD-02 | Email real (SMTP, recuperação, confirmação) não configurado ou não verificado | P1 |
| AUD-04 | Release assinado com a chave de debug sem aviso; build sem `--dart-define` arranca sem backend | P1 |
| AUD-05 | `READ_MEDIA_IMAGES` desnecessária, risco de rejeição na Play | P1 |
| AUD-06 | Login Google sempre visível sem configuração confirmada; iOS exige Sign in with Apple | P1 |
| AUD-08 | Plano Free do Supabase: sem backups recuperáveis | P1 |
| AUD-09 | Termos e Política sem responsável, sem revisão jurídica, desatualizados | P1 |
| AUD-14 | Fotos de pedidos legíveis por URL público sem sessão | P2 |
| AUD-17 | Google Fonts descarregada em runtime (IP à Google, primeiro arranque sem rede) | P2 |
| AUD-18 | Senha mínima e limites do Auth só no cliente; sem CAPTCHA | P2 |
| AUD-20 | Telefone sem validação no servidor | P2 |
| AUD-22 | `debugPrint` em release | P3 |
| AUD-27 | `allowBackup` por omissão inclui a sessão no backup do Android | P3 |
