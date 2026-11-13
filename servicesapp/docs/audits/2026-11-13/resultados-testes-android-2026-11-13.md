# Resultados dos testes Android (13/11/2026)

Execução do `manual_test_plan.md` desta auditoria em Android, com build de release assinada e BD de produção.

## Ambiente

- 2 emuladores Android 15 (API 35) com Google Play: `PJ_Cliente_API35` (cliente) e `PJ_Jardineiro_API35` (jardineiro), 1080x2400.
- APK de release assinado com a upload key, `--dart-define` de produção (`APP_PUBLIC_URL=https://projardim.pt`, `SUPPORT_EMAIL=suporte@projardim.pt`).
- `android/app/proguard-rules.pro` novo (regras `-dontwarn` do ML Kit) e `proguardFiles(...)` no `build.gradle.kts`: sem isto o R8 falha no build de release.
- APK reinstalado às 17:33 com a correção do registo do token push (`lib/app.dart`, ver "Correções pendentes").
- 2 contas de teste (cliente e jardineiro), GPS simulado em Bragança. As duas foram eliminadas pela app no fim (TR-09).
- AAB final: `servicesapp/build/app/outputs/bundle/release/app-release.aab` (81,6 MB, 17:34), já com a correção do `app.dart`.

As capturas estão em `capturas-android/` (230 ficheiros, uma por passo). **Não entram no repositório**: mostram o email das contas de teste.

## Resumo

| Teste | Resultado | Nota | Capturas |
|---|---|---|---|
| TR-01 Build de release | PASSA | Arranca no onboarding nos 2 emuladores. Falta confirmar `versionCode` e assinatura na Play Console. | `TR-01_*` |
| TR-02 Registo real com email | PASSA | Código chegou por email, escolha de papel, setup do jardineiro com foto, serviços e zona. | `TR-02_cliente_*`, `TR-02_jardineiro_*` |
| TR-03 Recuperar senha | PASSA | Em release, sem bypass. A senha antiga falha, a nova entra. | `TR-03_*` |
| TR-04 Criar pedido com GPS e câmara | PASSA | Permissões de localização e câmara, foto da câmara e da galeria, morada preenchida, jardineiro vê o pedido. | `TR-04_*` |
| TR-05 Propor e aceitar entre 2 aparelhos | PASSA | Os dois veem "Confirmado" sem reiniciar. Não deu para testar o "não selecionada" (só havia 1 jardineiro). | `TR-05_*` |
| TR-06 Push com a app fechada | PASSA | "Novo pedido" e "Proposta aceite" chegam, o toque abre o ecrã certo. O push perdido às 16:12 era a conta nova ainda sem token (corrigido no `app.dart`). | `TR-06_*` |
| TR-06 (repetição) Push "Novo pedido" 3 vezes com a app fechada | PASSA | Processo da app morto antes de cada tentativa. Tempos: 2,1 s, 2,1 s, 1,7 s (e 2,4 s numa 4.ª). Uma tentativa extra com a app em segundo plano: 2,0 s. | `TR-PUSH_01..05_*` |
| TR-07 Iniciar e concluir com fotos | PASSA | 2 fotos de antes, 2 de depois, cliente confirma e vê as 4. Toque duplo em "Iniciar trabalho", "Enviar para confirmação", "Trabalho concluído", "Confirmar" e "Enviar avaliação": sem duplicados (1 concluído, 1 avaliação, 1 aviso de cada tipo). | `TR-07_01..22` |
| TR-08 WhatsApp e Maps | PASSA | WhatsApp sem a app instalada e Maps no ponto certo. | `TR-08_*` |
| TR-09 Eliminar conta | PASSA, com 1 ponto por confirmar | Bloqueia bem com trabalhos em curso ("Tens trabalhos em curso..."). Depois de cancelar tudo, as 2 contas foram eliminadas e a app volta ao ecrã de entrada. **Falta confirmar que o login é recusado**: não escrevi senhas na app de produção. | `TR-09_cliente_*`, `TR-09_jardineiro_*` |
| TR-10 Crons na BD viva | NÃO FEITO | Precisa do SQL Editor. | |
| TR-14 Sem rede a meio de uma proposta | PASSA, com nota de UX | Em modo de avião aparece "Sem ligação à internet..." com "Tentar novamente" e o formulário mantém-se. Com rede, toque duplo em Enviar: 1 só proposta. Ver falha F2. | `TR-14_*` |
| TR-16 Cancelar perto da data | PASSA (parcial) | Cliente cancelou um trabalho confirmado para o dia seguinte: pede a razão, oferece voltar a publicar, o jardineiro fica sem o trabalho na hora. Não testei o jardineiro a cancelar. | `TR-16_*` |
| TR-19 Voltar do Android depois de push | PASSA | Abrir por push com a app fechada e fazer o gesto de voltar leva ao Início do jardineiro, não sai da app. | `TR-19_*` |
| TR-20 Aviso no topo com a app aberta | PASSA | Proposta nova com a app do cliente aberta: aviso no topo uma vez, "1 por ler". | `TR-20_*` |
| TR-21 Lembretes à hora | PASSA (parcial) | Chegou "O trabalho começa daqui a 1 hora" para o trabalho das 18:00. O lembrete de 30 min depois sem "Iniciar" não se aplicou (o trabalho foi iniciado). | `TR-07_22_jardineiro-notificacoes` |
| TR-23 Link e QR do cartão | PASSA, com nota | QR, "Copiar link" e partilha do sistema funcionam. O link é `https://projardim.pt/w/<id>?src=link`: só serve quando o domínio for vosso. | `TR-CARTAO_*` |
| TR-24 Monitorização | PASSA | Erro de teste aparece no Crashlytics. | `TR-24_01_crashlytics-consola` |
| Editar pedido | PASSA | Descrição alterada, o jardineiro vê a nova ao reabrir o pedido. | `TR-EDITAR_*` |
| Cancelar pedido em aberto | FALHA (F1) | Cancela bem no cliente, mas fica na lista "Pedidos" do jardineiro até reiniciar a app. | `TR-CANCELAR_*` |
| Retirar proposta (jardineiro) | PASSA | O cliente, que estava no detalhe dessa proposta, vê na hora "Esta proposta já não está disponível" e a lista fica vazia. | `TR-RETIRAR_*` |
| Recusar proposta (cliente) | NÃO EXISTE | O cliente só pode aceitar. "Recusar" só existe para remarcações. | `TR-RECUSAR_01_detalhe-proposta` |
| Agenda | PASSA, com nota | Semana, Mês e Hoje; trabalho "fora da app" adicionado. Ver falha F4. | `TR-AGENDA_*` |
| Notificações in-app | PASSA | Lista, filtro "Trabalhos", tocar abre o ecrã certo, "Marcar lidas" limpa o contador. | `TR-NOTIF_*` |
| Voltar do Android dentro da app | PASSA | Depois de abrir um alerta, voltar vai ao Início (os alertas usam `go()`, como decidido). | `TR-VOLTAR_01_*` |

