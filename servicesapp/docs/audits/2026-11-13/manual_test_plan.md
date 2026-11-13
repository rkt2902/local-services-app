# Plano de testes manuais antes da publicação (13/11/2026)

Testes que **não se validam a ler código** nem na BD local. Todos estão **PENDENTES**: nenhum foi executado nesta auditoria (sem dispositivo, sem acesso à produção).

Este plano complementa o de 12/11 (`docs/systematic-debugging-audit/05-MANUAL-TEST-PLAN.md`, 56 testes TM-001 a TM-056). Desses, 37 já passaram na web com Supabase local (12/11, ver `relatorios/2026-11-12-testes-manuais-web/`), mas **num browser não contam como validação em Android**. Aqui fica só o que falta para o lançamento, com os testes novos desta auditoria (TR-xx).

**Ambiente para todos:** Android físico (de preferência um Android 13+ e um Android 10 ou 11), **build de release assinada** com os `--dart-define` de produção, BD de produção com contas de teste, GPS num sítio sem jardineiros reais e tudo apagado no fim (decisão de 13/11). Segundo aparelho ou emulador com Google Play para os testes com duas contas.

Formato: **Pré-condições → Passos → Resultado esperado → Critério de aprovação.**

## Bloco P0 (sem estes não há lançamento)

| ID | Pré-condições | Passos | Resultado esperado | Critério de aprovação | Estado |
|---|---|---|---|---|---|
| TR-01 Build de release | `key.properties` com a upload key; `--dart-define` de produção | `flutter build appbundle --release ...`; instalar por teste interno da Play ou `bundletool` | Instala e arranca no ecrã de onboarding, sem ecrã vermelho nem cinzento | Arranca em 2 aparelhos; `versionCode` e assinatura certos na Play Console | PENDENTE |
| TR-02 Registo real com email | AUD-02 feito; email novo | Registo, código por email, escolher Cliente | Código chega em menos de 2 min; entra no Início | Código chega 3 vezes seguidas na mesma hora | PENDENTE (TM-003) |
| TR-03 Recuperar senha | Conta existente | "Esqueci-me", código, senha nova, login com a nova | Login com a nova; a antiga falha | Funciona em release (sem o bypass de debug) | PENDENTE (TM-009) |
| TR-04 Criar pedido com GPS e câmara | Cliente; permissões por dar | Criar pedido, "Usar a minha localização", aceitar permissão, foto pela câmara e outra pela galeria, publicar | Morada em texto preenchida, 2 fotos visíveis no detalhe | Pedido aparece ao jardineiro da zona com zona aproximada | PENDENTE (TM-016) |
| TR-05 Propor e aceitar entre 2 aparelhos | Jardineiro na zona; pedido de TR-04 | Jardineiro propõe; cliente vê, aceita | Os dois veem "Confirmado"; o outro jardineiro recebe "não selecionada" | Estado igual nos dois aparelhos sem reiniciar | PENDENTE (TM-021, TM-034) |
| TR-06 Push com a app fechada | AUD-01 feito; permissão de notificações dada | Fechar a app do jardineiro; criar pedido na zona; depois aceitar a proposta | Push "Novo pedido" e "Proposta aceite" chegam; tocar abre o ecrã certo | Chega em menos de 1 min em 3 de 3 tentativas | PENDENTE (TM-046) |
| TR-07 Iniciar e concluir com fotos | Trabalho confirmado para hoje | Iniciar com 2 fotos de antes, concluir com 2 de depois; cliente confirma | Cliente vê as 4 fotos, "Concluído" | Sem duplicados com toque duplo | PENDENTE (TM-036) |
| TR-08 WhatsApp e Maps | Trabalho confirmado | Tocar no WhatsApp (com e sem a app instalada) e na morada | Abre a conversa com o número certo; abre o Maps no ponto certo | Funciona nos 2 aparelhos | PENDENTE (TM-030) |
| TR-09 Eliminar conta | Conta de teste sem trabalhos ativos | Perfil, eliminar conta, confirmar; tentar login | Sai da app; login recusado; fotos do pedido deixam de abrir pelo URL | Na BD viva: nome "Conta eliminada", sem telefone | PENDENTE (TM-012) |
| TR-10 Crons na BD viva | Acesso ao SQL Editor | `select jobname, schedule, active from cron.job;` e `select jobname, status, start_time from cron.job_run_details order by start_time desc limit 30;` | 11 jobs ativos, últimas execuções `succeeded` | Nenhum `failed` nas últimas 24h | PENDENTE (TM-054) |

## Bloco P1

