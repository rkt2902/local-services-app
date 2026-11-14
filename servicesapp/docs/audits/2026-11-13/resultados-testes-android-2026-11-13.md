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
| F9 | Baixa | Colar o código do email no ecrã de código não preenche as caixas todas (relatado pelo Henrique no registo). Já corrigido no commit `f0c701f` deste ramo, ainda por testar em Android. | Copiar o código de 6 dígitos e colar na 1.ª caixa. |
| F10 | Baixa | O detalhe do trabalho do cliente não atualiza a equipa sozinho (ficou "0/1" com o ajudante já aceite) até sair e voltar a entrar. | `TR-AJ_19_*`, `TR-AJ_20_*` |
| F11 | Baixa | O Início do ajudante diz "Ainda não existem trabalhos agendados" com um trabalho de ajudante marcado (só aparece na Agenda). O Descobrir mostra "2 vagas" quando só falta 1. | `TR-AJ_29_*`, `TR-AJ_25_*` |
| F12 | Info | Existe a RPC `reject_proposal`, mas o cliente não tem botão para recusar uma proposta. | |

## Correções pendentes

- A correção do registo do token push está no commit `ba763b1` deste ramo, numa versão refeita (provider e testes) da que foi testada no APK. Convém instalar um APK novo deste ramo e repetir o registo de uma conta nova e o push "Novo pedido". **Feito a 14/11, ver a terceira ronda: passa.**

## Terceira ronda: correções do ramo (14/11, 04:05 a 04:40)

APK de release do ramo `claude/project-thread-d58w4x` no commit `2cc08a6` (com as correções F1 a F12, os Termos e a Política na app e a paginação). 4 contas novas (`+teste1` cliente; `+teste2`, `+teste3`, `+teste4` jardineiros). O Henrique escreveu as senhas e os códigos. As contas ficam ativas: não foram eliminadas. Capturas `AJ3_*` fora do repositório (pasta temporária da sessão, porque mostram o email).

| Teste | Resultado | Nota | Capturas |
|---|---|---|---|
| Registo das 4 contas (F9, colar o código) | A CONFIRMAR | As 4 contas foram criadas pelo Henrique; falta ele dizer se colar o código preencheu as 6 caixas. | |
| Push "Novo pedido" em contas acabadas de criar | PASSA | Chegou aos 3 jardineiros logo a seguir ao setup (correção do token, versão do commit). | `AJ3_11_*` |
| Termos e Política na app | PASSA, com nota | Perfil > Sobre > Termos abre o ecrã novo: cabeçalho com a data, índice que abre e salta para a secção, secções em cartões, "Ler a Política de Privacidade" no fim; voltar regressa ao "Sobre" sem acumular páginas. **Nota:** o responsável aparece como "[NOME OU DENOMINAÇÃO]", "[NÚMERO]" e "[MORADA COMPLETA]", por preencher antes de publicar. | `AJ3_03..07` |
| Contacto e suporte | PASSA | Prazos de resposta (1 dia útil, reclamações 15 dias úteis, dados 1 mês) e o botão "Livro de Reclamações Eletrónico", que abre o browser; voltar regressa à app. | `AJ3_01`, `AJ3_02` |
| Pedido com data fixa | PASSA | 17/11, GPS, 300+ m². | `AJ3_08..11` |
| Duas propostas, cliente recusa uma e aceita a outra | PASSA | Botão novo "Recusar proposta" com confirmação; toque duplo em "Recusar" sem erro; a lista passa a 1 proposta; o jardineiro recusado recebe "Proposta não selecionada". Aceitar a outra: "Pedido confirmado!". | `AJ3_13..17`, `AJ3_34` |
| Responsável pede 2 ajudantes depois do aceite | PASSA | Folha "Adicionar ajudante" ("O pedido segue para o cliente aprovar"); toque duplo em "Enviar pedido" sem duplicados. | `AJ3_18`, `AJ3_19` |
| Cliente aprova os ajudantes | PASSA, com nota | Alerta "Pedido de ajudantes ... Sem resposta, fica aprovado em 24 horas", que abre o detalhe com "Aprovar". **Nota:** o Início do cliente não mostra este pedido em "Precisa de ti"; só nos Alertas. | `AJ3_20..23` |
| Toque no push "Pedido de ajuda" com a app fechada | PASSA | Uma só notificação na gaveta, processo morto antes: os 2 ajudantes abrem diretamente "Candidatar-me" (antes abria o Início). | `AJ3_24..26` |
| Candidaturas dos 2 ajudantes | PASSA | Sem equipamento 10,50 €/h, com equipamento 15,00 €/h. Depois de enviar vão para o Início (não há ecrã por baixo quando se entra pelo push). | `AJ3_27_*` |
| Responsável aceita os 2 (F8) | PASSA | O aviso "Ajudante adicionado à equipa." desaparece sozinho e a lista fica utilizável. Equipa 2 de 2. | `AJ3_28..30` |
| Próximo trabalho no Início do ajudante (F11) | PASSA | "Próximo trabalho / Corte de relva / 17/11 às 14:00 · Ajudante de Teste Jardineiro" nos 2 ajudantes. | `AJ3_31_*` |
| Vagas no Descobrir (F11) | NÃO VERIFICADO | Com 3 vagas e 2 preenchidas, o Descobrir não mostra o pedido a quem já está na equipa, e não havia um quarto jardineiro para o ver. | `AJ3_32`, `AJ3_33` |
| Equipa no detalhe do cliente sem reabrir (F10) | PASSA | Passou sozinho a "2 de 3" depois de o responsável mudar as vagas. | `AJ3_35` |
| Iniciar com fotos, concluir, confirmar, avaliar | BLOQUEADO | O trabalho é a 17/11 e a remarcação só aceita datas a partir de amanhã. Um trabalho de hoje só abre o "Iniciar" 1 hora antes (o mais cedo é Manhã, 09:00) e os testes foram às 04:30. Já tinha passado no TR-07 a 13/11. | |

### Bloqueio da app ao pedir o GPS (ambiente)

Nos 4 emuladores, ligados há cerca de 9 horas, a app ficou sem responder ("ProJardim isn't responding") ao tocar em "Usar GPS" ou "Usar a minha localização" logo depois de dar a permissão. A stack da ANR (guardada em `anr-jardineiro-gps.txt` e `anr-cliente-gps.txt`, fora do repositório) mostra a thread principal parada numa chamada ao serviço de localização do Android:

```
at android.location.ILocationManager$Stub$Proxy.unregisterGnssNmeaCallback
at android.location.LocationManager.removeNmeaListener
at o1.d.f (plugin geolocator, ofuscado pelo R8)
```

Depois de reiniciar os emuladores, o mesmo passo funcionou nos 4, incluindo com a permissão retirada e dada de novo (o caso que tinha bloqueado). Conclusão: é o serviço de GPS do emulador que encravou com o tempo ligado, não um erro da app. Fica a nota de que o `geolocator` faz esta chamada na thread principal: se aparecer uma ANR igual em telemóveis reais no Crashlytics ou na Play Console, rever a versão do plugin.

### Notas novas

- O Início do cliente não mostra em "Precisa de ti" um pedido de ajudantes à espera de aprovação (só aparece nos Alertas e no detalhe). Sem resposta, é aprovado sozinho em 24 horas.
- Aumentar as vagas de 2 para 3 depois de a equipa estar completa não pediu nova aprovação ao cliente (o primeiro pedido de ajudantes pediu). Confirmar se é a regra pretendida.