TR-11, TR-12, TR-13 (Android 10), TR-15, TR-18, TR-22, TR-25, TR-26 e o bloco P2 não foram feitos nesta sessão.

## Ajudantes (segunda ronda, 18:25 a 18:50)

4 emuladores (cliente, jardineiro responsável, 2 ajudantes), 4 contas novas criadas para isto (o Henrique escreveu as senhas e os códigos) e eliminadas pela app no fim.

| Teste | Resultado | Nota | Capturas |
|---|---|---|---|
| Push "Novo pedido" em contas acabadas de criar | PASSA | Chegou aos 3 jardineiros logo depois do registo. Confirma a correção do token em `lib/app.dart`. | `TR-AJ_03_*` |
| Proposta com 1 ajudante | PASSA | Resumo com ajudante; o cliente vê "Ajudantes: 1" e, depois de aceitar, a fase "Equipa". | `TR-AJ_04..08` |
| Push "Pedido de ajuda perto de ti" | PASSA | Chegou aos 2 ajudantes. | `TR-AJ_09_*` |
| Tocar no push "Pedido de ajuda perto de ti" | A CONFIRMAR | Nos 2 ajudantes (app em segundo plano e app fechada) abriu o Início em vez da candidatura. O código parece certo, e o toque pode ter caído na notificação agrupada errada. Repetir com uma só notificação na gaveta. | `TR-AJ_10_*`, `TR-AJ_11_*` |
| Candidatura (alerta in-app e Descobrir) | PASSA | Os 2 caminhos abrem "Candidatar-me". Sem equipamento: 10,50 €/h; com equipamento: 15,00 €/h. | `TR-AJ_12..17` |
| TR-17 Dois candidatos para 1 vaga | PASSA (parcial) | A folha "Aceitar candidato" é modal, por isso num só aparelho não dá para aceitar os dois ao mesmo tempo. Com o toque duplo em "Confirmar e adicionar" ficou 1 só ajudante. O outro recebeu "Candidatura não selecionada" e o aceite "Candidatura aceite!". A corrida no servidor já estava provada na BD local (RACE-06). | `TR-17_*` |
| Alterar vagas de 1 para 2 | PASSA | O candidato recusado recebe "Vaga disponível novamente", volta a candidatar-se e entra com a taxa de 15,00 €/h. Equipa 2 de 2. Não pediu aprovação do cliente. | `TR-AJ_23..28` |
| Agenda do ajudante | PASSA | O trabalho aparece na semana seguinte como "Ajudante, com henrique". | `TR-AJ_31_*` |
| Cliente cancela com equipa | PASSA | Responsável e os 2 ajudantes recebem "Trabalho cancelado". | `TR-AJ_32_*`, `TR-AJ_33_*` |
| Eliminar as 4 contas | PASSA | Todas voltam ao ecrã de entrada. | `TR-AJ_34_*` |
| Aprovação do cliente (`pending_approval`) | NÃO TESTADO | Com os ajudantes pedidos na proposta, o pedido de ajuda abre logo. Falta o caso de pedir ajudantes depois de o cliente aceitar. | |