| ID | Pré-condições | Passos | Resultado esperado | Critério | Estado |
|---|---|---|---|---|---|
| TR-11 Permissão GPS recusada | Instalação limpa | Criar pedido, recusar localização; depois "Não perguntar de novo" | Mensagem clara e campo de morada à mão; nada bloqueia | Pedido publicado só com morada escrita | PENDENTE |
| TR-12 Localização errada | GPS simulado noutra cidade | "Usar a minha localização", corrigir a morada à mão | A morada escrita prevalece; o pino segue a morada | Jardineiro vê a zona certa | PENDENTE |
| TR-13 Fotos sem `READ_MEDIA_IMAGES` | AUD-05 feito | Escolher fotos em Android 13+ e em Android 10 | Abre o seletor do sistema sem pedir acesso à galeria toda | Funciona nos dois | PENDENTE |
| TR-14 Sem rede a meio de uma proposta | Jardineiro com proposta preenchida | Modo de avião, Enviar; voltar a ligar, Enviar | Erro amigável; o formulário mantém-se; à segunda cria 1 proposta | Nunca 2 propostas | PENDENTE (TM-052) |
| TR-15 Remarcar entre 2 aparelhos | Trabalho confirmado | Jardineiro propõe nova data; cliente aceita noutro aparelho | Data nova nos dois; aviso aos ajudantes | Igual nos dois sem reiniciar | PENDENTE (TM-027 em Android) |
| TR-16 Cancelar perto da data | Trabalho para amanhã | Cliente cancela; jardineiro cancela outro | Avisos certos; regras das 24h | Estados coerentes na BD | PENDENTE |
| TR-17 Dois ajudantes para a última vaga | Pedido de ajuda com 1 vaga, 2 candidatos | Responsável aceita os dois quase ao mesmo tempo (2 aparelhos com a mesma conta, ou toque duplo) | Só 1 aceite; o outro recebe "não selecionada" | A BD tem 1 aceite e o pedido `filled` (já provado na BD local, RACE-06) | PENDENTE |
| TR-18 Login com Google | AUD-06 configurado | "Continuar com Google" em conta nova e existente | Conta nova vai a escolher papel; existente entra | Funciona em release (SHA-1 da Play App Signing no Google Cloud) | PENDENTE (TM-006) |
| TR-19 Voltar do Android depois de push | TR-06 | Abrir por push, voltar com o gesto | Vai ao início do papel, não sai da app | 3 tipos de aviso | PENDENTE (TM-048) |
| TR-20 Aviso no topo com a app aberta | Realtime ativo em produção | Com a app aberta, outra conta faz uma proposta | Aviso no topo uma vez; tocar abre o pedido | Sem repetidos | PENDENTE (TM-045) |
| TR-21 Lembretes à hora | Trabalho com hora marcada daqui a 70 min | Esperar | Lembrete 1h antes; 30 min depois sem Iniciar, outro | Hora certa (Lisboa) | PENDENTE (TM-042) |
| TR-22 Mapa e moradas | AUD-12 e AUD-13 feitos | Abrir o mapa, procurar 5 moradas reais (rua, lugar, código postal) | Tiles carregam; atribuição visível; sugestões aparecem | 5 de 5 encontradas ou escritas à mão | PENDENTE (TM-051) |
| TR-23 Link e QR do cartão | AUD-10 feito | Partilhar o cartão, ler o QR com outro telemóvel | Abre o domínio certo `/w/<id>` | Nunca `projardim.pt` se o domínio não for teu | PENDENTE |
| TR-24 Monitorização | AUD-07 feito | Forçar um erro de teste numa build interna | Aparece no Crashlytics | Sem dados pessoais na mensagem | PENDENTE |
| TR-25 Restauro de backup | AUD-08 feito | Restaurar o último backup num projeto de teste | BD sobe com os dados | Feito uma vez e escrito | PENDENTE |
| TR-26 Schema da BD viva igual ao do repo | Supabase CLI ligado, dentro de `servicesapp/` | `supabase db dump --schema public,storage -f /tmp/live.sql` e comparar funções, policies e triggers com a BD local de `run.sh` | Sem diferenças além do nome do trigger `on_job_created` | 0 diferenças inesperadas | PENDENTE |

## Bloco P2

| ID | Pré-condições | Passos | Resultado esperado | Critério | Estado |
|---|---|---|---|---|---|
| TR-27 Ecrã pequeno e texto grande | Aparelho de 360 dp ou emulador; tamanho de letra no máximo | Percorrer criar pedido, propostas, detalhe, Agenda | Sem overflow nem botões tapados | Sem faixas amarelas e pretas; tudo clicável | PENDENTE |
| TR-28 Leitor de ecrã | TalkBack ligado | Login, criar pedido, aceitar proposta | Botões com nome; avisos lidos | Fluxo completo sem ver o ecrã | PENDENTE |
| TR-29 Rotação e tablet | Tablet ou rotação ligada | Rodar nos ecrãs principais | Layout largo correto, sem perder o que estava escrito | Sem perder dados | PENDENTE |
| TR-30 App em segundo plano | Proposta a meio | Ir ao WhatsApp e voltar 10 min depois | Formulário mantém-se ou avisa | Sem crash | PENDENTE |
| TR-31 Internet lenta | Perfil de rede 3G lenta | Abrir Início, pedidos, propostas | Esqueletos, depois dados; sem esqueleto infinito | Tudo carrega em menos de 15 s | PENDENTE |
| TR-32 OCR do cartão frota | Só se o cartão frota ficar visível (AUD-28) | Ler um cartão | Campos extraídos; foto não guardada | | PENDENTE (TM-041) |
| TR-33 Safari / PWA | Web publicada | Abrir `/w/<id>` e fazer um pedido | Igual ao Android | | PENDENTE (TM-055) |

## iOS

Todos **BLOQUEADOS** até haver Mac, conta Apple e o AUD-15. Quando houver: repetir TR-01 a TR-10 no iPhone e acrescentar Sign in with Apple, permissões em português e push por APNs.