## Falhas e notas

| ID | Gravidade | O que acontece | Como reproduzir |
|---|---|---|---|
| F1 | Média | Um pedido cancelado pelo cliente continua na lista "Pedidos" do jardineiro. Puxar para baixo não atualiza (o ecrã não tem `RefreshIndicator`) e trocar de aba também não. Só desaparece ao reiniciar a app. Ao abrir, o detalhe diz "O pedido foi cancelado", por isso não dá para propor. | Jardineiro com a lista aberta, cliente cancela um pedido aberto, jardineiro volta à aba "Pedidos". |
| F2 | Baixa | Sem rede, o erro da proposta aparece no fundo do formulário, fora de vista. Quem está no topo toca em "Enviar proposta" e parece que nada acontece. | Modo de avião, preencher o topo do formulário, Enviar. |
| F3 | Baixa | No formulário de proposta, depois de escolher a data no calendário o foco volta ao campo do preço e o teclado reabre por cima de "Manhã/Tarde" e do botão. Um toque pode cair no teclado (aconteceu: entrou um "." no preço). | Escrever o preço, abrir o calendário, OK. |
| F4 | Baixa | Agenda, vista "Hoje": mostra "Só 8 min até ao próximo" para um trabalho já concluído, e a hora "18:00" do cartão parte-se em "18:0 / 0". | `TR-AGENDA_03_hoje`. |
| F5 | Baixa | Os pushes usam o canal `fcm_fallback_notification_channel`: falta `com.google.firebase.messaging.default_notification_channel_id` no `AndroidManifest.xml`, por isso nas definições do Android aparece um canal genérico em vez de um nome da app. | `adb shell dumpsys notification` com um push recebido. |
| F6 | Baixa | O alerta "Trabalho concluído!" mantém o botão "Confirmar conclusão" depois de o cliente já ter confirmado (abre o detalhe já "Concluído", sem erro). | `TR-NOTIF_02_*` |
| F7 | Baixa | No detalhe do pedido do cliente, a fila de fotos do pedido encosta ao cartão do jardineiro, sem espaço entre os dois. | `TR-07_13_cliente-fotos-pedido` |
| F8 | Média | No lobby da equipa (`worker_help_requests_lobby_view.dart`), depois de aceitar um candidato ou de alterar vagas, o `AppSuccessFeedback` ("Ajudante adicionado à equipa.", "Vagas atualizadas.") fica no ecrã para sempre, opaco e a bloquear os toques (nem os separadores respondem). `_successVisible` nunca volta a `false`. Só se sai com o voltar. Afeta também "Candidatura recusada." e as outras ações da equipa. | Responsável, separador Equipa, Aceitar, Confirmar. `TR-AJ_22_feedback-preso`. |
| F9 | Baixa | Colar o código do email no ecrã de código não preenche as caixas todas (relatado pelo Henrique no registo). | Copiar o código de 6 dígitos e colar na 1.ª caixa. |
| F10 | Baixa | O detalhe do trabalho do cliente não atualiza a equipa sozinho (ficou "0/1" com o ajudante já aceite) até sair e voltar a entrar. | `TR-AJ_19_*`, `TR-AJ_20_*` |
| F11 | Baixa | O Início do ajudante diz "Ainda não existem trabalhos agendados" com um trabalho de ajudante marcado (só aparece na Agenda). O Descobrir mostra "2 vagas" quando só falta 1. | `TR-AJ_29_*`, `TR-AJ_25_*` |
| F12 | Info | Existe a RPC `reject_proposal`, mas o cliente não tem botão para recusar uma proposta. | |

## Correções pendentes (no PC, fora deste ramo)

- `lib/app.dart`: o token FCM passa a ser registado só quando há perfil (depois de escolher o papel), em vez de logo a seguir ao código de email. Antes, numa conta nova o registo falhava com a FK de `device_tokens.user_id` e a conta ficava sem push até ao arranque seguinte. Está no APK e no AAB testados, mas ainda não está em nenhum commit.
