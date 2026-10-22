# LocalServices — Decisions Log

> Registo de decisões técnicas importantes. Memória entre sessões Browser/Code.
> Formato: data — decisão — motivo.

## 2026-10-22 — Painel /admin e planos dos jardineiros (0059)

- **No mesmo link, em `/admin`** (pedido do Henrique), não num site à parte. O código do
  painel vai no mesmo bundle; isso não abre nada porque os dados só saem de RPCs `admin_*`.
- **Admin = linha em `admin_users` + aal2.** A tabela só se escreve por SQL Editor e as RPCs
  exigem o segundo fator TOTP na sessão (`auth.jwt()->>'aal'`). Uma conta normal que abra
  `/admin` só vê "Sem acesso" (`admin_whoami` não exige aal2, para dar essa resposta sem
  inscrever um fator).
- **A conta de admin não tem papel**: o router deixa `/admin` fora de todas as regras de
  papel e de onboarding.
- **O plano não é um papel.** `profiles.role` continua `worker`; o plano vive em
  `worker_plans` com validade, e acaba sozinho (volta a Grátis) sem cron: o plano em vigor
  é calculado (`worker_active_tier`).
- **Limite do Grátis: 5 trabalhos aceites por mês (hora de Lisboa), não propostas.**
  Limitar propostas deixava os clientes com menos propostas. Trigger BEFORE INSERT em
  `job_proposals`, para não depender da versão de `create_proposal`. Limite suave:
  propostas já pendentes podem ser aceites, porque falhar a aceitação do cliente era pior.
- **Sem preços nem forma de pagar na app** (regras de faturação das lojas): o plano é
  contratado e pago fora, e atribuído no painel.
- **Sem selo "Verificado" à parte**: "documentos verificados" é uma data no plano, e o
  selo Pro passa a querer dizer isso (o selo em si ainda não aparece aos clientes).

## 2026-10-22 — Pedir de novo ao mesmo jardineiro (0057, design A5)

- **A app nunca manda o id do jardineiro**: manda `direct_source_job_id` (o trabalho concluído)
  e um trigger BEFORE INSERT tira o jardineiro da proposta aceite, depois de validar que o
  trabalho é do cliente e está concluído.
- **Estado à parte** (`direct_status`), com o pedido sempre `open`: não mexe na máquina de
  estados nem nos ecrãs que leem `status`.
- **Visibilidade pela hora** (`job_reserved_for_other`), não pelo cron: o cron de 5 minutos só
  serve para os avisos e para marcar `expired`.
- **Ao abrir a todos**, `expires_at` passa a pelo menos agora + 48h, para os outros
  jardineiros terem tempo de propor.
- **Retirar a proposta conta como recusa**; recusar a proposta do escolhido abre a todos
  sem aviso ao cliente (foi ele que recusou).
- **Cartão só com 4 ou 5 estrelas ou sem avaliação**, e "Os teus jardineiros" sem os
  avaliados abaixo de 4.
- **Texto em "tu"** ("Os teus jardineiros", "Precisas outra vez?") em vez do "si" dos mockups,
  como o resto da app, e nomes sem artigo ("de Rui") para não adivinhar o género.
- **Um só botão** "Pedir de novo a {nome}" no fundo do trabalho concluído; o cartão é só
  contexto.
- **"Não voltar a mostrar"** da folha de explicação guardado no aparelho
  (`SharedPreferences`, por utilizador), sem coluna na BD.

## 2026-10-22 — Total estimado com a equipa em todos os ecrãs (0056)

- **Uma só conta** (`teamHourlyRate` em `core/utils/price_labels.dart`): preço por hora ×
  (1 + ajudantes × fator) × horas, fator 1 se os ajudantes trazem equipamento e 0,75 se não.
  Antes só "Propostas recebidas" contava a equipa; o formulário da proposta, o trabalho
  confirmado (cliente e jardineiro) e "Os meus trabalhos" mostravam só o responsável.
- **0056**: `get_worker_job_board` devolve `people_needed` e `helpers_equipment_required`
  (1 e false nas linhas de ajudante, que mostram o seu valor acordado). Sem a 0056 aplicada
  a app assume 1 pessoa.

## 2026-10-22 — WhatsApp com logótipo, folhas de avaliação e de perfil

- **Botão de WhatsApp único** (`AppWhatsAppButton`): o "Falar por WhatsApp" partia em três
  linhas ao lado do nome do cliente. Agora tem o logótipo do WhatsApp (pacote
  `font_awesome_flutter`, só pela fonte de marcas) e uma versão compacta "WhatsApp".
- **"Avaliar o trabalho"** passou para o `AppSheet` (fundo branco, fechar, campo e botão da
  app); o controlador do comentário vive no estado da folha.
- **Perfil do jardineiro nas propostas**: fundo cinzento da app em vez do verde do Material,
  cartão do topo com foto, zona, nota e serviços.
- **"Sobre a ProJardim"** com o logo, a versão, Termos, Privacidade e licenças (`AppAboutDialog`), em vez do `showAboutDialog` do Material em inglês.
- **Email de suporte**: um `SUPPORT_EMAIL` que não é um email (o site mostrava "Noth") cai no
  email por omissão.

## 2026-10-21 — Ligação entre cliente, jardineiro e ajudantes (0055)

As 7 melhorias do documento "Fluxos e regras de tempo", todas aprovadas pelo Henrique.

- **O cliente vê a equipa** (decisão RC2 que estava pendente): nome e foto dos ajudantes no
  pedido agendado. Reaproveita `get_accepted_helpers_for_job`, que passa a responder também
  ao cliente. Sem telefone: o contacto continua a ser só com o responsável.
- **Desistir só até à véspera.** No dia, só o responsável retira um ajudante e a vaga não
  reabre (o pedido já fechou): a equipa fica com quem resta, ou o pedido é cancelado.
- **Aviso da véspera** às 18h (Portugal), uma vez por pedido: responsável com vagas ou
  candidatos por decidir, cliente com o pedido por aprovar.
- **"Candidaturas até dd/mm"** na descoberta e na candidatura (a véspera do trabalho).
- **"O trabalho começou" para os ajudantes**, pelo trigger que já avisava das outras mudanças
  do trabalho (agora também em `started_at`).
- **Aviso no topo com a app aberta**: o push do sistema não aparece em primeiro plano, por
  isso a notificação nova aparece no `AppToast` com o ícone e o tom do tipo.
- **Aprovação automática ao fim de 24h** sem resposta do cliente, se o dia do trabalho ainda
  não chegou. O cliente é avisado no pedido e no aviso de aprovação.

## 2026-10-21 — Pedidos de ajuda no dia do trabalho, avisos novos, logo e splash

- **Pedidos de ajuda fecham no dia do trabalho (0054).** A partir da data confirmada (dia em
  Portugal) deixam de aparecer na descoberta e de aceitar candidaturas, o responsável já não
  pede ajudantes e não aceita candidatos, e o cliente já não aprova. O cron de hora a hora
  fecha os que ficaram abertos: pendentes recusados e avisados, equipa fica com os aceites
  (`filled`, vagas = aceites) ou o pedido é cancelado; aviso `help_request_closed` ao
  responsável. Os pedidos que nascem abertos em `accept_proposal` não fazem falhar a
  aceitação no próprio dia: ficam escondidos e o cron fecha-os. Triggers em vez de reescrever
  `approve_help_request`/`accept_help_candidate`.
- **Avisos só a quem faz o serviço.** `new_job_in_radius` e o novo
  `new_help_request_in_radius` vão para jardineiros no raio que oferecem o serviço, ou que
  ainda não escolheram serviços (para não ficarem sem avisos). Texto em "tu".
- **Foto dos ajudantes no cartão "Equipa"**: `get_accepted_helpers_for_job` devolve
  `avatar_url` (DROP + CREATE, a forma muda).
- **Ícone e splash com o logo** (pedido do Henrique, substitui a decisão antiga "sem
  splash"): `flutter_launcher_icons` (ícone adaptativo verde com a folha branca) e
  `flutter_native_splash` (fundo branco, logo a 128 dp; Android 12 com o círculo verde). O
  ecrã `/loading` mostra o mesmo logo (`AppLaunchScreen`) em vez de um spinner. Para mudar o
  logo: trocar os PNG em `assets/branding/` e correr `dart run flutter_launcher_icons` e
  `dart run flutter_native_splash:create`.
- **Push com o estilo da app**: ícone pequeno `ic_stat_projardim` (folha branca) e cor
  `#2E7D32`, no AndroidManifest (por omissão) e no `send-push` (precisa de novo deploy).

## 2026-10-21 — Bugs: avisos no topo, OTP, login e recuperação de senha

- **Avisos no topo (`AppToast`)** em vez da SnackBar do Material, que fica sempre em baixo,
  por cima dos botões de ação. Vive no Overlay do navigator raiz (sobrevive a `go`/`pop`,
  regra T4 igual: guardar `AppToast.of(context)` antes de navegar). Dois tons, `show`
  (verde) e `error` (vermelho); um aviso novo substitui o anterior; fecha sozinho em 4 s,
  com toque ou a arrastar para cima. As 76 chamadas a `showSnackBar` foram migradas.
- **Recuperação de senha mandava para o início** logo depois do código: o passo 1 abria o
  passo 2 com `push`, e quando a sessão de recuperação aparece o go_router reavalia o
  redirect com o URI da BASE da pilha (`/login`), que com sessão vai para o início do papel.
  Agora é `go`, e `resolveRedirect` nunca redireciona `/forgot-password/reset` com sessão
  (cobre também jardineiro com perfil incompleto e conta sem papel).
- **OTP:** as 6 caixas tinham 48 de largura fixa e transbordavam em ecrãs estreitos ou com
  o tamanho de ecrã/letra aumentado; agora encolhem.
- **Login e confirmar email:** o rodapé ("Não tens conta?", "Já tens conta com este email?")
  esconde-se com o teclado aberto, em vez de subir colado a ele por cima do "Entrar".

## 2026-10-21 — Termos e Política de Privacidade no Google Docs

- **Porquê:** a Meta e o Google pedem os URLs no ecrã de consentimento e ainda não há site.
- **Como:** `AppLinks.termsUrl`/`privacyPolicyUrl` com os Google Docs publicados por
  omissão (`--dart-define=TERMS_URL`/`PRIVACY_POLICY_URL` para mudar), abertos no browser
  por `app_legal_links.dart`. `AppLegalConsentText` é a frase com toque, partilhada pelo
  registo e pelo login social. Email de suporte por omissão passa a `projardim26@gmail.com`.

## 2026-10-21 — Botão do Facebook escondido por omissão

- **Porquê:** a verificação de negócio da Meta não aceita `netlify.app` e pede empresa ou
  atividade registada, por isso a app da Meta fica em Development. Aí, quem não é tester
  recebe um erro da Meta ao tocar em "Continuar com Facebook".
- **Como:** `AppLinks.facebookLoginEnabled` (`--dart-define=FACEBOOK_LOGIN_ENABLED=true`,
  por omissão `false`). Sem ele o botão e a menção ao Facebook na frase dos termos não
  aparecem. O deploy web lê a variável `FACEBOOK_LOGIN_ENABLED` do GitHub. O código do
  OAuth do Facebook fica igual; ligar é só a flag (`SETUP.md` 7.4).

## 2026-10-19 — Notificações (A4)

- **Uma vista para os dois papéis:** `core/widgets/app_notifications_view.dart` só desenha;
  `notifications_screen.dart` liga `allNotificationsProvider` e a apresentação vem de
  `notifications/application/notification_presentation.dart` (funções puras).
- **Ícone e tom por tipo** pela legenda do design, só com os cinco tons: success (proposta,
  aceite, lembrete do dia, concluído), waiting (candidato, nova data), info (editado,
  trabalho feito, pedido de ajudantes, iniciado, pedido novo na zona), cancelled (cancelado,
  retirado da equipa), neutral (expirado, não escolhido, retirado). Não lida é o fundo verde
  claro e o ponto, não um tom.
- **"(Serviço, dd/mm)" no título:** a 0049 já grava esse contexto no fim do corpo; a app
  muda-o para o título, nas notificações antigas e novas, sem migration. As de hoje levam
  "Há 10 min" no fim do corpo; as outras ficam pela secção (Hoje, Ontem, Mais antigas).
- **Filtro "Trabalhos"** deixa de fora as oportunidades novas (pedido novo na zona, vaga de
  ajudante reaberta). As contagens são das 50 mais recentes que a app carrega.
- **Secções como um cartão com linhas**, como no design. "Marcar todas como lidas" deixou de
  ser otimista: espera pelo servidor e pela lista nova.
- **"Confirmar conclusão"** aparece no aviso de trabalho feito enquanto não foi lido e abre o
  pedido (onde se veem as fotos antes de confirmar), o mesmo destino do toque.
- **Mantido fora do design:** o ecrã continua fora do ShellRoute (sub-fluxo com voltar),
  como antes; "Alertas" na barra do cliente continua a abri-lo por cima.

## 2026-10-19 — Propostas recebidas do cliente (A3)

- **Ecrã separado em vista e integração:** `widgets/client_proposals_view.dart` só desenha
  (lista, estados e a folha); `client_proposals_screen.dart` lê os providers, ordena e
  formata com as funções puras de `application/client_proposal_labels.dart`.
- **Valor grande = total estimado com a equipa incluída** ("24 a 48 €", ou "48 €" com uma só
  estimativa de horas); por baixo as horas e o preço por hora ("2 a 4h · 12,00 €/h"), que é o
  compromisso real do jardineiro. Sem horas mostra só o preço por hora. A lista ordena por
  esse mesmo total mínimo (antes ignorava a equipa); `compareByEstimatedPrice` saiu.
- **Data:** dia da semana e hora exata ("Qui, 23/10 · 9:00"), não manhã/tarde como no
  design, porque a proposta guarda a hora; sem data, "Data a combinar com o jardineiro".
- **"Recomendada"** continua a ser só destaque (borda e chip verde, botão "Escolher" cheio),
  pela mesma regra: melhor média com pelo menos 3 avaliações.
- **Folha:** `AppSheet` com resumo, três linhas fixas e "Aceitar proposta · valor". Fecha só
  depois de o servidor aceitar; erro fica dentro da folha; proposta indisponível troca a
  folha pelo aviso "Esta proposta já não está disponível" com "Ver propostas".
  `AppSheet.show` ganhou `enableDrag` para não se fechar a meio do pedido.
- **Texto do pagamento adaptado:** "Pagas diretamente ao jardineiro, depois de confirmares que
  o trabalho está feito", porque a app não trata pagamentos.
- **Mantido fora do design:** a nota que o jardineiro escreve na proposta (até 2 linhas).

## 2026-10-19 — Os meus trabalhos do jardineiro (A2)

- **Três tabs montadas ao mesmo tempo** (`IndexedStack`, uma `PageStorageKey` por tab) em
  vez do fade: cada tab guarda o scroll e pagina por si. Os rótulos chegam formatados
  ("Pendentes 3", "Agendados 4", "Histórico" sem número) e as contagens vêm do
  `total_count` da RPC.
- **Badge = estado do trabalho**, com "Não selecionada" (e afins) só quando não houve
  trabalho para este jardineiro. "Agendado", "Em curso", "À espera do cliente" (âmbar),
  "Concluído", "Cancelado" (vermelho quando o trabalho era dele, cinzento quando não) e
  "Expirado" (cinzento, tanto `no_response` como expirado depois da data). "Ajudante" é um
  chip de papel ao lado, não um estado.
- **Cartões:** ícone do serviço, título, uma linha de detalhe por tab e papel ("Hoje · 9:00 ·
  Cascais", "com João Pires", "Feito a 18/10 · confirma automaticamente em 31h",
  "cancelado pelo cliente", "o cliente escolheu outra proposta") e o valor estimado a verde
  só nos do responsável. Histórico agrupado por mês, fechados a cinzento; páginas seguintes
  entram sem animação.
- **Migration 0053:** `get_worker_job_board` passa a devolver `service_type_id`,
  `location_area`, `marked_done_at`, `started_at`, `cancel_reason`, `cancelled_by_client`/
  `cancelled_by_me` (booleanos, sem ids) e `job_updated_at`. Sem ela a app funciona: ícone
  pelo nome do serviço, localidade tirada da morada, data pela marcada ou de criação, e
  "cancelado" sem dizer por quem.

## 2026-10-19 — Detalhe do meu trabalho do jardineiro (A1)

- **Mesmo ecrã, três composições:** `worker_my_job_detail_view.dart` escolhe pelo estado real
  (proposta aceite + `confirmed`, `cancelled`/`no_response` ou `completed`); não há enum novo de
  estado. Pendente, não selecionada, retirada e à espera de confirmação continuam como estavam.
- **Agendado:** linha de estado sem cartão, cartão com ícones (data abreviada "Qui, 22/10 ·
  9:00", local com "Abrir localização no mapa", valor), cliente com "Falar por WhatsApp", cartão
  "Equipa" com um círculo por vaga (iniciais dos ajudantes aceites) e candidatos por decidir, a
  regra do dia anterior sempre visível por cima de Remarcar/Cancelar, e "Iniciar trabalho" com
  cadeado e "Disponível a partir das 8:00 de qui, 22/10". A descrição do pedido fica (o design
  não a mostra, mas o jardineiro precisa dela).
- **Cancelado ou expirado:** cartão vermelho (ou cinzento com ampulheta quando expirou), dados
  a cinzento só com a localidade, cliente sem WhatsApp e "Ver pedidos disponíveis" no fundo. A
  data do cancelamento vem de `updated_at` (não há `cancelled_at`; num pedido cancelado é a
  última alteração).
- **Concluído:** "Concluído a dd/MM" (de `updated_at`) e o tempo registado, em vez de "A Sofia
  confirmou": o pedido também fica concluído sozinho 48h depois (0052) e a app não distingue os
  dois casos. Fotos de antes/depois, lista "Avaliações" (cliente e ajudantes, com seta até
  avaliar, estrelas depois) e a avaliação que o cliente deixou neste trabalho
  (`get_my_ratings_received`, filtrada pelo pedido e pelo cliente).

## 2026-10-19 — Navegação lateral em tablet deitado e PC (U8)

- **Já existia (`AppAdaptiveShell`, PR #15):** não se criou outra shell. Mudaram só os valores
  e o topo da lateral.
- **Valores do design:** coluna de conteúdo de 640 para 720 (`AppBreakpoints.contentMaxWidth`,
  vale para todos os ecrãs, detalhes incluídos, sem segundo painel). Lado menor mínimo para a
  lateral de 600 para 480 (`compactShortestSide`): telemóvel deitado continua com bottom nav,
  tablets e janelas baixas de PC passam a lateral mais cedo. O corte nos 840 fica igual.
- **Topo da lateral:** marca (`AppBrandBadge`) e "+" quadrado de cantos redondos com sombra,
  com entrada escalonada, em vez do botão redondo. Lateral com 92 de largura.

## 2026-10-19 — Conta, suporte, terminar sessão e eliminar conta (U7)

- **Sem widgets novos onde já havia:** o bloco perigoso continua a ser um `AppAccountMenuGroup`
  (as linhas `destructive` ficam a vermelho e sem seta) e os diálogos continuam a ser
  `AppConfirmDialog`, que ganhou `stepLabel` ("1/2"), ícone opcional e `outlinedConfirm`.
- **A minha conta (cliente):** título grande, cartão branco com "Cliente · N pedidos" e seta
  (abre o perfil, em vez da roda dentada), um só grupo com pedidos, avaliações, definições,
  suporte e "Sobre". Saíram os três números (pedidos, em curso, concluídos). O jardineiro
  mantém o cartão digital e os grupos; só mudam o título e o bloco perigoso.
- **Contacto e suporte:** folha com ícone, "Respondemos em 1 dia útil" (`AppLinks.
  supportResponseTime`), o email e "Copiar email" / "Escrever". "Escrever" passa a abrir a app
  de email (`mailto:` com assunto): é suporte da ProJardim, fora da app; o contacto entre
  cliente e jardineiro continua só por WhatsApp. Sem app de email, avisa para copiar.
- **Terminar sessão e eliminar conta:** diálogos só com texto, como no design. Eliminar: passo
  1/2 com as três consequências reais da 0049 (dados apagados, avaliações como "Conta
  eliminada", trabalhos em curso fechados antes) e "Continuar" só com rebordo; passo 2/2
  "Não dá para desfazer." com "Eliminar conta" a vermelho. O erro do servidor continua dentro
  do diálogo.

## 2026-10-19 — Destaques e redes, cartão público e avaliações (U6)

- **Adaptado ao que já existia (0051):** o editor continua a ser a secção "Destaques e redes"
  de `WorkerProfileEditScreen` e o cartão público continua em `/w/:id`; não se criou rota nova.
- **Editor:** "Em destaque" com as linhas e "+ Adicionar destaque · N de 5", que abre uma
  `AppSheet` (recusa vazio e repetido). Fechar a folha sem adicionar limpa o campo, porque o
  "Guardar" junta o texto pendente à lista. Redes em linhas com ícone e nome à esquerda;
  "Ver como o cliente vê" em botão largo. Saíram os dois textos de ajuda.
- **Cartão público:** sem título "Perfil", foto com aro, nome, zona e "★ 4,9 · N avaliações".
  O raio ("até 15 km") do design não aparece: `worker_public_card` (0033) não o expõe de
  propósito. As estrelas abrem a folha de avaliações só com sessão (a RLS de `ratings` não
  deixa o visitante ler as avaliações). Os serviços continuam por baixo.
- **`WorkerShowcaseSection`:** cartões "SOBRE" e "EM DESTAQUE", "VER TRABALHOS E REDES" com
  botões em duas colunas e a nota "Informação partilhada pelo jardineiro.". Igual no cartão
  público e na folha de avaliações.
- **Folha de avaliações:** uma avaliação por cartão (inicial, nome, data, estrelas e
  comentário). Passam a aparecer também as avaliações sem comentário. Vazio com `AppEmptyState`.

## 2026-10-19 — Autenticação: login, código do email e escolha de papel (U5)

- **Adaptado, não copiado:** o código de referência separava cada ecrã em vista + wrapper
  com callbacks. Os três ecrãs já funcionavam com Riverpod e o router decide os destinos,
  por isso só mudou a apresentação; a lógica (signIn, OAuth, `verifySignupCode`,
  `createProfile`, contagem de 60 s do reenvio) ficou igual.
- **Login:** fundo branco, alinhado à esquerda, marca 52, "Senha" em vez de "Password",
  "Esqueceste-te da senha?", "Criar conta" no rodapé. "Termos" e "Política de
  Privacidade" a verde na frase dos botões sociais, mas sem toque: ainda não há páginas.
- **Código do email:** sem barra de título (só a seta), título grande, email a negrito na
  frase, "Confirmar" logo por baixo das caixas, "Reenviar em 0:42" e caixa cinzenta no fundo
  com "Entra" (vai para /login) e "recupera a senha" (vai para o pedido de código de
  recuperação com o email preenchido). Mantém-se o `AppOtpInput` de 6 caixas.
- **Escolha de papel:** aviso a âmbar, cartões compactos em linha com ✓, "Os teus dados" com
  "+351" fixo antes do telemóvel (só ajuda visual, outros indicativos continuam aceites). O
  texto por baixo diz quem contacta conforme o papel (`phoneUsageHint`). "Os teus dados" só
  aparece quando ainda falta o telefone (conta Google/Facebook), como antes: no registo por
  email o nome e o telefone já foram pedidos.

## 2026-10-19 — Fluxo do ajudante e lobby da equipa (U4)

- **As minhas candidaturas:** pílulas "Pendentes N / Aceites N / Histórico" em vez das três
  secções seguidas; abre na primeira com candidaturas. Cartão pendente com inicial do
  responsável, "À espera", data/zona/equipamento, caixa "Sugestão do responsável" e
  "À espera da decisão de X" com "Retirar". Datas como "Sábado, 25/10 · 8:30".
- **Trabalho como ajudante:** cabeçalho "Ajudas X" sem cartão, timeline num cartão branco
  com a frase do passo numa caixa verde, detalhes em linhas rótulo/valor com "Mapa", cartão
  "RESPONSÁVEL" com ★ e WhatsApp, "Desistir" em texto vermelho.
- **Lobby:** saiu o cartão "Responsável" (é o próprio); o serviço e a data passam para o
  subtítulo de "Equipa". Cartão "Vagas preenchidas 1 de 2" com "Alterar vagas" e "Fechar
  pedido de ajuda" lá dentro; secções "Aceites · N" e "Por decidir · N"; ajudante com
  "Na equipa", WhatsApp e "Retirar"; candidato sem badge, com "Aceitar" e o X de recusar
  (mantido, o design não o mostra mas tirá-lo era perder a ação).
- **Diálogos:** "Alterar vagas" e "Fechar pedido de ajuda?" passam a `AppConfirmDialog`
  (`message` ficou opcional). O máximo de vagas continua 10 (limite da RPC), não 5.
- **Texto de fechar diferente do design:** o design diz "Quem já está na equipa continua",
  mas `cancel_help_request` (0049) também tira os aceites. Decisão do Henrique (19/10): fica
  como está; o texto diz o que a RPC faz e para tirar só uma pessoa usa-se "Retirar".

## 2026-10-19 — Criar pedido passo 2 e Editar pedido (U3)

- **`JobScheduleFields` partilhado:** três botões (Data fixa, Flexível, Disponibilidade) e por
  baixo só o campo do modo escolhido, com fade. Data escrita como "Sábado, 25/10"
  (`weekdayDateLabel`). Saíram os cartões de opção (`JobOptionCard`) e o enum
  `ClientJobUrgency`: o modo da data passa a ser `DateMode` direto.
- **Urgência separada da data:** "Normal"/"Urgente" ao lado da dimensão, para qualquer modo
  de data (antes só existia com data fixa). A base de dados já aceitava as combinações.
- **Dimensão** num chip que abre a folha "Dimensão aproximada", porque o U3 só mostra o valor
  e o passo 2 continua a ser o único sítio onde se escolhe.
- **Mapa:** "Onde?", pin verde, "Usar a minha localização" por cima do mapa. A dica diz
  "Toca no mapa" e não "Arrasta o pin", porque o flutter_map não arrasta marcadores sem um
  plugin extra; o pin muda com um toque.
- **Editar pedido:** fechar (X), aviso azul aos jardineiros que propuseram, contador
  "118 / 10 mín.", SnackBar "Pedido atualizado. Avisámos 2 jardineiros." A morada continua
  editável (o U3 não a mostra, mas a RPC `update_job_request` suporta e tirá-la era perder
  uma funcionalidade). Pedido que já saiu de aberto mostra "Este pedido já não pode ser
  editado" com "Ver pedido"; o texto sobre Remarcar só aparece se o pedido está confirmado.

## 2026-10-19 — Inícios dos dois papéis e "+" do jardineiro (U2)

- **Cabeçalho igual nos dois:** "Bom dia/Boa tarde/Boa noite" (`dayGreeting`), "Olá, Nome" e o
  sino `HomeNotificationButton` com ponto vermelho. Saíram o avatar, a data e o emoji.
- **Cliente:** pedido à espera de confirmação diz quanto falta para a confirmação automática
  ("Confirma em 46h."), contado de `marked_done_at` + 48h.
- **Jardineiro:** Pendentes/Agendados em cartões brancos que abrem a aba certa de "Os meus
  trabalhos"; "O que falta fazer" com o título fora do cartão; "Trabalho hoje às 9:00" com
  "Iniciar disponível a partir das 8:00" (ou "Em curso"); "trabalhos por concluir".
  Oportunidades em lista (até 3) com serviço e dimensão, zona, distância e quando, e "Urgente";
  "Ver todas" abre a aba Pedidos.
- **"Próximo trabalho" mantido** no Início do jardineiro, apesar de não estar no U2, para não
  tirar uma funcionalidade sem decisão do Henrique.
- **"+" do jardineiro:** folha "O que queres fazer?" com Encontrar trabalho e Pedidos de ajuda,
  e Cartão frota só quando o cartão está ativo (pedido do Henrique). O estado do cartão é lido
  no `WorkerShell` para já estar carregado quando a folha abre.
- **Não aplicado:** "À espera de ti" como estado curto do cliente, porque o mesmo label curto
  aparece também do lado do jardineiro.

## 2026-10-19 — Componentes base em falta (U1)

- **Novos em `core/widgets/`:** `AppConfirmDialog`, `AppEmptyState`, `AppSheet`, `NextStepRow`,
  `TodoRow`, a partir do código de referência do Claude Design, adaptados ao que já existia.
- **Não recriados:** `AppBarTitle`, `AppBarStatusBadge` e `SocialSignInButtons` já existiam e
  são usados em muitos ecrãs; a referência trocava-lhes a API. Ficaram, com o
  `AppStatusBadge` a ganhar `dense` e o mapa de labels curtos a ficar público
  (`shortStatusLabel`) para o `NextStepRow`.
- **Diálogos:** os 10 `AlertDialog` de confirmação passaram a `AppConfirmDialog` (perigo a
  vermelho para cancelar, retirar, desistir, sair e eliminar conta). Os 4 com formulário
  ficaram como estavam.
- **Tamanhos:** os valores fixos da referência (48, 68, 40, 420…) entraram como tokens em
  `AppSizes`; o fundo verde claro das linhas com ação é `AppColors.primaryTint`.
- **Texto do design não usado:** "O jardineiro recebe o pagamento" no diálogo de confirmar
  conclusão, porque a app não trata pagamentos.
- **Google e Facebook:** "G" desenhado com as 4 cores oficiais (sem asset nem pacote novo) e
  botão do Facebook azul da marca com texto branco, como no design.

## 2026-10-19 — O código passa a seguir o design: iniciar trabalho e 48h (0052)

- **Sem estado novo:** "Em curso" é `confirmed` com `started_at`. Evita mexer em todas as
  RPCs, listas e políticas que filtram por `status`.
- **Janela de início:** 1h antes da hora combinada, na hora de Lisboa; sem hora, a partir do
  dia; sem data, sempre. A app calcula o mesmo para o botão e a BD volta a verificar.
- **Fotos:** até 3 de antes (opcionais) e 3 de depois (recomendadas), caminhos validados na
  BD (têm de ser do próprio jardineiro, deste trabalho, e existir no Storage).
  `completion_photo_path` continua com a 1.ª de depois para compatibilidade.
- **48h:** o lembrete das 24h e a confirmação passam para `auto_confirm_completed_jobs`, de
  hora a hora; o `send_job_reminders` diário deixava o lembrete até 24h atrasado.
- **Contacto:** o design mostra telefone e chat; mantém-se só WhatsApp (regra do projeto).
- **"Valor a receber":** a app mostra "Valor acordado" (o preço da proposta); não há regra
  de comissão para calcular outro valor.
- **Textos e espaçamento:** "Falar por WhatsApp", "Tentar novamente", "À espera de…",
  "jardineiro", sem travessões na UI. A escala 4 a 32 do design entrou em `AppSpacing` e os
  valores soltos dos ecrãs passaram a usar os tokens, sem mudar medidas.

## 2026-10-18 — Destaques e redes sociais no perfil do jardineiro (0051)

- **Onde:** nova secção "Destaques e redes sociais" em Editar perfil (a apresentação/bio já
  existia na vista geral e continua lá). O cliente vê tudo na folha que abre ao tocar no
  jardineiro numa proposta, que passa a abrir sempre (antes só com avaliações), e no
  cartão `/w/:workerId`.
- **Formato:** destaques em `text[]` (5 × 80); links em `jsonb` `[{kind, url}]` com um campo
  por tipo (Instagram, Facebook, Site, Outro) em vez de uma lista livre: mais simples de
  preencher no telemóvel e chega para mostrar a empresa ou fotos. `@nome` vira o link
  completo; `http://` vira `https://`.
- **Segurança:** os links abrem fora da app e são vistos por visitantes sem conta, por isso
  a BD tem CHECK (só `https://`, sem `user@`, tamanho máximo) e a app volta a filtrar ao ler.
  Escrita pelo UPDATE owner-only já existente em `worker_profiles`, sem RPC nova.
- **Sem selo "Verificado":** a secção diz "Informação partilhada pelo jardineiro".
- **Compatibilidade:** `WorkerProfile.showcaseSupported` só fica `true` se a linha lida já
  tem as colunas; até lá a app não as envia no UPDATE (senão o PostgREST recusava gravar o
  perfil inteiro) e a secção diz "Em breve".
- **Numeração:** 0051, porque a thread do login com Google e Facebook pode usar a 0050.

## 2026-10-18 — Login com Google e Facebook

- **Um só caminho para tudo:** `signInWithOAuth` do Supabase (página do Google/Facebook no
  browser, volta por redirect), em vez de `google_sign_in`/`flutter_facebook_auth` nativos.
  Funciona igual na web, Android e iOS e só precisa de um cliente OAuth "Web" no Google e de
  uma app na Meta, sem SHA-1, `google-services.json` nem chaves nas apps. Custa um salto ao
  browser no telemóvel.
- **Volta às apps:** deep link `pt.projardim.app://login-callback` (intent-filter no
  `AndroidManifest.xml`, `CFBundleURLTypes` no `Info.plist`); o `supabase_flutter` lê a
  sessão do link e o router manda `/login-callback` para `/`. Na web volta a
  `<origem>/` (com `?from=` se havia destino guardado).
- **Conta nova:** sem trigger nem migration. Continua a ser `/choose-role` a criar o perfil;
  aí, sem telemóvel nos dados (conta social), o ecrã pede nome (já preenchido com o da
  conta) e telemóvel, porque o contacto é por WhatsApp.
- **Foto:** a app só mostra fotos do Storage do projeto (`StorageUrls`), por isso ao criar o
  perfil a foto da conta é descarregada e enviada para `avatars/<id>.jpg` (Google em 400 px).
  Melhor esforço: se falhar (na web o browser pode bloquear o download por CORS), a conta é
  criada sem foto.
- **Termos:** quem entra assim não vê a caixa dos termos do registo; os botões têm por baixo
  "Ao continuar com Google ou Facebook aceitas os Termos e a Política de Privacidade".
- **Apple:** fica para quando houver app iOS publicada (a App Store exige-o se houver outro
  login social).

## 2026-10-18 — Tokens do design system, acessibilidade e docs em dia

- **Cores soltas trocadas por tokens:** os ~30 `Colors.red`/`redAccent` (SnackBars de erro,
  botões destrutivos, borda de erro do `AppTextField`) passaram a
  `AppStatusColor.cancelled.foreground`, que já era o padrão nos ecrãs mais recentes. Estrelas
  de avaliação mostradas (`Colors.amber`) passaram a `AppColors.logoAccent`, a mesma cor do
  `RatingStarsInput`. Ícones das notificações com `AppStatusColor` (verde = `primary`, laranja
  = `waiting`, azul = `info`, cinza = `neutral`). Ficam de fora as 4 cores do logótipo Google
  (marca de terceiros) e o `inactiveColor` do indicador do onboarding (decorativo).
- **Acessibilidade:** todos os `IconButton` têm `tooltip` (é o que o TalkBack/VoiceOver lê).
  Os olhos das passwords dizem "Mostrar/Esconder palavra-passe" conforme o estado.
- **Logs:** tirados os `debugPrint('[UPLOAD_PHOTO] ...')` (corriam também em release).
- **`docs/architecture.md` → `docs/ARCHITECTURE.md`:** o CLAUDE.md e 13 referências usavam
  maiúsculas; no Windows funcionava, no Linux (CI, sessões cloud) o ficheiro não era encontrado.
- **Docs:** `STATUS.md` e `improvements.md` tinham SA1/SA2/SA3, M4, P-8-8, P1/A1 e o reskin de
  `client_jobs_screen` como abertos; todos já estavam resolvidos (tabela em `improvements.md`).

## 2026-10-18 — Decisões pendentes, todas feitas (defaults escolhidos pelo Claude)

O Henrique pediu para fazer tudo o que estava por decidir. Defaults escolhidos:
- **Mensagens:** sem chat na app (regra do projeto); rotas `/client/messages` e
  `/worker/messages` removidas.
- **Disponibilidade em texto livre:** quarta opção no passo 2 do pedido ("Indicar
  disponibilidade", até 200 caracteres), mostrada no lugar da data dos dois lados.
- **Editar pedido:** enquanto está aberto, tudo menos as fotos; quem já propôs é avisado.
- **Eliminar conta:** anonimiza (perfil "Conta eliminada", dados pessoais limpos, login
  bloqueado) em vez de apagar, porque avaliações e histórico de outras pessoas
  referenciam o perfil. Recusa com trabalho em curso. Fotos no Storage ficam (o Supabase
  não deixa apagar por SQL).
- **Propostas sem fim:** pedido sem data fixa com propostas e sem escolha fecha aos 14 dias.
- **Remarcar atrasado:** permitido depois da data; continua bloqueado no próprio dia.
- **Report de problema:** suspende a confirmação automática daquele trabalho.
- **Avaliação do cliente:** deixa de ser copiada para os ajudantes.
- **Avisos:** levam o serviço e a data; ajudantes avisados de nova data, trabalho feito,
  concluído e lembrete do dia.
- **Equipa:** o responsável pode alterar vagas, fechar o pedido de ajuda e retirar
  ajudantes. Ecrã próprio do ajudante em `/worker/help/:id`. Cartão "O que falta fazer"
  no Início do jardineiro. Botão central do jardineiro abre atalhos.
- **Outros:** publicar de novo, voltar ao destino depois do login, puxar para atualizar,
  telefone gravado como `+351…`, preços com vírgula também no jardineiro.

## 2026-10-18 — Revisão de todos os fluxos (cliente, jardineiro, ajudantes)

- Pedida pelo Henrique ("para o worker e ajudantes depois não fica muito claro").
  Duas auditorias de leitura, depois correções só na app e a migration 0048.
- Início do cliente: uma só lista de pedidos em curso, o que precisa do cliente
  primeiro, com uma linha de próximo passo (igual na aba Pedidos).
- Jardineiro: cartão "Equipa" no trabalho (o lobby não tinha entrada na app), sem
  `pop` depois de ações abertas por notificação, listas invalidadas num só sítio
  (`invalidateWorkerLists`), pedidos já tomados só de leitura, regras de
  cancelar/remarcar por dias como na BD, aba "Concluídos" passa a "Histórico".
- Cliente: avaliação do jardineiro só por `submit_client_rating` (o botão antigo
  chamava a RPC do responsável e falhava sempre), falha de rede no arranque vai para
  `/session-error` em vez de `/choose-role`, voltar seguro na web, rascunho do pedido
  preservado e limpo ao trocar de conta, terminar sessão com confirmação.
- 0048 (por aplicar): candidatura por RPC (`apply_to_help_request`, permite voltar a
  candidatar-se), retirar candidatura pendente, triggers de avisos (proposta de pedido
  cancelado/expirado, candidaturas fechadas quando o trabalho é feito, novo candidato,
  pedido de ajudantes ao cliente), um pedido de ajuda ativo por trabalho, telefone dos
  ajudantes aceites, `job_status` no board.

## 2026-10-17 — Mais testes automáticos e redirect do router testável

- A decisão de redirect saiu de `RouterNotifier.redirect` para a função pura
  `resolveRedirect` (`core/router/route_guard.dart`), sem mudar o comportamento: o
  notifier lê os providers e delega. Assim as regras de acesso (sem sessão, sem papel,
  cliente/jardineiro, setup incompleto, cartão público `/w/`) têm testes.
- Testes novos: router, preços, datas, força da password, `friendlyError`, enums da BD,
  `HelpAcceptance.message` e um teste de widget do lobby de ajudantes. Total 67, no CI.

## 2026-10-17 — Mensagem do candidato visível ao jardineiro principal

- Antes: `help_acceptances.message` (0034) era gravada pelo ecrã de candidatura mas a
  RPC `get_candidates_for_help_request` (0040) não a devolvia, por isso ninguém a via.
- Agora: migration 0047 (DROP + CREATE, porque o `RETURNS TABLE` muda de forma) junta a
  coluna `message`; mesma autorização (`is_principal_worker_for_help_request`, por
  `auth.uid()`) e o REVOKE/GRANT da regra da 0042. A app lê-a (vazia ou só espaços
  conta como sem mensagem) e mostra-a num bloco "Mensagem" no cartão do candidato.
- Compatível nos dois sentidos: a app nova sem a 0047 aplicada simplesmente não mostra
  o bloco; a app antiga ignora a coluna nova.

## 2026-10-17 — Confirmação de email por código de 6 dígitos

- Antes: ligar "Confirm email" no Supabase partia o registo (o `signUp` deixa de abrir
  sessão e `choose_role_screen` cria o perfil com `currentUser`). O ecrã
  `/verify-email` era cosmético e `/email-confirmed` esperava um deep link nunca feito.
- Agora (escolhido pelo Henrique entre as tarefas sem configuração): mesmo padrão da
  recuperação de senha, código no email e `verifyOTP(type: signup)`, sem deep links nem
  app_links. `signUp` devolve se precisa de confirmação; o registo vai para
  `/verify-email` (OTP + reenviar com 60s) e, com a sessão aberta, para `/choose-role`.
  Login de conta por confirmar reenvia o código e vai para o mesmo ecrã. Com a opção
  desligada no Supabase o fluxo é o de sempre, sem o ecrã cosmético depois do papel.
- Removidos `email_confirmed_screen.dart`, a rota `/email-confirmed`,
  `emailConfirmationModeProvider` (atalho de debug) e os TODOs de deep link no
  AndroidManifest e no Info.plist. O nome e o telefone vêm de `userMetadata` se a app
  fechar entre o registo e o código.
- Configuração (template "Confirm signup" com `{{ .Token }}`, ligar a opção): `SETUP.md`
  passo 3.3.

## 2026-10-17 — Validação de telefone e link de WhatsApp com indicativo

- Bug encontrado: os 5 sítios que abrem o WhatsApp faziam `wa.me/<número sem espaços>`.
  Um número português escrito sem `+351` (o normal) abria `wa.me/912345678`, que o
  WhatsApp não reconhece. Agora há um helper único, `openWhatsAppOrWarn`
  (`core/utils/phone_utils.dart`), que normaliza para `351912345678` e mostra uma
  SnackBar se o número for inválido. Cobre também os números já gravados.
- Validação no registo e nos dois ecrãs de editar perfil: 9 dígitos portugueses (2, 3 ou
  9 à frente), com ou sem `+351`/`00351`, ou número estrangeiro com indicativo.
  Espaços, hífenes, pontos e parênteses são aceites. O número continua a ser gravado como
  foi escrito.
- Sem migration: os limites na BD que estavam na lista (`people_needed >= 1`,
  `slots_needed >= 1`) já existem na baseline, e `hourly_rate > 0` é validado por
  `create_proposal`, a única forma de criar propostas desde a 0042. Um CHECK no telefone
  na BD bloquearia qualquer UPDATE de perfil de quem já tem um número antigo inválido.

## 2026-10-17 — Limpeza sem decisões, CI e guia de configuração

- **CI** (`.github/workflows/ci.yml`): `flutter analyze` e `flutter test` em cada PR e
  push para `main` que mexa em `servicesapp/`. Falha também com `info`, para o analyze
  ficar a zero.
- **Avisos do analyze corrigidos (5 para 0):** `control_flow_in_finally` no lobby de
  ajudantes (o `return` dentro do `finally` passou a `if (mounted)`; os callbacks já
  apanham os erros, por isso não muda comportamento) e os 3 `unused_field` de
  `_NotificationCategory` (ficou só `job`; os outros valores voltam quando houver
  notificações dessas).
- **Rating sheets renomeados:** `submit_rating_sheet.dart` / `showSubmitRatingSheet` e
  `worker_ratings_sheet.dart` / `showWorkerRatingsSheet`.
- **Domínio e email de suporte por `--dart-define`** (`APP_PUBLIC_URL`, `SUPPORT_EMAIL`,
  em `AppLinks`). Opcionais: sem eles a web usa o próprio site e as apps o placeholder.
  O deploy web lê-os das Variables do GitHub, se existirem.
- **`avatar_url` sem migration:** a app só aceita fotos de perfil do Storage do próprio
  projeto (`StorageUrls`, prefixo derivado de `SUPABASE_URL`), aplicado nos modelos e
  repositórios que leem `avatar_url`. Fecha o risco do review (um URL externo revelava o
  IP de quem abre o perfil) sem depender do domínio final. A coluna continua texto livre
  na BD; um CHECK por migration ficaria preso ao ref do projeto e não acrescenta proteção
  a quem vê, que é onde estava o risco.
- **Overflow de 3px nas abas:** não reproduzido (bottom nav testada a 320/360/411 de
  largura e texto até 1,3x sem overflow). Fica na lista de testes manuais do `SETUP.md`.
- **Confirmação de email:** não pode ser ligada só no dashboard. O registo cria o perfil
  logo a seguir ao `signUp` e precisa de sessão; com a confirmação ligada o registo
  parte. Fica documentado no `SETUP.md` como tarefa de código (código de 6 dígitos, como
  a recuperação).
- Docs alinhados com a BD (todas as migrations até à 0046 aplicadas): `database_schema.md`,
  `ARCHITECTURE.md` secções 7, 9, 12, 14 e 16, `STATUS.md`, README das migrations.
  Guia novo `docs/SETUP.md`.

## 2026-10-17 — Versão web (Flutter web) e PWA para iPhone

Pedido do Henrique: sem Mac nem conta Apple, os utilizadores de iPhone usam a app pelo browser. Guia completo em `docs/web.md`.

- Flutter web, não uma reescrita. A mesma base de código compila para web (`flutter build web`).
- Fotos passam a circular como `XFile` em vez de `dart:io` `File` (na web não há ficheiros). Helper único em `core/utils/picked_photo.dart`: pré-visualização (`pickedPhotoImage`) e bytes para upload (`photoBytesForUpload`, compressão nativa igual à de antes no telemóvel; na web o próprio picker redimensiona para 1600px, qualidade 70). Avatares passam de `upload(File)` para `uploadBinary(bytes)`.
- Pesquisa de morada: `GeocodingService.searchAddress`. No telemóvel continua o package `geocoding`; na web (que não tem implementação) usa a pesquisa do Nominatim limitada a Portugal. Na web os pedidos ao Nominatim vão sem `User-Agent` próprio (o browser não deixa e obrigaria a preflight CORS).
- Cartão frota na web: sem OCR (ML Kit só existe em Android/iOS); o passo 1 explica e segue para o ecrã de confirmação com os campos vazios. Push FCM continua desligado na web (já estava).
- Layout: designs só mobile, por isso o conteúdo fica com largura máxima de 640 centrada (`AppContentWidth`, `AppBreakpoints`), aplicado num só sítio (3 builders de transição, rotas com `builder` simples e shells). A partir de 840 de largura os shells usam `NavigationRail` em vez da bottom nav (`AppAdaptiveShell`), com os mesmos destinos e a ação central como botão no topo.
- URLs sem `#` (`usePathUrlStrategy`), para o link `/w/:workerId` ficar limpo. Obriga o alojamento a devolver `index.html` em qualquer caminho: `web/_redirects` (Netlify, Cloudflare), `web/vercel.json`, `firebase.json`. Na web o link do cartão do jardineiro usa o próprio domínio do site (`Uri.base.origin`), por isso já funciona.
- Mobile intocado: rodar o telemóvel não recria o ecrã (`AppContentWidth` tem sempre a mesma árvore e dá ao ecrã o tamanho exato de antes); telemóvel deitado fica com a bottom nav (a navegação lateral exige o lado menor com 600+); avatares no telemóvel continuam a usar `upload(File)` como antes, só a web usa bytes.
- PWA: `manifest.json` e `index.html` com nome ProJardim, cores da marca, ícones novos (folha branca em fundo `#2E7D32`), `apple-touch-icon` e ecrã de arranque simples até ao primeiro frame. Arrastar com rato/trackpad ativo (onboarding e listas no PC).

## 2026-10-16 — Regras do dia do trabalho: concluir, expirar e lembrar (migration 0046)

Pedido do Henrique depois de testar o ecrã confirmado do jardineiro.

- "Marcar como concluído" só a partir do dia combinado (`mark_job_done` recusa antes; sem data confirmada fica livre). Foto opcional do worker em `job-photos/<worker>/<job>/done_*.jpg`, guardada em `job_requests.completion_photo_path` e mostrada ao cliente ao confirmar. O cliente continua a confirmar.
- Trabalho confirmado cuja data passou sem conclusão: lembrete aos dois no dia seguinte; 3 dias depois da data passa a `cancelled` com `cancel_reason = 'expired'`. Escolhemos `cancelled` e não `completed` porque ninguém disse que o trabalho foi feito; não reabre o pedido.
- Marcado como concluído e o cliente não confirma: lembrete ao fim de 1 dia, confirmação automática ao fim de 3 (regra antiga, agora a contar de `marked_done_at`).
- Pedidos abertos com data fixa passada: escondidos já em `get_jobs_in_radius` e passados a `no_response` pelo cron (propostas pendentes ficam `rejected`).
- Lembrete na manhã do dia (cron `job-reminders`, 07:30 UTC) ao cliente e ao worker. Tipo novo `job_reminder` (20 tipos). "Hoje" é sempre a data de Portugal (`today_pt()`).
- Títulos deixam de mostrar o id ("Pedido #12ab34cd"): nome do serviço e, por baixo, zona e data (`jobDistinguisherLabel`), para distinguir duas podas.
- Valor acordado mostra taxa e intervalo total ("25,00 €/h · ≈ 50 a 100 €") nos ecrãs de trabalho confirmado (`agreedPriceLabel`).

## 2026-10-16 — Catálogo de serviços com Agricultura e Floresta (migration 0045)

Três categorias (Jardinagem, Agricultura, Floresta) e 33 tipos, cada um com ícone. O ícone fica na BD (`service_types.icon`, nome de um ícone Material) e a app traduz o nome com um mapa fixo em `core/widgets/service_icon.dart`, porque o Flutter não carrega ícones por nome e o tree-shaking corta os que não aparecem no código. Nome desconhecido mostra o ícone genérico (`yard`). Um teste lê a migration e falha se algum ícone dela não estiver no mapa. A lista de serviços passa a vir ordenada por categoria e por `sort_order`, e os ecrãs de escolha (criar pedido, configurar e editar perfil do jardineiro) mostram uma secção por categoria. Os 3 tipos antigos mantêm id e nome, para pedidos e perfis existentes não mudarem.

## 2026-10-16 — Fecho do review: RPCs sem p_worker_id e policies mais rápidas (migration 0044)

`create_proposal`, `get_jobs_in_radius` e `sync_worker_service_types` deixam de receber `p_worker_id` (DROP explícito das versões antigas; a app nova já não o envia). A app ainda não está publicada, por isso não há versão antiga a proteger.

P4: as policies do public passam a usar `(SELECT auth.uid())`, avaliado uma vez por query. **Exceção: `job_requests`.** A policy de INSERT de `job_requests` consulta `profiles`, e uma policy de `profiles` consulta `job_requests`; com um sublink nas policies de SELECT de `job_requests`, o Postgres recusa o INSERT com "infinite recursion detected in policy". Por isso a migration acaba com uma verificação que faz EXPLAIN de SELECT/INSERT/UPDATE/DELETE em todas as tabelas como `authenticated` e falha inteira se houver recursão. `get_jobs_in_radius` e `get_help_requests_in_radius` pré-filtram por uma caixa de lat/lng, com índice parcial `idx_job_requests_open_location`.


Relatório: `/mnt/project-files/projardim/review/2026-10-16-review-codigo.md`.

**Decisão de fundo:** as escritas de negócio só passam por RPCs SECURITY DEFINER. Policies de INSERT/UPDATE diretas que a app não usa foram apagadas, em vez de tentar replicar em RLS as regras das RPCs. As que a app usa (criar pedido, pedir ajudantes, candidatar-se, cartão frota, marcar notificação lida) ficaram com WITH CHECK que só aceita o estado inicial.

**BD (0042, não aplicada):** autorização em `cancel_job` e `reject_proposal`; `create_user_profile` apagada (não era usada e estava aberta a anon); `mark_job_done` e a policy de profiles do worker passam a usar `job_requests.accepted_proposal_id` em vez de `job_proposals.status`; `accept_help_candidate` só com o pedido de ajuda `open`; `create_proposal` valida worker, preço, próprio pedido e `excluded_worker_ids`; remarcações exigem data futura e pedido confirmado; raio limitado a 50 km no servidor; `acos` trocado por haversine com `asin` (rebentava com coordenadas iguais); `ORDER BY` por distância reposto nos ajudantes; buckets com 2 MB e só imagens, sem listagem pública; REVOKE de anon em todas as funções; notificações lidas apagadas aos 90 dias (todas aos 180) por pg_cron; limite de 5 pedidos por hora por cliente; 7 índices.

**Assinaturas mantidas de propósito:** `create_proposal` e `get_jobs_in_radius` continuam a receber `p_worker_id` (ignorado ou comparado com `auth.uid()`), para a app atual não partir entre aplicar a migration e publicar a app nova. Remover numa migration futura com DROP explícito.

**App:** id passa a `pt.projardim.app` (Android applicationId/namespace e iOS bundle id), nome "ProJardim" no ícone, assinatura de release por `android/key.properties` (fallback para debug), chaves de permissão no Info.plist (localização, câmara, fotos: sem elas o iOS fecha a app), `pubspec.lock` passa a ser versionado, stream de notificações com `.limit(50)`, `notificationSync` compara ids em vez de tamanhos, `currentUserProvider` só reconstrói quando muda o id do utilizador, `cacheWidth` nas miniaturas, providers mortos removidos, mensagens novas em `friendlyError`, teste smoke trocado por testes de lógica pura.

**Decidido no mesmo dia (migration 0043):** zona aproximada até haver proposta aceite. O jardineiro vê a localidade (`location_area`, preenchida pela app com o `locationName` do reverse geocoding) e coordenadas arredondadas a 2 casas decimais; a morada exata e as coordenadas reais ficam para o cliente, o worker aceite e os ajudantes aceites. Os workers deixam de ler `job_requests` por RLS (exceto o aceite); a app lê o detalhe por `get_job_by_id`, que devolve a versão certa para cada um. Efeito lateral corrigido: o worker aceite passa a ver as fotos do pedido depois de confirmado (a policy antiga só mostrava fotos de pedidos `open`). Ao candidato a ajudante ainda não aceite também deixa de aparecer o telefone do principal.

## 2026-10-16 — Extração de dump real da BD viva e verificação do estado das migrations

O utilizador extraiu um dump real da BD viva via `supabase db dump` (CLI, projeto
`twpflvcoyeiysnychkom`, plano Free), guardado temporariamente em
`supabase_schema_backup.sql` na raiz do workspace (fora do git, ver entrada de
gitignore abaixo). É a primeira vez nesta série de sessões com acesso real ao
schema da BD viva, em vez de depender da palavra do utilizador ou dos cabeçalhos
dos ficheiros de migration.

**Verificação feita:** comparação linha a linha entre o dump e a soma de
`0001_consolidated_baseline.sql` + migrations 0033–0040.

- Funções: 37 na BD viva, 37 nas migrations, diff vazio nos dois sentidos.
- Tabelas: 14 na BD viva, 14 nas migrations, diff vazio.
- Views: 3 em ambos (`worker_profiles_public`, `worker_rating_summary` com
  `security_invoker=true`, `worker_public_card`), `security_invoker` coincide.
- Policies de `profiles`: 5 na BD viva (3 granulares + insert própria + update
  própria), confirma que não existe policy pública — `database_schema.md`
  continua desatualizado nesse ponto (discrepância 1 da secção 16 do
  `ARCHITECTURE.md`, não corrigida porque é fora do âmbito da verificação).

**Resultado principal:** as migrations `0038_ratings_mine_received_given.sql`,
`0039_help_request_principal_avatar.sql` e `0040_cross_party_identity_rpcs.sql`
estavam todas marcadas como "NÃO aplicada" em `ARCHITECTURE.md`, `STATUS.md` e
`supabase/migrations/README.md` — e na verdade já estavam todas aplicadas na BD
viva (confirmado pela presença das 7 funções que introduzem, com a assinatura
exata esperada). Os 3 ficheiros foram corrigidos para refletir isto.

**Drift novo encontrado:** o trigger de `job_requests` chama-se `on_job_created`
na BD viva, mas o ficheiro `0001_consolidated_baseline.sql` define-o como
`trigger_notify_workers_new_job`. Mesma função (`notify_workers_new_job()`),
mesmo evento (`AFTER INSERT`) — parece um rename manual feito diretamente no
Supabase Studio, nunca passou por uma migration deste repo. Sem impacto
funcional. Registado como ponto 8 novo na secção 16 do `ARCHITECTURE.md`.

**Não confirmado:** o dump foi só de schema (sem `--data-only`), por isso a
discrepância do seed de `service_types` (ponto 3 da secção 16, "Montagem de
jardim" vs. "Limpeza de jardim") continua sem resposta — precisa de
`supabase db dump --data-only` ou de uma query direta.

**Ficheiros alterados:** `supabase/migrations/README.md`, `docs/ARCHITECTURE.md`
(secção 7 — nota de abertura, tabela de RPCs, trigger, estado das migrations;
secção 16 — pontos 1, 3, 7 atualizados, ponto 8 novo), `docs/STATUS.md` (nova
entrada em "Gaps conhecidos", nota de confirmação no item dos 4 RPCs de
contraparte). Nenhuma migration nova criada — esta tarefa foi só de
verificação/documentação, não tocou em código Dart nem em SQL novo.

**Gitignore:** `.gitignore` da raiz ganhou `/supabase_*.sql` e `/supabase/.temp/`
para o dump e a cache de link da CLI (criada por engano na raiz do workspace em
vez de dentro de `servicesapp/`) nunca irem para o repo.

## 2026-10-16 — 4 bugs visuais/navegação reportados com screenshots reais (Android)

### 1. Badge de estado gigante na AppBar

**Causa raiz:** `AppStatusBadge`'s `Container` tinha `alignment: Alignment.center` — comportamento documentado do Flutter, não um bug do Flutter: um `Container` com `alignment` e um único filho deixa de se ajustar ao conteúdo e passa a **expandir-se para ocupar todo o espaço disponível**, tal como um `Align`/`Center` sozinho faria. Dentro de `AppBar.actions` (Material 3: `Row` com `crossAxisAlignment.center`, dá constraints LOOSE de 0 até à altura da toolbar), isto fazia o badge esticar para os 56px da toolbar mesmo já envolvido num `Center` no call site — o `Center` externo dava constraints loose corretas, mas o `Container` interno, por ter `alignment`, escolhia o máximo em vez do tamanho do conteúdo. Confirmado com widget test: `Size(254.0, 56.0)` antes, `Size(254.0, 28.0)` depois de remover só o `alignment:` (mantendo `minHeight: 28`).

**Sítios com badge em `AppBar.actions` ou equivalente** (grep exaustivo por `AppStatusBadge`/`actions:` em `lib/`):
- `client_job_detail_screen.dart` — 2 AppBars reais (ramo `open`, com ícone de fechar a seguir; ramo `awaitingConfirmation`/`completed`/`cancelled`/`noResponse`, sem ícone extra).
- `worker_my_job_detail_view.dart` — 1 AppBar (estado da proposta do worker).
- `client_scheduled_job_detail_screen.dart`'s `_ScheduledHeader` — não é um `AppBar` real (é um cabeçalho próprio, Container+Row), mas mesmo papel visual/mesma posição — mesmo badge, mesmo bug (constraints loose herdadas de um `Row`/`Column` sem altura fixa acima).

**Correção num único sítio** (`core/widgets/app_status_badge.dart`, não por ecrã): `alignment: Alignment.center` removido do `Container` de `AppStatusBadge` — corrige os 3 sítios de uma vez, e qualquer uso futuro do badge em contexto apertado.

**Título ainda cortado depois do fix de altura — sim, com 3 labels longos.** Medido com widget test a 360/392/412dp: `"À espera de proposta"` (20 car.) + ícone de fechar esmagava o título a 0–6px de largura; `"Aguarda resposta"` (16 car.) e `"Não selecionada"` (15 car., mesma AppBar — estados de `ProposalStatus`) ficavam a 48–111px, apertado. Resolvido com um widget novo, `AppBarStatusBadge` (mesmo ficheiro), que acrescenta ao `AppStatusBadge` já corrigido: margem direita consistente (`AppSpacing.md`, serve também de espaçamento para o ícone de fechar quando existe) e um mapeamento fechado de labels curtos SÓ para este contexto (os badges em cards/listas continuam com o texto completo de `presentation().label`):

| Label completo (cards/listas) | Label curto (AppBar) |
|---|---|
| "À espera de proposta" | "Em aberto" |
| "Aguarda resposta" | "Pendente" |
| "Não selecionada" | "Recusada" |

Medido depois do fix: título entre 80–169px nos 3 larguras — nunca mais 0px. "Confirmado"/"Substituída"/"Concluído"/"Cancelado" já eram curtos, sem alteração.

**Ficheiros alterados:** `core/widgets/app_status_badge.dart` (fix + `AppBarStatusBadge` novo), `client_job_detail_screen.dart`, `worker_my_job_detail_view.dart`, `client_scheduled_job_detail_screen.dart` (as 4 call sites a usar o novo widget).

---

### 2. Texto dos chips não centrado

**Causa raiz, confirmada com widget test (não a mesma do Ponto 1 — mecanismo diferente):** `AppFilterChip`'s `Row` interno tem `mainAxisSize: MainAxisSize.min`, sem `mainAxisAlignment`. Um `Row` não-flex dentro de outro `Row`/`Flex` recebe sempre constraints de largura UNBOUNDED no eixo principal — por isso, quando o chip está em `Wrap` (constraints loose, chip do tamanho do conteúdo), `mainAxisSize: min` já dá o resultado certo e sempre deu. Mas quando o chip está num `Expanded` (ex.: 3 chips de igual largura numa `Row`), o `Expanded` força o `AnimatedContainer` externo a uma largura TIGHT bem maior que o conteúdo — e essa largura tight propaga-se ao `Row` interno (que `mainAxisSize: min` não consegue recusar quando a constraint chega já fixa, só escolhe min/max quando a constraint é loose). Sem `mainAxisAlignment`, o `Row` (agora largo) alinha o conteúdo ao início (esquerda) em vez de centrar. Medido: texto a `x=41.75` (chip com `center.dx=400`) antes; `x=400` (= centro do chip) depois de acrescentar só `mainAxisAlignment: MainAxisAlignment.center` — sem tocar em `mainAxisSize`.

**Confirmado sem regressão no caso "largura do conteúdo":** no mesmo teste, o chip em `Wrap` manteve exatamente a mesma posição/tamanho antes e depois (`mainAxisAlignment` não tem nada para redistribuir quando `mainAxisSize: min` já reduziu o `Row` ao tamanho do conteúdo).

**Ecrãs onde verifiquei (grep por `AppRadius.pill` + `mainAxisSize: MainAxisSize.min`, e por padrões de pill/tab seletor):**
- `worker_submit_proposal_view.dart` ("A sua proposta" — Manhã/Tarde/Fim do dia; 1-2h/2-4h/4-6h/+6h) — usa `AppFilterChip` dentro de `Expanded`, é exatamente o caso do bug reportado. **Corrigido pelo fix no componente partilhado.**
- `client_job_detail_screen.dart` (chips de "Problemas comuns", ramo `awaitingConfirmation`) — usa `AppFilterChip` em `Wrap`. Já estava certo, confirma que o fix não estraga este caso.
- `client_create_job_schedule_screen.dart` (`_SizeChip`, passo "Data" de criar pedido — Pequeno/Médio/Grande) — widget PRÓPRIO, não `AppFilterChip`, mas já tinha `Container(alignment: Alignment.center)` + `Text(textAlign: center)`, sempre usado dentro de `Expanded` (tight) — alignment/Container nesse caso É seguro porque a constraint é sempre tight aqui, nunca loose-sem-limite. **Já estava correto, não alterado.**
- `_UrgencyOptionCard` (mesmo ecrã, Normal/Urgente) — não é um chip (card de opção com rádio, texto à esquerda por design) — não aplicável.
- `worker_setup_screen.dart` (chips de tipo de serviço) — usa o `FilterChip` nativo do Flutter (Material), não o componente da app — já centra corretamente por si só.
- Pills de tabs (`_TabPill` em `worker_help_requests_screen.dart`; `_TabButton`, duplicado identicamente em `client_jobs_view.dart` e `my_ratings_screen.dart`) — **verifiquei e NÃO têm o bug**, apesar de usarem o mesmo `Padding > Text(textAlign: center)` sem `Row` nem `Center` explícito: confirmado com teste a nível de glyph (`RenderParagraph.getBoxesForSelection`) que o texto fica corretamente centrado — `Text` usa por omissão `textWidthBasis: TextWidthBasis.parent`, que faz a caixa do parágrafo ocupar a largura TOTAL disponível (quando finita) em vez de encolher ao conteúdo; `textAlign: center` centra os glyphs dentro dessa caixa cheia. Mecanismo diferente do `Row.mainAxisSize`, e sem bug aqui.
- `_JobsTabButton` (`worker_jobs_view.dart`, tabs Pendentes/Agendados/Concluídos) — usa `FittedBox` (que já centra por omissão) em vez de `Row`/`Padding`+`Text` — também sem bug.

**Ficheiro alterado:** só `core/widgets/app_filter_chip.dart` (+1 linha, `mainAxisAlignment: MainAxisAlignment.center`).

---

### 3. Cores da zona da bottom nav diferentes do fundo

**Causa raiz:** nem `ClientShell`/`WorkerShell` nem o `ThemeData` definiam `scaffoldBackgroundColor` — o `Scaffold` desses 2 shells (que só existe para alojar a `bottomNavigationBar`) caía no `colorScheme.surface` **gerado pelo Material 3 a partir da seed verde** (`ColorScheme.fromSeed`), uma cor diferente de `AppColors.background`/`AppColors.surface` (tokens próprios da app, não derivados da seed). `AppBottomNavigation` não pinta o fundo do seu próprio `SafeArea`/`Padding`/`Stack` — só a "pílula" (`Positioned` com `AppColors.surface`) tem cor; tudo o resto (margem acima da pílula, laterais, e a área do inset de gestos por baixo) é transparente e mostra o que estiver por trás: o Scaffold do SHELL, não o do ecrã individual (que já definia `AppColors.background` corretamente). Não havia NENHUMA configuração de `SystemUiOverlayStyle`/`systemNavigationBarColor` em lado nenhum do projeto (grep a `lib/` sem resultados) — a cor da barra de gestos do Android vinha do valor por omissão da plataforma, sem relação com nenhum token da app.

| Faixa | Origem | Cor antes | Cor depois |
|---|---|---|---|
| Acima da pílula (margem `AppSpacing.sm`) | `Scaffold.backgroundColor` do Shell (não definido → `colorScheme.surface` gerado pela seed) | Esverdeado derivado da seed, ≠ `AppColors.background` | `AppColors.background` (`#F6F8F6`) |
| A pílula em si | `Container` dentro de `AppBottomNavigation` | `AppColors.surface` (`#FFFFFF`) — já correto | inalterado |
| Laterais/inset inferior (gestos) | Mesma causa acima + `systemNavigationBarColor` nunca definido (default da plataforma) | Mistura do default do Android + o `colorScheme.surface` da seed | `AppColors.surface` via `systemNavigationBarColor`, ícones `Brightness.dark` |

**Correções:**
- `AppTheme.light()` (`core/theme/app_theme.dart`) ganhou `scaffoldBackgroundColor: AppColors.background` — elimina a faixa acima da pílula em QUALQUER Scaffold sem cor própria, dentro ou fora do shell, de uma só vez.
- Novo `AppTheme.systemUiOverlayStyle` (mesmo ficheiro) — `systemNavigationBarColor: AppColors.surface` (igual à pílula), `systemNavigationBarIconBrightness: Brightness.dark`, `systemNavigationBarDividerColor: Colors.transparent`.
- `app.dart` — `AnnotatedRegion<SystemUiOverlayStyle>` a envolver `MaterialApp.router` uma única vez (não por ecrã; sobrevive a resumes, ao contrário de uma chamada única a `SystemChrome.setSystemUIOverlayStyle` em `main.dart`). Aplica-se a toda a app, incl. ecrãs fora do shell (login, onboarding, etc.) — confirmado por estar acima do `routerConfig`, não dentro de uma rota específica.
- Confirmado sem cor hardcoded fora de `AppColors` em `app_bottom_navigation.dart`/shells/`app.dart`/`app_theme.dart` (grep a `Color(0x`).

**Ficheiros alterados:** `core/theme/app_theme.dart`, `app.dart`. `AppBottomNavigation`/`ClientShell`/`WorkerShell` não precisaram de alteração — a causa era só a falta do `scaffoldBackgroundColor` global.

---

### 4. Botão de voltar depois de notificação não faz nada

**Causa exata:** `notification_handler.dart` usa `context.go()` de propósito (16 dos 19 tipos — ver tabela abaixo) para evitar o crash de `keyReservation` já documentado no próprio ficheiro. `go()` SUBSTITUI a stack toda pela rota de destino — depois de um `go()`, não fica nada por baixo para desfazer. O botão de voltar (um `IconButton` a chamar `context.pop()` direto) e o gesto do sistema caem em `canPop() == false`; o `pop()` do go_router não faz nada nesse caso (sem crash, só sem efeito) — daí "não faz nada".

**Mecanismo partilhado (nunca duplicado):** `core/router/app_back_navigation.dart` — `goBackOrToRoleHome(context)`: pop normal se `context.canPop()`; senão, `context.go()` para `/worker/home` ou `/client/home`, inferido do PRÓPRIO prefixo da rota (`roleHomeRouteFor`, mesmo padrão já usado no cross-role guard de `app_router.dart` — sem precisar de ler sessão/Riverpod).

Aplicado em dois sítios, como pedido:
- **(a) Botão da AppBar** — novo `AppBackButton` (`core/widgets/app_back_button.dart`), usado em `client_job_detail_screen.dart` (2 AppBars). Nos ecrãs que já separam screen/view com um callback `onBack` (arquitetura já estabelecida no projeto), bastou trocar o corpo do callback — sem tocar no widget da view: `client_scheduled_job_detail_screen.dart` (`_ScheduledHeader` + estados loading/error), `worker_job_detail_screen.dart`, `worker_my_job_detail_screen.dart`, `worker_help_requests_lobby_screen.dart` (só o `onBack`; `onRequestHelpers`, que também faz `pop()`, é uma ação diferente — fechar o lobby para abrir o sheet de pedir ajudantes no ecrã de trás — não tocado).
- **(b) Gesto/botão do sistema** — `PopScope` dentro de `_wrapWithBackFallback`, chamado uma vez em cada um dos 3 builders de transição (`buildSharedAxisPage`/`buildContainerTransformPage`/`buildFadeThroughPage`, `app_page_transitions.dart`) — cobre todas as rotas de uma vez, confirmado por leitura de `app_router.dart`: toda rota alcançável por notificação passa por um destes 3 builders (nenhuma rota "sem pageBuilder" é destino de notificação — só `/client/home`/`/worker/home`, que são o próprio destino do fallback, corretamente não-embrulhados).

**2 armadilhas reais encontradas só com widget tests** (haviam passado numa primeira leitura do código, por isso vale registar): (1) `GoRouterState.of(context)` lança quando chamado dentro do callback assíncrono do `PopScope`, porque o `context` do `pageBuilder` não é descendente da própria rota — resolvido lendo `state.matchedLocation` (já disponível, síncrono) em vez de reconsultar via `context`. (2) `context.canPop()` lido no `context` do `pageBuilder`, à mesma altura, fica desatualizado logo após um `context.push()` (reporta `false` quando já é `true`) — resolvido embrulhando com `Builder` para obter um `context` que é mesmo descendente da rota antes de ler `canPop()`. As duas únicas rotas de teste automatizado (`go()` depois de voltar do sistema → home; `push()` depois de voltar do sistema → pop normal) confirmam os dois comportamentos lado a lado.

**19 tipos de notificação — destino e comportamento do voltar:**

| Notificação | Destino | Navegação | Voltar |
|---|---|---|---|
| `newJobInRadius` | `/worker/job/:id` | go | → `/worker/home` |
| `proposalReceived` | `/client/job/:id` | go | → `/client/home` |
| `proposalWithdrawn` | `/client/job/:id` | go | → `/client/home` |
| `proposalAccepted` | `/worker/my-job/:id` (ou `/worker/home` se o fetch falhar) | go | → `/worker/home` |
| `proposalRejected` | `/worker/job/:id` | go | → `/worker/home` |
| `jobCancelled` | `/client/job/:id` ou `/worker/my-job/:id` (ou `/worker/home`) | go | → início do papel |
| `jobReopened` | `/worker/job/:id` | go | → `/worker/home` |
| `rescheduleProposed` | `/client/job/:id` ou `/worker/my-job/:id` (ou `/worker/home`) | go | → início do papel |
| `rescheduleAccepted` | idem | go | → início do papel |
| `rescheduleRejected` | idem | go | → início do papel |
| `jobMarkedDone` | `/client/job/:id` | go | → `/client/home` |
| `jobCompleted` | `/client/job/:id` ou `/worker/my-job/:id` (ou `/worker/home`) | go | → início do papel |
| `jobNoResponse` | `/client/job/:id` | go | → `/client/home` |
| `helpRequestApproved` | `/worker/job/:id/help-requests` (ou `/worker/home`) | push | pop normal (stack já tem algo por baixo na maioria dos casos; fallback aplicado por consistência) |
| `helpAccepted` | `/worker/help-requests` (tab 1) | go | → `/worker/home` |
| `helpRejected` | `/worker/help-requests` (tab 1) | go | → `/worker/home` |
| `helpJobCancelled` | `/worker/help-requests` (tab 1) | go | → `/worker/home` |
| `helpRequestReopened` | `/worker/help-requests` | push | pop normal / fallback |
| `helpWithdrew` | `/worker/job/:id/help-requests` (ou `/worker/home`) | push | pop normal / fallback |

`worker_help_requests_screen.dart` (destino de 4 tipos) tem um padrão próprio já adequado — `if (canPop) IconButton(...)`, esconde o botão em vez de o mostrar morto — não alterado; o fallback do gesto/botão do sistema (b) cobre-o da mesma forma que os outros.

**Testado mentalmente (e com teste automatizado) os dois caminhos pedidos:** notificação → abrir detalhe → voltar = cai no início do papel (confirmado, `go()` + `canPop() == false`). Abrir a app → entrar num detalhe por um card → voltar = cai na lista de onde veio (confirmado, `push()` + `canPop() == true`, comportamento inalterado).

**Ficheiros alterados:** `core/router/app_back_navigation.dart` (novo), `core/widgets/app_back_button.dart` (novo), `core/router/app_page_transitions.dart`, `client_job_detail_screen.dart`, `client_scheduled_job_detail_screen.dart`, `worker_job_detail_screen.dart`, `worker_my_job_detail_screen.dart`, `worker_help_requests_lobby_screen.dart`.

**Fora de âmbito, deliberadamente não tocado:** os restantes ~25 call sites de `context.pop()` em `leading`/`onBack` espalhados pela app (wizard de criar pedido, fluxo de auth, cartão frota, etc.) — todos em fluxos multi-passo já sempre com stack (`canPop()` praticamente sempre `true` aí), não são destino de nenhuma notificação, e o comportamento de hoje já está correto. `AppBackButton`/`goBackOrToRoleHome` ficam disponíveis para serem adotados nesses sítios no futuro, sem necessidade de os tocar agora.

**`flutter analyze`:** 0 issues novos (mesmos 5 pré-existentes e sem relação).

---

## 2026-10-15 — Indicador de progresso horizontal em todo o lado + foto/nome da contraparte nos dois sentidos

### Parte 1 — `StatusTimeline` vertical substituída por `StatusTimelineHorizontal` em todos os ramos

**Decisão nova (substitui a de 2026-09-27, commit `023e636`):** todos os indicadores de progresso passam a horizontal, no topo do ecrã. A sessão anterior tinha revertido `client_job_detail_screen.dart` para vertical nos ramos fora de `open` precisamente porque a variante horizontal não mostrava `subtitle`/`note` por passo — em vez de reverter outra vez, a variante horizontal foi estendida para os mostrar numa zona de detalhe única.

**`core/widgets/status_timeline.dart`:**
- `StatusTimelineStepData` ganhou `dateLabel` (caption curta "dd/MM" sob o label do nó, só em passos `completed`) — `subtitle` deixou de ser usado para datas, fica reservado ao passo `state == current` (ex.: motivo de cancelamento).
- `StatusTimelineHorizontal` passou a renderizar, por baixo do traço: o `subtitle` do passo atual, e a `note` de QUALQUER passo (não só do atual) — a note de remarcação pendente vive no passo "Proposta aceite", que nunca é `current` nos ramos onde isto importa, por isso a regra do enunciado ("se um passo que não é o atual tiver uma note de aviso") foi generalizada para qualquer note, não só as de aviso, para não perder a note "Data remarcada" (sucesso, não aviso).
- A largura de cada nó (`_horizontalNodeColumnWidth`, 72px) passou a ser calculada por `LayoutBuilder`: mantém-se 72px sempre que os passos cabem nessa largura; só encolhe (com um mínimo de 12px por conector) quando não cabe. Sem isto, 4 nós fixos a 72px (`buildJobTimeline` nos ramos confirmed/awaitingConfirmation/completed) overflowavam por 8px a 360dp dentro de cartões com `AppSpacing.lg` (24px) de margem — `worker_my_job_detail_view.dart` (ambos os corpos) e o ramo não-`open` de `client_job_detail_screen.dart`. Verificado com um widget test (texto a 1.3×, 360dp, pior caso de padding) — sem overflow depois do fix, removido no fim (não ficou nenhum ficheiro de teste novo).
- Classe `StatusTimeline` (vertical) e os widgets privados que só ela usava (`_TimelineRow`, `_TimelineRowState`) **removidos** — zero utilizadores depois da conversão.
- `StatusTimelineCard` (novo, público) — extrai o `Container` (fundo `AppColors.primaryContainer`, raio `AppRadius.card`) que existia como `_TimelineCard` privado e quase idêntico em `client_job_detail_screen.dart` e `client_scheduled_job_detail_screen.dart`; `supportingLabel`/`supportingLabelColor` continuam a existir para texto independente dos passos (aviso de expiração do ramo `open`; frase "Serviço agendado para..." do ecrã dedicado a `confirmed`).

**`features/jobs/application/job_timeline.dart`:** labels mais longos encurtados para caberem em ~14 caracteres / 2 linhas (cor do nó continua a vir de `presentation().color` — só o texto do nó muda, os badges de estado em toda a app continuam a usar `presentation().label` sem alteração):

| Label antigo (longo) | Label novo (nó da timeline) | Onde |
|---|---|---|
| "À espera de proposta" | "Sem proposta" | `JobStatus.open`, sem propostas ainda — só aparece via `buildJobTimeline` quando o worker olha para o seu próprio job ainda `open` (`worker_my_job_detail_view.dart`); o cliente usa sempre o stepper `_buildOpenStepperSteps`, inalterado |
| "Marcado como concluído" | "Trabalho feito" | passo intermédio, nunca confundido com "Concluído" (completado só depois da confirmação do cliente) |
| "A aguardar confirmação" | "A confirmar" | estado `awaitingConfirmation`, nó current |

Labels já curtos ("Pedido criado", "Proposta aceite", "Sem resposta", "Concluído", "Cancelado") mantidos sem alteração.

**Ficheiros alterados:** `core/widgets/status_timeline.dart`, `features/jobs/application/job_timeline.dart`, `features/jobs/presentation/client_job_detail_screen.dart`, `features/jobs/presentation/client_scheduled_job_detail_screen.dart`, `features/worker/presentation/widgets/worker_my_job_detail_view.dart`.

**O que mudou de sítio:**
- Datas de passos `completed` ("Pedido criado", "Proposta aceite") → caption "dd/MM" sob o label do nó (antes: `subtitle` nunca renderizado pela variante horizontal nestes ramos, porque estavam todos em vertical).
- Motivo de cancelamento (subtitle do passo "Cancelado") e notas de remarcação (note do passo "Proposta aceite") → zona de detalhe, centrados, por baixo do traço.
- `worker_my_job_detail_view.dart` (`_buildOtherBody`): o indicador passou a ser o primeiro elemento do corpo (antes vinha depois de `_JobSummaryCard`, descrição e `_ProposalSummaryCard`); o título de secção "Estado do pedido" foi removido (redundante com o cartão no topo, mesmo padrão dos outros ecrãs).
- Nenhuma informação da timeline vertical ficou de fora: confirmado campo a campo (dateLabel cobre as datas, note cobre os avisos, subtitle do passo atual cobre o motivo de cancelamento).

**Confirmação do ponto 5 (6+ passos):** nenhum ramo de `buildJobTimeline` nem de `_buildOpenStepperSteps` passa de 4 passos — não foi preciso agrupar nada.

---

### Parte 2 — Foto/nome da contraparte: 4 pontos partidos pelo hardening de segurança de 2026-09-09 (migration 0032)

**Causa raiz comum aos 4:** a migration `archive/0032_audit_fixes.sql` (aplicada à BD viva em 2026-09-09) substituiu a policy `USING(true)` de `profiles` por 3 policies granulares — correção de segurança correta (antes, qualquer autenticado lia o perfil completo de qualquer utilizador, incluindo telefone). Mas 4 pontos do código liam nome/avatar da CONTRAPARTE através de um embedded join do PostgREST (`profiles!<fk>(full_name, avatar_url)`) fora das 2 relações que essas 3 policies cobrem (dono do perfil; worker↔cliente só depois de proposta `accepted`). Nenhum destes 4 pontos foi testado de novo depois do hardening — o join passou a devolver sempre `null`, sem erro nenhum, por isso ninguém reparou até esta auditoria.

**Matriz de pontos de contacto (antes → depois):**

| Ecrã | Quem aparece | Fonte de dados (antes) | Nome/avatar chegavam? | Fonte (depois) |
|---|---|---|---|---|
| `WorkerJobDetailScreen` (oportunidade, `open`) | Cliente, ao worker | SELECT direto `profiles` via `clientBasicInfoProvider` | **Não** — RLS só permite depois de proposta aceite; job ainda `open` | RPC `get_open_job_client_identity` (novo provider `openJobClientIdentityProvider`) |
| `client_proposals_screen.dart` ("Propostas recebidas") | Worker, ao cliente, por proposta `pending` | embedded join `profiles!job_proposals_worker_id_fkey` | **Não** — mesma causa, e é justamente ANTES de aceitar que o cliente mais precisa de ver quem propôs | RPC `get_pending_proposals_for_job` |
| `worker_help_requests_lobby_screen.dart` (aceitar/rejeitar candidatos) | Candidato ajudante, ao worker principal | embedded join `profiles!help_acceptances_worker_id_fkey` | **Não** — não há policy "principal vê perfil de candidato", só client↔worker de job confirmado | RPC `get_candidates_for_help_request` |
| `showRatingsSheet` (`client_proposals_screen.dart`, ecrãs de candidatura de ajudante) | Quem avaliou, ao ver as avaliações de um worker | embedded join `rater:profiles!rater_id` | **Não** — `ratings` é pública, mas o nome do rater não | RPC `get_ratings_with_rater_identity` |
| `worker_my_job_detail_screen.dart` / `worker_job_detail_screen.dart` (job `confirmed`/`awaiting_confirmation`/`completed`) | Cliente, ao worker | SELECT direto `profiles` via `clientBasicInfoProvider` | **Sim** — proposta já `accepted`, RLS permite | inalterado |
| `client_job_detail_screen.dart` / `client_scheduled_job_detail_screen.dart` / `client_job_confirmed_screen.dart` / `client_rate_worker_screen.dart` (job confirmado) | Worker, ao cliente | SELECT direto `profiles` via `workerBasicInfoProvider` | **Sim** — `client_has_confirmed_job_with_worker` cobre confirmed/awaiting/completed | inalterado |
| `client_jobs_screen.dart` (lista "Os meus pedidos") | Worker, ao cliente, jobs confirmados | `acceptedProposalForJobProvider` → `workerBasicInfoProvider` | **Sim**, mas a linha inteira desaparecia (não só o avatar) se o nome viesse vazio por qualquer razão | inalterado na fonte; UI já não esconde a linha (ver abaixo) |
| `get_worker_job_board` ("Os meus trabalhos", todas as tabs) | Cliente ou worker principal, ao worker | RPC já com `person_name`, SECURITY DEFINER | **Sim**, sempre (bypassa RLS) — mas nunca mostrou avatar, cards são texto+ícone genérico por design | inalterado, confirmado por design |
| `get_help_requests_in_radius` (descoberta de pedidos de ajuda) | Worker principal, ao candidato | RPC, `principal_avatar_url` ausente do `RETURNS TABLE` | **Não** (já corrigido em sessão anterior, migration 0039 escrita) | inalterado — ver nota sobre 0039 abaixo |
| Dashboard do worker (próximo trabalho/oportunidades), notificações (ambos os lados) | — | — | N/A — nenhum destes ecrãs tenta mostrar avatar (cards texto+ícone genérico, por design) | inalterado |
| "Pedidos disponíveis" (lista), "Enviar proposta", ecrãs de ajudante (nunca mostram o cliente do job) | — | — | N/A por design (lista mais leve; ajudante não deve ver o cliente, regra de negócio já documentada em `project_overview.md`) | inalterado |

**Correções (RLS → RPC, nunca alargamento de `profiles`):** 4 novas funções SECURITY DEFINER em `supabase/migrations/0040_cross_party_identity_rpcs.sql` (NOVA — NÃO APLICADA), cada uma a expor só nome+avatar (nunca telefone/coordenadas) com a MESMA condição de autorização que a policy já exigia para a linha "principal":
- `get_open_job_client_identity(p_job_id)` — autorização = `status = 'open'` (igual à policy "Worker vê jobs abertos").
- `get_pending_proposals_for_job(p_job_id)` — autorização = `job_requests.client_id = auth.uid()` (igual à policy "Client vê propostas dos seus jobs"); devolve as mesmas colunas de `job_proposals` + `worker_name`/`worker_avatar_url`.
- `get_candidates_for_help_request(p_help_request_id)` — reaproveita directamente `is_principal_worker_for_help_request()`, a mesma função já usada pela policy "Worker principal vê candidatos".
- `get_ratings_with_rater_identity(p_ratee_id)` — sem restrição adicional (a informação já era pública via `ratings USING(true)`).

**Ficheiros Dart alterados:**
- `features/jobs/data/job_repository.dart` (+ `fetchOpenJobClientIdentity`), `features/jobs/application/job_providers.dart` (+ `openJobClientIdentityProvider`), `features/worker/presentation/worker_job_detail_screen.dart` (usa o novo provider em vez de `clientBasicInfoProvider`).
- `features/proposals/data/proposal_repository.dart` (`fetchPendingProposalsForJob` passa a chamar a RPC), `features/proposals/data/proposal_model.dart` (`fromJson` lê `worker_name`/`worker_avatar_url` planos, com fallback ao embedded antigo).
- `features/help_requests/data/help_request_repository.dart` (`fetchCandidatesForHelpRequest` passa a chamar a RPC), `features/help_requests/data/help_request_model.dart` (idem, `HelpAcceptance.fromJson`).
- `features/ratings/data/rating_repository.dart` (`fetchRatingsWithRaterNames` passa a chamar a RPC), `features/ratings/data/rating_model.dart` (`Rating.fromJson` + novo campo `raterAvatarUrl`).

**Fallback visual ("—" → papel conhecido):** `core/widgets/user_avatar_with_name.dart` ganhou `fallbackLabel` opcional (mostrado no texto E usado para a inicial do avatar quando `name` vem vazio; omitido mantém o "—" antigo para quem não passar o parâmetro — nenhum call site não tocado muda de comportamento). Aplicado a:
- `worker_my_job_detail_view.dart` (×2 — cliente ao worker, confirmado e "other body"), `worker_job_detail_view.dart` (cliente ao worker, oportunidade) → `'Cliente'`.
- `client_job_detail_screen.dart` (`_workerContactCard`) → `'Jardineiro'`; `client_job_confirmed_screen.dart` e `client_scheduled_job_detail_screen.dart` já usavam ícone genérico para o avatar (sem alterar), só o texto "—"→"Jardineiro" no nome.
- `worker_help_requests_screen.dart` (card de descoberta, nome do principal) → `'Jardineiro'`; `_WorkerSummary` em `worker_help_requests_lobby_view.dart` (candidatos/ajudantes aceites) → `'Jardineiro'` inline (widget local, sem parâmetro — usado só neste papel).
- `ratings_sheet.dart` (nome do rater) → `'Avaliador'` (papel ambíguo — tanto clientes como principals avaliam um worker, por isso um termo neutro em vez de assumir um dos dois).
- `client_jobs_screen.dart` + `client_jobs_view.dart`: a lista escondia a linha do worker inteira quando o nome vinha vazio (`if (job.workerName != null && job.workerName!.isNotEmpty)`); passou a distinguir "sem worker" (`null`, esconde) de "há worker mas falta o nome" (`''`, mostra com `fallbackLabel: 'Jardineiro'`) — `workerName` na screen deixou de filtrar nomes vazios para `null`.

**O que continua sem avatar/nome, e porquê:**
- `get_worker_job_board` ("Os meus trabalhos") — texto+ícone genérico por design, confirmado na sessão anterior (`023e636`); não é um gap.
- Dashboard do worker e notificações (ambos os lados) — nenhum destes ecrãs usa avatar, design icon+texto consistente em toda a feature; não é um gap.
- "Pedidos disponíveis" (lista) e "Enviar proposta" — nunca mostraram o cliente; decisão de produto implícita (lista mais leve, identidade só no detalhe) — não alterado por não estar claramente pedido, mas fica registado como candidato a decisão futura.
- Ajudantes nunca veem o cliente do job — regra de negócio deliberada (`project_overview.md`), confirmado sem nenhuma leak nos ficheiros de `features/help_requests/`.

**`flutter analyze`:** 0 issues novos (5 pré-existentes sem relação, mesmos de 2026-10-12).

---

## 2026-10-12 — Limpeza de dívida técnica: mapeamento de erros, _PlaceholderScreen morto, confirmação do ratings_sheet

### 1. Consolidação do mapeamento de erros

**Antes — 4 funções a traduzir exceções, não só as 2 já conhecidas:**

| Função | Ficheiro | Casos tratados |
|---|---|---|
| `friendlyError(e)` | `core/utils/error_utils.dart` | rede, "24h de antecedência", proposta já enviada, duplicado/unique constraint, permission denied/RLS, estado inválido, fallback genérico. Usado em 26+ ficheiros. |
| `AuthController._mapError(e)` (privado) | `features/auth/application/auth_controller.dart` | invalid login, email já registado, password (genérico, texto desatualizado "6 caracteres"), rede, email not confirmed, rate limit, fallback. 4 call sites (signUp/createProfile/signIn/signOut). |
| `describePasswordResetError(e)` | `features/auth/application/password_reset_controller.dart` | só lê `.message` de um `AuthException` já classificado por `_throwClassified`; fallback próprio se não for `AuthException`. |
| `AuthRepository._throwClassified(e)` (privado) | `features/auth/data/auth_repository.dart` | **não encontrado pela auditoria de 2026-09-08** — classifica e relança com `code` estruturado (network/invalidCode/unexpected) para o fluxo de recuperação de senha/confirmação de email: deteção de rede via `AuthRetryableFetchException.statusCode == null` (mais fiável que string matching), `otp_expired`/`otp_disabled`, `same_password`, `weak_password` (texto "demasiado fraca... 8+ caracteres, maiúscula, número"), rate limit, backstop por string. |

Não existia nenhum `auth_error_utils.dart` — a deteção de rede "usada na recuperação de senha" vivia dentro de `_throwClassified`.

**Depois:**

- `friendlyError()` (`error_utils.dart`) passou a ser o ponto único para **mapear uma exceção crua numa mensagem**. Ganhou os casos de autenticação de `_mapError` (invalid login, email já registado, email not confirmed, rate limit, password fraca) e a deteção de rede foi extraída para uma função partilhada `isNetworkError(e)` (type-check `AuthRetryableFetchException` + string fallback, exatamente a lógica que estava em `_throwClassified`) — satisfaz o pedido de reaproveitar a deteção já existente em vez de criar outra.
- `AuthController._mapError` **removido por completo** — os 4 call sites chamam `friendlyError(e)`. Import de `flutter/foundation.dart` (só servia o `debugPrint` do `_mapError`) também removido.
- `AuthRepository._throwClassified` **mantido** (não é duplicação de `friendlyError`: produz um `code` estruturado que `PasswordResetController._classify` usa para decidir entre erro inline e `AppSystemStateScreen` — isso não é algo que uma função `String friendlyError(Object)` possa expressar). Simplificado para chamar `isNetworkError(e)` em vez de repetir a lógica duas vezes (type-check no topo + string backstop no fundo); o backstop de string para rede tornou-se redundante e foi removido.
- `describePasswordResetError` — fallback (caso `e` não seja `AuthException`, o que não deve acontecer em operação normal) passou a chamar `friendlyError(e)` em vez de uma string própria.
- `weak_password` em `_throwClassified` passou a usar a mesma constante `weakPasswordMessage` do validador client-side.

**Conflitos de texto resolvidos (mesmo caso, textos diferentes):**

1. **Password fraca** — `_mapError` dizia "A password deve ter pelo menos 6 caracteres." (regra antiga, Supabase default); `_throwClassified` dizia "A password é demasiado fraca. Usa 8+ caracteres, uma maiúscula e um número."; o validador client-side (`password_policy.dart`, única fonte da REGRA real) diz "A password tem de ter 8+ caracteres, uma maiúscula e um número." — confirmado em `signup_screen.dart` que esta é a regra realmente aplicada (`passwordPolicyValidator`, partilhado entre signup e nova password da recuperação). **Ficou o texto do validador** (extraído para a constante `weakPasswordMessage` em `password_policy.dart`, reutilizada nos 2 sítios) — o texto de 6 caracteres estava simplesmente desatualizado.
2. **Rede** — `friendlyError`/`_throwClassified` diziam "Sem ligação à internet. Verifica a tua conexão e tenta novamente."; `_mapError` dizia só "Sem ligação à internet." **Ficou a versão mais longa/acionável** (já era maioria 2-para-1).
3. **Fallback genérico** — `friendlyError` dizia "Ocorreu um erro inesperado. Tenta novamente."; `_mapError`/`describePasswordResetError`/`_throwClassified` diziam "Ocorreu um erro. Tenta novamente." **Ficou o texto do `friendlyError`** (maior superfície de uso); `_throwClassified` e `describePasswordResetError` ficaram alinhados com ele (o fallback de `_throwClassified` mantém-se literal — é o `code: unexpected` que o `PasswordResetController` lê, não uma chamada a `friendlyError`, para não perder o `code`).

**Nenhum caso foi perdido** — todos os 4 inventários acima estão cobertos em `friendlyError` ou em `_throwClassified` (que continua a existir, agora só reduzido de duplicação interna).

Ficheiros alterados: `core/utils/error_utils.dart`, `core/constants/password_policy.dart`, `features/auth/application/auth_controller.dart`, `features/auth/data/auth_repository.dart`, `features/auth/application/password_reset_controller.dart`. `flutter analyze`: 0 issues novos (5 pré-existentes sem relação).

### 2. `_PlaceholderScreen` duplicado em `client_shell.dart`

**Já não existe** — foi removido na sessão de 2026-09-09 (ver `STATUS.md`, secção "Gaps conhecidos 🔵 BAIXO"), antes desta sessão. Confirmado por leitura direta: `client_shell.dart` (68 linhas) não define nenhuma classe `_PlaceholderScreen`; a única definição do projeto vive em `app_router.dart:563`, usada 2x para as rotas placeholder `/client/messages` e `/worker/messages`. Nenhuma alteração feita — pedido já estava satisfeito.

### 3. `ratings_sheet.dart` / `showRatingsSheet`

**Não removido — a premissa da sessão estava incorreta.** `showRatingsSheet` (plural, `ratings_sheet.dart`) continua com 4 call sites ativos: `worker_help_requests_screen.dart` (import + 1 uso), `worker_help_requests_lobby_screen.dart`, `client_proposals_screen.dart`. O novo ecrã "As minhas avaliações" (`my_ratings_screen.dart` + `my_ratings_route.dart`, rotas `/worker/ratings` e `/client/ratings`) **não é o mesmo widget nem substitui o sheet** — `MyRatingsRoute` mostra sempre as avaliações do PRÓPRIO utilizador (dadas/recebidas, via `myRatingsReceivedProvider`/`myRatingsGivenProvider`, filtrados por `auth.uid()` nas RPCs `get_my_ratings_received`/`get_my_ratings_given`), enquanto `showRatingsSheet` mostra, a partir de um fluxo em curso, as avaliações de um WORKER ESPECÍFICO identificado por `workerId` passado pelo caller (ex.: ver a reputação de um candidato antes de aceitar). São funcionalidades distintas que coexistem — o ecrã novo não veio para substituir o sheet, veio para cobrir um caso que não existia antes ("ver as minhas próprias avaliações"). `rating_sheet.dart` (`showRatingSheet`, singular — submeter avaliação nova) confirmado em uso em 3 call sites (`worker_help_requests_screen.dart`, `worker_my_job_detail_view.dart`, `client_job_detail_screen.dart`), não tocado. Nenhum ficheiro apagado.

## 2026-09-26 — Wizard "criar pedido" ganha passo 4: rever e publicar

**Contexto:** o wizard de 3 passos publicava diretamente no passo 3 ("Descrição e fotos"), sem
nenhum ecrã de revisão. Referência visual/estrutural fornecida em `doc.txt` (secção "1a. Criar
pedido — Passo 4: Rever e publicar"), apagado depois de integrado.

**Novo ficheiro:** `client_create_job_review_screen.dart` — passo 4/4. Ao contrário do mockup de
referência (presentational puro, wrapper+view separados com `CreateJobReviewViewData`/
`CreateJobPublishResult` injetados), este ecrã lê o `clientCreateJobWizardProvider` diretamente,
igual aos outros 3 passos do wizard — nenhum deles usa esse padrão de wrapper. `AppStepProgress`
passa a `totalSteps: 4` nos 4 ecrãs.

**Publicação move-se do passo 3 para o passo 4:** `createJob` + loop de `uploadJobPhoto` +
`ref.invalidate(clientJobsProvider)` + `reset()` do wizard, tudo movido de
`client_create_job_description_screen.dart` para a revisão. O passo 3 passa a só gravar
descrição/fotos no wizard provider (`setDescriptionAndPhotos` — **existia desde sempre mas nunca
tinha sido chamado em lado nenhum**, confirmado por grep antes de mexer; `description`/`photos`
do provider estavam sempre nos valores por omissão na prática) e a navegar para a revisão; botão
passa de "Publicar pedido" para "Continuar". Fotos continuam como `File` locais até à publicação
real — a revisão só as mostra com `Image.file`/`FileImage`, nunca faz upload.

**Navegação direta para um passo específico — não existia nenhum padrão disto no projeto**
(confirmado: só há `PageView` no onboarding, arquitetura diferente, e `_openSection()` em
`worker_edit_profile_screen.dart`, secções dentro do mesmo ecrã sem rotas próprias). Implementado
com o mínimo de mecanismo: os 3 ecrãs do wizard ganharam um parâmetro `fromReview` (bool, lido de
`?fromReview=true` na query string do router, mesmo padrão já usado para `?workerId=...` em
`client_job_confirmed_screen.dart`) — quando `true`, "Continuar" faz `context.pop()` em vez de
avançar para o próximo passo. Sem provider novo, sem estado duplicado: a revisão e os passos leem
sempre o mesmo `clientCreateJobWizardProvider`, por isso voltar de "Editar" já reflete o que foi
alterado assim que o ecrã editado grava e faz pop.

**Sucesso ao publicar:** `AppSuccessFeedback` + espera de 1100ms (0ms com reduced motion) antes de
navegar para a home — mesmo padrão já usado em `client_rate_worker_screen.dart` — em vez de
navegar imediatamente como o mockup de referência sugeria. Sem SnackBar de sucesso redundante
(fica só para o caso de erro).

**Verificação:** `flutter analyze` (SDK instalado nesta sessão) — 5 issues, todas as mesmas
pré-existentes já confirmadas nas sessões anteriores, zero problemas novos nos 6 ficheiros
tocados.

## 2026-09-26 — Motion Fase 3: fecho dos 2 itens pendentes (LinearProgressIndicator + rating_sheet)

**Contexto:** os 2 itens deixados como "pendentes" no fecho da Fase 3 do motion system.

**`worker_help_requests_screen.dart:837`:** o `LinearProgressIndicator` nunca tinha sido avaliado
contra a regra de skeleton loading (o grep original da auditoria só apanhava
`CircularProgressIndicator`). Contexto real: `_AcceptedCard`, `ratingAsync =
ref.watch(myRatingForJobProvider(jobId))` — decide entre mostrar "Prestador avaliado" ou o botão
"Avaliar o prestador". É "a carregar dados para decidir o que renderizar", não progresso de uma
operação com duração conhecida — trocado por `AppSkeletonShimmer`, mesmo tratamento do resto do
app.

**`rating_sheet.dart`:** ao verificar o padrão real usado nos 3 call sites existentes
(`client_job_detail_screen.dart`, `worker_my_job_detail_view.dart`,
`worker_help_requests_screen.dart`), confirmado que já existia SnackBar de sucesso — a auditoria
anterior estava incompleta (só tinha olhado para `rating_sheet.dart` isolado). O problema real era
a ordem: os 3 callers faziam `pop → invalidate → SnackBar`, invalidando **antes** de mostrar a
confirmação, imediatamente a seguir ao fecho da modal. Dois desses ecrãs
(`client_job_detail_screen.dart`, `worker_help_requests_screen.dart`) fazem `ref.watch` do mesmo
provider que invalidam logo a seguir — mesma classe de risco que motivou o fix do T4 original
("pop → go → snackBar → invalidate"), ainda sem crash reportado mas latente.

**Fix:** `showRatingSheet` ganhou um parâmetro `successMessage` obrigatório e passou a mostrar o
`SnackBar` ele próprio, logo a seguir ao `Navigator.pop`, antes de devolver o resultado ao caller.
Os 3 callers deixaram de duplicar o SnackBar — só fazem `ref.invalidate(...)` depois de
`submitted == true`. Ordem final: pop (dentro da sheet) → SnackBar (dentro da sheet) → invalidate
(no caller), mesma sequência do T4.

**Verificação:** `flutter analyze` corrido (SDK reinstalado nesta sessão, não persiste entre
turnos neste ambiente) — 5 issues, todas as mesmas pré-existentes já confirmadas por diff nas
sessões anteriores (2× `control_flow_in_finally` em `worker_help_requests_lobby_view.dart`, 3×
`unused_field` no enum `_NotificationCategory`). Zero problemas novos.

Isto fecha a Fase 3 do motion system — nenhum item pendente conhecido além da secção colapsável
genérica (documentada como "quando surgir a funcionalidade", não construída por não haver hoje
nenhum caso real que precise).

## 2026-09-26 — Motion Fase 3: ajustes pequenos + estrelas de avaliação partilhadas

**Contexto:** segue-se à auditoria da Fase 3 do motion system (`docs/motion_spec.md` §3) contra o
código real. Implementados os itens classificados como "ajuste pequeno" e "trabalho novo";
secções colapsáveis genéricas ficaram de fora por não haver hoje nenhuma funcionalidade real que
precise disso (regra explícita: não construir só para cumprir a especificação).

**Ajustes pequenos:** `PrimaryActionButton`/FAB central de `AppBottomNavigation` ganharam
scale ao premir (`Listener`, não `GestureDetector`, para não competir com o tap do `FilledButton`
na arena de gestos — 32 e 2 consumidores respetivamente, API pública inalterada);
`AppFilterChip` passou a cross-fade de cor/borda (antes não animava nada); bottom nav ganhou
cross-fade ícone+cor+peso do label (antes trocava tudo instantaneamente, sem sequer diferença de
peso entre estados); `apply_as_helper_screen.dart` (_EquipmentCard/_AvailabilityCard) perdeu o
`AppPulseScale` no ícone de check — estava a criar um segundo loop infinito, violando a regra do
spec de "único loop infinito permitido na app" (reservado à timeline); notificação não-lida ganhou
fade no ponto verde e no fundo tonal; corrigido bug real em `notifications_screen.dart` — o índice
do stagger reiniciava a 0 em cada grupo de data ("HOJE"/"ONTEM"/...), agora usa contador
acumulado (mesmo padrão já usado em `worker_help_requests_lobby_view.dart`); adicionado guard de
`disableAnimations` a 8 animações que o ignoravam (`choose_role_screen`,
`worker_submit_proposal_view` ×2, `onboarding_screen`, `onboarding_page_indicator`, e as 2 de
`apply_as_helper_screen`); 18 sítios de `CircularProgressIndicator` como loading de lista/ecrã/
formulário trocados por `AppSkeletonShimmer` (10 via novo `AppScreenLoadingSkeleton` genérico para
loading de ecrã inteiro, 8 com forma tailored ao conteúdo).

**Trabalho novo:** `RatingStarsInput` (`core/widgets/rating_stars_input.dart`) — widget de 5
estrelas partilhado com entrada em cascata (100ms/estrela, valor bespoke do spec) e pop individual
só na estrela tocada (as que mudam de estado por efeito colateral não animam). Substitui as duas
implementações antigas e inconsistentes: `_RatingStars`/`_RatingStar` privados de
`client_rate_worker_screen.dart` (já tinha pop e `AppSuccessFeedback`, só faltava a entrada em
cascata e usava `Curves.easeOutBack` solto em vez do token `reward`) e as estrelas cruas de
`rating_sheet.dart` (`IconButton`+`Colors.amber`, sem animação nenhuma, sem tokens — era o fluxo
de avaliação mais usado dos dois, 3 dos 4 pontos de entrada). Decisão consciente: não adicionei
`AppSuccessFeedback` ao submit de `rating_sheet.dart` (fica só a fechar a modal sheet) — não fazia
parte do pedido e um overlay de sucesso full-screen dentro de uma bottom sheet merece decisão de
UX própria.

**Fora de âmbito nesta ronda (decisão deliberada):** unificação
`worker_dashboard_screen`↔`workerJobBoardPageProvider`; `LinearProgressIndicator` em
`worker_help_requests_screen.dart:837`; spinner de paginação (fim de lista) em
`worker_jobs_view.dart:420`; spinners de GPS/geocoding e `_ProcessingState` do OCR do cartão
frota (tratados como feedback de ação em curso, mesma categoria que um spinner dentro de um
botão); spinner de boot da app em `app_router.dart`. Nenhum destes estava nas listas de "ajuste
pequeno"/"trabalho novo" da auditoria.

**Verificação:** `flutter analyze` corrido de facto (Flutter 3.47.5/Dart 3.13.4 instalado
localmente para esta sessão — o ambiente não tinha SDK por omissão). Primeira corrida apanhou 1
erro real (`ratings_sheet.dart` — `BorderRadius.circular()` não-const dentro de uma árvore
`const`); corrigido. Segunda corrida: 5 issues, todas confirmadas pré-existentes por diff (2×
`control_flow_in_finally` em `worker_help_requests_lobby_view.dart`, ficheiro não tocado nesta
sessão; 3× `unused_field` no enum `_NotificationCategory` de `notifications_screen.dart`, já
documentado no próprio código como preparado para tipos futuros). Zero problemas novos.

## 2026-09-25 — Cache com TTL em 12 providers `.family` (keepAlive + timer)

**Contexto:** mapeamento prévio (sessão de auditoria só-leitura) identificou que `jobByIdProvider`
e outros `FutureProvider.family` fazem fetch novo sempre que a app navega para um ecrã de detalhe,
mesmo quando os dados já tinham sido carregados por uma lista irmã ou por uma visita recente ao
mesmo ecrã. Nenhum provider do projeto usava `.autoDispose` — por omissão o Riverpod já mantinha
cada valor em memória para sempre (por cada `jobId`/`workerId` alguma vez visto, até a app
reiniciar), sem TTL nem limite de memória.

**Mecanismo:** helper `cacheFor(ref, ttl)` em `lib/core/utils/provider_cache.dart` — chama
`ref.keepAlive()` + `Timer(ttl, link.close)` + `ref.onDispose(timer.cancel)`. Aplicado só a
providers convertidos para `.autoDispose.family`. Efeito: o valor fica disponível sem novo fetch
enquanto alguém o observa OU durante `ttl` depois do último observador sair; passado esse tempo
sem observadores, é disposed (liberta memória, ao contrário do comportamento anterior). Um
`ref.invalidate()` explícito continua a forçar recompute imediato em qualquer altura — dispõe o
estado atual (cancelando o timer via `onDispose`) e o próximo `watch`/`read` corre `create` de
novo. Nenhum ponto de invalidação existente (accept_proposal, accept_help_candidate,
notificationSyncProvider, etc.) foi tocado.

**Providers convertidos e TTL:**
- 5 min (dados quase estáticos — nome/telefone/avatar/bio, edição manual e rara):
  `workerBasicInfoProvider`, `workerPublicCardProvider`, `clientBasicInfoProvider`,
  `ratingSummaryProvider`, `ratingsWithNamesProvider`, `jobPhotosProvider` (write-once, sem UI de
  edição).
- 45s (dados de job/proposta — mudam com alguma frequência, não precisam de estar frescos ao
  segundo): `jobByIdProvider`, `acceptedProposalForJobProvider`, `proposalByIdProvider`,
  `acceptedHelpersForJobProvider`.
- 20s (listas de decisão — o utilizador escolhe uma proposta/candidato a partir daqui, dado mais
  volátil): `pendingProposalsForJobProvider`, `helpRequestsForJobProvider`,
  `candidatesForHelpRequestProvider`. TTL curto por prudência de UX (evitar mostrar uma opção já
  processada), não por risco de corrupção de dados — `accept_proposal`/`accept_help_candidate` já
  validam o estado no servidor (`FOR UPDATE` + check de status) e rejeitam com erro em vez de
  aplicar uma transição inconsistente, cache ou não.

**Fora de âmbito nesta ronda (decisão deliberada, não esquecimento):**
- `workerProposalForJobProvider`, `myRatingForJobProvider`, `myRatingForJobAndRateeProvider`,
  `workerJobBoardPageProvider`, `completedWorkerProposalsProvider` e todos os providers não-family
  (`clientJobsProvider`, `jobsInRadiusProvider`, `pendingWorkerProposalsProvider`, etc.) — não
  tinham TTL atribuído na classificação de risco da sessão de auditoria; alterá-los agora seria
  scope creep sem análise de risco prévia.
- `profileSummaryProvider`/`workerNameProvider` — sem nenhum `ref.watch`/`ref.read` na app (código
  morto); não vale a pena tocar.
- Unificação `worker_dashboard_screen` (trio legado `pendingWorkerProposalsProvider` +
  `scheduledWorkerProposalsProvider` + `jobsInRadiusProvider`) com `workerJobBoardPageProvider`
  (migration 0035, já usado por `worker_jobs_screen`) — identificada como fonte de dados
  duplicada, mas fica para outra sessão: muda o *shape* dos dados consumidos pelo dashboard
  (`WorkerJobBoardEntry` vs `Map<String, dynamic>`), não é uma mudança puramente de cache.
- `ratingSummaryProvider`/`ratingsWithNamesProvider` não são invalidados após
  `submitClientRating`/`submitPrincipalRating`/`submitHelperRating` — gap pré-existente à cache
  (antes ficava stale para sempre; agora fica stale até 5 min), não corrigido nesta sessão.

**Risco residual conhecido:** `flutter analyze` não foi corrido — este ambiente de execução não
tem o Flutter/Dart SDK instalado (sem `flutter`/`dart` no PATH, sem `.dart_tool`, dependências
nunca foram `pub get`). Verificação feita manualmente: `Ref` já é usado como tipo direto de
parâmetro noutro sítio do código (`notification_providers.dart:_invalidateWorkerJobBoard`),
confirmando que é o tipo unificado desta versão de Riverpod (3.3.1) e que `cacheFor(Ref ref, ...)`
tipa corretamente contra os callbacks de `.autoDispose.family`; grep confirmou que nenhum dos 12
providers é referenciado com tipo explícito (`FutureProvider<T>`) fora do próprio ficheiro que o
declara, e que os dois únicos locais que fazem `ref.read(provider(x)).value` (em vez de
`ref.watch`) — `client_job_detail_screen.dart:68` e `worker_help_requests_lobby_screen.dart:111`
— só são chamados a partir de handlers de botão no mesmo widget que já observa o mesmo provider
no `build()`, logo o provider nunca está sem observador nesses pontos. Correr `flutter analyze`
antes de merge continua recomendado.

## 2026-09-08 — Cartão frota (fuel card): OCR local + aprovação manual (migration 0037)

**Contexto:** item "Carteira digital de cartões" em `improvements.md` estava bloqueado por decisão de negócio (falta de parceria com emissor de cartões frota). Desbloqueado ao trocar a integração real por um fluxo com dados fictícios: o worker fotografa o seu próprio cartão, o telemóvel faz OCR local (`google_mlkit_text_recognition`), e o pedido fica `pending` até ser ativado manualmente via SQL Editor — reaproveita o padrão de moderação já existente em `job_reports`.

**Nova tabela `worker_fleet_cards`** (migration `0037_worker_fleet_cards.sql`, **não aplicada**): `id, worker_id, card_number nullable, barcode_value, holder_name nullable, status ('pending'|'active'|'rejected'), created_at`. RLS: `authenticated` só tem SELECT/INSERT do próprio `worker_id`; **sem policy de UPDATE nem DELETE** — só o service role muda `status`, exatamente como em `job_reports`. Sem `UNIQUE` em `worker_id`: um pedido `rejected` seguido de "tentar novamente" cria uma nova linha em vez de fazer upsert; o repositório lê sempre a mais recente (`ORDER BY created_at DESC LIMIT 1`), preservando o histórico de tentativas.

**A foto nunca é enviada nem guardada:** sem bucket de Storage novo. `FleetCardTextExtractor.extract()` corre o `TextRecognizer` sobre o ficheiro temporário do `image_picker` e apaga-o no `finally`, sucesso ou falha, antes do ecrã de scan sequer navegar para o de confirmação.

**Barcode renderizado como QR (`qr_flutter`)**, não como código de barras 1D — evita introduzir uma dependência nova só para isto, reaproveitando o padrão já usado no cartão partilhável do worker (`worker_profile_screen._showQrDialog`).

**Pequenos desvios face ao pedido original:** `gen_random_uuid()` → `uuid_generate_v4()` (consistência com `0001_consolidated_baseline.sql`, que usa `uuid_generate_v4()` em todas as tabelas); adicionado `CHECK (status IN (...))` e um índice em `worker_id` (convenção já usada nas outras tabelas do projeto, não estava no pedido). Ecrã de confirmação (`FleetCardConfirmDataScreen`) não tem campo `cardId` — o fluxo só cria, nunca edita (RLS bloqueia UPDATE), por isso um `cardId` sintético não teria consumidor real.

`flutter analyze`: 0 issues.

## 2026-07-12 — Bug fix AppTextField multiline + reskin landing_screen

**Bug fix `app_text_field.dart`:** `maxLines` alterado de `int` (não-nullable) para `int?` (nullable, default `1`). Adicionado `minLines: int?`. Ambos passados ao `TextFormField`. A versão anterior com `int` causava assertion crash quando se passava `TextInputAction.newline` sem `keyboardType: TextInputType.multiline` — o fix também exige que o caller passe os dois.

**Bug fix `worker_setup_screen.dart` campo bio:** `maxLines: 3 + textInputAction.newline` → `maxLines: 5, minLines: 3, keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline`. Combinação válida — campo de apresentação expande entre 3 e 5 linhas.

**`landing_screen.dart` reskinned:** `AppBrandBadge(size:100)` substitui `Icon(Icons.yard)`; texto "ProJardim" via `textTheme.displaySmall`; tagline via `textTheme.bodyMedium + AppColors.textSecondary`; `FilledButton` → `PrimaryActionButton`; `OutlinedButton` estilizado com `AppColors.primary` border + `AppRadius.card`. Fundo `AppColors.background`. Navegação inalterada (`context.push`).

**Ocorrências de "LocalServices" ainda por corrigir (aguarda confirmação):**
- `app.dart:41` → `title: 'LocalServices'` (título do MaterialApp — aparece no task switcher do SO)
- `worker_home_screen.dart:25` → `AppBar title: Text('LocalServices')`
- `client_home_screen.dart:30` → `AppBar title: Text('LocalServices')`

`flutter analyze`: 0 issues.

---

## 2026-07-12 — Reskin visual: 4 ecrãs de auth + 3 widgets partilhados

**Widgets criados em `lib/core/widgets/`:**
- `primary_action_button.dart` — `FilledButton` full-width, `isLoading` spinner, `AppRadius.card`, disabled via `textSecondary.withValues(alpha:0.4)`
- `app_text_field.dart` — `TextFormField` com `AppRadius.input`, `AppColors.divider`/`primary`, suporte a `maxLines`/`suffixIcon`/`autofillHints`. Todos os TextStyle via `Theme.of(context).textTheme`.
- `app_brand_badge.dart` — ícone circular com `AppColors.primaryContainer` e `Icons.eco_outlined`.

**Ecrãs reskinned (lógica intacta, só visual alterado):**
- `choose_role_screen.dart` — sem AppBar; título "Como quer usar a ProJardim?"; `_RoleSelectionCard` com borda `AppColors.primary`/`divider`, fundo `primaryContainer`/`surface`, radio indicator animado. Usa `UserRole.client/worker` (enum existente).
- `login_screen.dart` — sem AppBar; `AppBrandBadge` + "Bem-vindo de volta"; `AppTextField` para email/password; botão "Esqueci-me da senha" desativado (`onPressed: null`); botão Google desativado (`onPressed: null`) — ambos visíveis mas não funcionais.
- `signup_screen.dart` — sem AppBar; header row com back button; `AppTextField` x4; barra de força de password (`_PasswordStrength`) visual usando `AppStatusColor.success`; checkbox de termos com `_acceptedTerms` — botão desativado se não aceite; `TapGestureRecognizer` removido dos termos (links estilizados mas não funcionais por enquanto).
- `worker_setup_screen.dart` — sem AppBar; header com título; `_PhotoSection` (CircleAvatar 52px + câmara overlay); chips de serviços com `AppColors.primaryContainer`/`primaryPressed`/`AppRadius.pill`; localização mostra container verde `AppStatusColor.success` quando definida; botão guardar fixo no fundo via `PrimaryActionButton`. Toda a lógica (GPS, geocoding, ImagePicker, serviceTypesProvider, _save()) intacta.

**Mapeamento de cores aplicado:** `primaryDark→primaryPressed`, `border→divider`, `borderStrong→primary`, `selectedSurface/surfaceAlt→primaryContainer`, `disabled→textSecondary.withValues(alpha:0.4)`, `success/successSoft→AppStatusColor.success.foreground/.background`.

**BorderRadius:** `16→AppRadius.card` (botões/cards), `12→AppRadius.input` (campos), `999→AppRadius.pill` (chips).

`flutter analyze`: 0 issues.

---

## 2026-07-12 — Limpeza splash + tokens órfãos + AppStatusColor.cancelled

**splash_screen.dart e projardim_logo_mark.dart eliminados** — o ecrã de splash nunca chegou a ser wired numa rota e a decisão foi não utilizá-lo. `ProJardimLogoMark` (CustomPainter) só era usado pelo splash, pelo que foi removido em conjunto.

**Tokens removidos de app_colors.dart:** `splashTop`, `splashBottom`, `white` — exclusivos do splash eliminado. `logoAccent` mantido: ainda usado por `onboarding_illustration.dart` para os dots decorativos.

**status_timeline.dart:** círculo do estado `cancelled` (`Color(0xFFE53935)`) substituído por `AppStatusColor.cancelled.foreground`. Todos os hardcodes de cor removidos do widget.

`app_colors.dart` final: 10 tokens sem órfãos — `primary`, `accent`, `primaryContainer`, `primaryPressed`, `background`, `surface`, `textPrimary`, `textSecondary`, `divider`, `logoAccent`.

`flutter analyze`: 0 issues.

---

## 2026-07-12 — Tokens de design finais: app_colors, app_typography, app_radius, app_status_color

`AppColors.primary` revertido de `0xFF3F7F2F` para `0xFF2E7D32` (valor oficial confirmado pelo kit visual). Adicionados 9 novos tokens ao `AppColors`: `accent`, `primaryContainer`, `primaryPressed`, `background`, `surface`, `textPrimary`, `textSecondary`, `divider`; removido `statusActive` (substituído por `AppStatusColor`). `splashTop`/`splashBottom`/`logoAccent` mantidos como tokens de splash separados da paleta funcional.

**`app_typography.dart` criado:** 5 estilos constantes (`display`/`title`/`subtitle`/`body`/`caption`) com tamanhos/pesos/espaçamentos oficiais. Integrado em `app_theme.dart` via `GoogleFonts.plusJakartaSans(textStyle: AppTypography.X).copyWith(...)` nos 5 níveis mapeados (`displaySmall`/`titleLarge`/`titleMedium`/`bodyMedium`/`labelMedium`). Nenhum widget usa `AppTypography` diretamente — `Theme.of(context).textTheme` continua a ser a API de acesso.

**`app_radius.dart` criado:** `input=12`, `card=16`, `pill=999`.

**`app_status_color.dart` criado:** enum `AppStatusColor { waiting, success, inProgress, cancelled }` com getters `.background` e `.foreground`. `status_timeline.dart` actualizado: `AppColors.statusActive` removido, ambos os usos (círculo e conector do estado `done`) substituídos por `AppStatusColor.success.foreground`. Nota: círculo do estado `cancelled` (`0xFFE53935`) não foi alterado — valor do kit visual a confirmar.

Gradiente do splash (`splashTop`/`splashBottom`) ainda não foi migrado para `primary`/`primaryPressed` — decisão pendente, a confirmar com o utilizador.

`flutter analyze`: 0 issues.

---

## 2026-07-12 — Onboarding 3 slides + atualização AppColors.primary

`AppColors.primary` atualizado de `0xFF2E7D32` para `0xFF3F7F2F`. Propaga via `ColorScheme.fromSeed` e `AppColors.primary` — sem mais hardcodes na codebase.

Criados `onboarding_illustration.dart` (`OnboardingIllustration` + `_IllustrationBgPainter` CustomPainter com background circular e dots decorativos) e `onboarding_page_indicator.dart` (`OnboardingPageIndicator` com pill animado 220ms). `onboarding_screen.dart` substituído por `ProJardimOnboardingScreen` (ConsumerStatefulWidget, 3 slides, 330ms, modo compacto height < 700, "Saltar"/"Continuar"/"Começar", `markSeen()` + `context.go('/')` no último slide). Router actualizado para usar `ProJardimOnboardingScreen`. Splash (`ProJardimSplashScreen`) permanece em `splash_screen.dart` — ligação splash → slides fica para próxima sessão.

`flutter analyze`: 0 issues.

---

## 2026-07-12 — Splash/Onboarding + tipografia global + tokens de cor

**Dependências adicionadas:** `google_fonts: ^6.2.1` (resolvido 6.3.3), `shared_preferences: ^2.3.3`.

**app_colors.dart criado:** tokens `primary`, `splashTop/Bottom`, `white`, `logoAccent`, `statusActive`. Elimina os dois Color hardcoded (P2/M2 resolvido).

**Tipografia global:** `GoogleFonts.plusJakartaSansTextTheme` aplicado em `AppTheme.light()`. Nenhum widget chama GoogleFonts diretamente — todos usam `Theme.of(context).textTheme`.

**Feature onboarding criada:** `features/onboarding/` com `data/onboarding_prefs_service.dart`, `application/onboarding_providers.dart` (`OnboardingPrefsService` + `OnboardingNotifier` / `hasSeenOnboardingProvider`), `presentation/splash_screen.dart` (`ProJardimSplashScreen` com Fade/Scale/Slide), `presentation/widgets/projardim_logo_mark.dart` (CustomPainter), `presentation/onboarding_screen.dart` (wrapper ConsumerWidget).

**Routing:** rota `/onboarding` adicionada. `RouterNotifier` escuta `hasSeenOnboardingProvider` (pre-warm + reatividade após `markSeen()`). Guard no redirect: utilizadores não autenticados que ainda não viram o onboarding são redirecionados para `/onboarding`; utilizadores autenticados nunca são redirecionados. Leitura da flag é síncrona sobre `AsyncData` já resolvido — se ainda loading, retorna null (mesmo padrão da sessão).

`flutter analyze`: 0 issues.

---

## 2026-07-10 — P8/B4 resolvido: chamada Supabase em widget movida para AuthRepository.fetchNameAndPhone

`worker_setup_screen.dart:189` — `ref.read(supabaseClientProvider).from('profiles').select('full_name, phone')` movido para `AuthRepository.fetchNameAndPhone(userId)`. Widget usa agora `ref.read(authRepositoryProvider).fetchNameAndPhone(...)`. Comportamento idêntico; 0 violações arquiteturais.

---

## 2026-07-09 — Auditoria de docs e roadmap (Task 2)

Leitura de todos os ficheiros em `docs/` e dos ficheiros chave de `lib/` (proposal_repository, job_repository, worker_setup_screen, reschedule_dialog). Itens verificados contra código real:

**B2 Fase 8 — CONFIRMADO RESOLVIDO:** `reschedule_dialog.dart:27` usa `firstDate: DateTime.now().add(const Duration(days: 1))` — impede seleção de data passada. Marcado resolvido em `improvements.md`.

**P8/B4 — CONFIRMADO ABERTO:** `worker_setup_screen.dart:190` faz `ref.read(supabaseClientProvider).from('profiles').select(...)` diretamente no widget — única violação do princípio arquitetural #2.

**decisions_log.md — quase completo:** todas as sessões de 2026-07-01 a 2026-07-09 têm entradas. Nenhuma entrada em falta identificada — o que o utilizador enumerou em STEP 2 estava já documentado nas entradas existentes.

**Criado `docs/STATUS.md`:** snapshot honesto do estado do projeto — o que funciona end-to-end, gaps conhecidos (CRÍTICO/ALTO/MÉDIO/BAIXO), postura de segurança, o que é necessário antes do primeiro utilizador real.

**Atualizado `docs/improvements.md`:** secção `🗺️ Roadmap limpo` adicionada com tabelas CRÍTICO/ALTO/MÉDIO/PÓS-LANÇAMENTO; B2 Fase 8 movida para resolvida.

`flutter analyze`: 0 issues.

---

## 2026-07-09 — Consolidação de migrations em baseline único

### Contexto

31 migrations incrementais (0001–0032, sem 0015) arquivadas em `supabase/migrations/archive/`. Um único ficheiro `0001_consolidated_baseline.sql` substitui-as para novos projetos. **NÃO APLICADO — aplicar manualmente via SQL Editor.**

### Decisões tomadas

**Fonte de verdade para o schema:** `snapshot_tables.csv` (2026-07-09) é autoritativo para colunas, constraints, indexes e RLS policies. Para tabelas não incluídas no snapshot query (`service_categories`, `job_photos`) e funções não capturadas (`reject_proposal`, `withdraw_proposal`, `confirm_job_completion`, `worker_has_proposal_for_job`, `notify_workers_new_job`), usou-se `0001_baseline.sql` do arquivo.

**FKs corrigidos no baseline:** `job_proposals.worker_id` e `help_acceptances.worker_id` apontam para `profiles(id)` (correto), não para `worker_profiles(profile_id)` (estado actual do live DB, a ser corrigido via 0032).

**Funções com auth checks:** `accept_proposal`, `create_proposal`, `sync_worker_service_types` incluem os checks de `auth.uid()` de 0032, não os corpos pré-0032 do snapshot.

**`snapshot_a.csv` e `snapshot_b.csv` não existem:** Todos os dados do snapshot foram lidos de um único ficheiro `snapshot_tables.csv`. Documentado no README e no cabeçalho do ficheiro.

**Discrepâncias snapshot vs. 0001_baseline encontradas:**
- `profiles.phone`: nullable no live DB (snapshot: sem NOT NULL); 0001 criou como NOT NULL — baseline usa nullable.
- `job_requests.confirmed_flexible`: nullable boolean no live DB; 0001 criou como `NOT NULL DEFAULT false` — baseline usa nullable.
- 6 indexes do 0001 ausentes do live DB (CREATE TABLE IF NOT EXISTS skipped body) — incluídos no baseline via 0032.

**Seed data preservada:** 1 service_category (gardening) + 3 service_types incluídos via `ON CONFLICT DO NOTHING`.

**pg_cron:** 2 jobs documentados e incluídos (`auto-expire-jobs`, `auto-confirm-completed-jobs`), ambos a cada 3 horas.

**Storage:** Buckets `avatars` e `job-photos` (public=true) com as 7 policies do live DB. `worker-photos` (do 0001) omitido — não está em uso no app e não estava no snapshot.

---

## 2026-07-09 — Auditoria completa B1-B4 (DB) + C1-C4 (Dart) + migration 0032

### Contexto

Auditoria de segurança e correctness em duas camadas: (1) schema/RLS/funções via `snapshot_tables.csv`; (2) código Dart via leitura de todo `lib/`. Achados documentados em tabelas B1-B4 e C1-C4. Migration 0032 escrita para corrigir os itens críticos e altos. **NÃO APLICADA — aplicar manualmente via SQL Editor.**

---

### B2-C1 CRÍTICO: FKs quebrados causavam null em nomes/avatares de workers (produção)

**Root cause confirmado:** `job_proposals_worker_id_fkey` e `help_acceptances_worker_id_fkey` apontavam para `worker_profiles(profile_id)` em vez de `profiles(id)`. Migration 0031 foi um no-op silencioso: usou `IF NOT EXISTS` para verificar a existência do constraint pelo nome, encontrou-os (apontando para a tabela errada), e saltou o `ADD CONSTRAINT`. As strings de join `profiles!job_proposals_worker_id_fkey(full_name, avatar_url)` e `profiles!help_acceptances_worker_id_fkey(full_name, avatar_url)` em `proposal_repository.dart:42` e `help_request_repository.dart:88` pediam ao PostgREST para resolver o join via um FK cujo destino era `worker_profiles`, não `profiles` — join silenciosamente nulo.

**Fix (migration 0032, Priority 1):** DROP ambos os constraints; ADD CONSTRAINT apontando para `profiles(id) ON DELETE CASCADE`. Os dados existentes são consistentes (worker_id = profiles.id = worker_profiles.profile_id — mesmo UUID). O hint de join em Dart não muda: o nome do FK mantém-se, só o destino muda.

**Semântica de CASCADE após a mudança:** Apagar um profile cascada diretamente a job_proposals e help_acceptances (novo FK directo) e a worker_profiles (FK existente). Resultado final idêntico ao anterior.

**Após aplicar:** executar `NOTIFY pgrst, 'reload schema'` (ou reiniciar PostgREST no dashboard) para que o schema cache seja atualizado e os embed joins funcionem.

---

### B2 CRÍTICO: accept_proposal sem verificação de auth.uid() = client_id

**Vulnerabilidade:** qualquer utilizador autenticado que conhecesse um `proposal_id` e `job_id` podia chamar `rpc('accept_proposal', ...)` e aceitar uma proposta em nome do cliente — confirmando o job, notificando o worker, e criando um help_request automaticamente. A função é `SECURITY DEFINER`, by-passa RLS completamente.

**Fix (migration 0032, Priority 2a):** `CREATE OR REPLACE FUNCTION accept_proposal` com check no início: `IF NOT EXISTS (SELECT 1 FROM job_requests WHERE id = p_job_id AND client_id = auth.uid()) THEN RAISE EXCEPTION ...`. Resto do corpo idêntico ao snapshot.

---

### B2 CRÍTICO: create_proposal sem verificação de p_worker_id = auth.uid()

**Vulnerabilidade:** qualquer autenticado podia passar `p_worker_id = victim_uuid` e submeter uma proposta em nome de outro worker — incrementando o `proposal_count` do job da vítima, enviando notificação ao cliente com o nome errado, e bloqueando o slot de proposta da vítima nesse job.

**Fix (migration 0032, Priority 2b):** `IF p_worker_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Não autorizado.'` no início de `create_proposal`. Usa `IS DISTINCT FROM` para segurança com NULL.

---

### B2 CRÍTICO: sync_worker_service_types sem verificação de p_worker_id = auth.uid()

**Vulnerabilidade:** qualquer autenticado podia chamar `rpc('sync_worker_service_types', {'p_worker_id': victim_uuid, 'p_service_type_ids': []})` e apagar todos os tipos de serviço de outro worker. A policy `ALL USING (auth.uid() = worker_id)` em `worker_service_types` é bypassed por SECURITY DEFINER.

**Fix (migration 0032, Priority 2c):** `IF p_worker_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Não autorizado.'` no início de `sync_worker_service_types`.

---

### B3 ALTO: profiles.role escalação via UPDATE directo

**Vulnerabilidade:** a policy `"Utilizador atualiza o seu perfil"` tinha `USING (auth.uid() = id)` mas nenhum `WITH CHECK`. Um utilizador podia enviar `PATCH /profiles?id=eq.<uid>` com `{"role":"worker"}` e a BD aceitava — qualquer `client` tornava-se `worker` (ou vice-versa) sem nenhum obstáculo.

**Fix (migration 0032, Priority 3):** Trigger `tg_prevent_profile_role_change` (`BEFORE UPDATE ON profiles FOR EACH ROW`) que lança exceção se `NEW.role IS DISTINCT FROM OLD.role`. Trigger é o guard primário porque `WITH CHECK` em políticas de UPDATE só tem acesso ao NEW row — impossível comparar com OLD.role em RLS. A policy foi recreada com `WITH CHECK (auth.uid() = id)` para consistência (não adiciona protecção de role por si só).

---

### B3: Políticas SELECT de profiles ausentes de todas as migrations

**Achado:** o live DB tinha três políticas SELECT granulares em `profiles` que substituíram a policy broad `USING(true)` do 0001_baseline via sessões interativas. Ausentes de todas as migrations 0001-0031 — rebuild a partir de migrations deixaria qualquer autenticado a ler qualquer perfil.

**Fix (migration 0032, Priority 5):**
- DROP `"Perfis são legíveis por utilizadores autenticados"` (0001 — broad, não estava no live DB)
- CREATE `"Utilizador vê o seu perfil"` — USING: `auth.uid() = id`
- CREATE `"Worker ve perfil de cliente com job confirmado"` — USING: join via accepted proposal
- CREATE `"Cliente ve perfil de worker com job confirmado"` — USING: `role = 'worker' AND client_has_confirmed_job_with_worker(id)`

---

### C2 MÉDIO: fetchCompletedWorkerProposals — filtro client-side antes de paginação

**Problema:** a query usava `.range(page * pageSize, ...)` antes de filtrar `job_requests.status == 'completed'` no cliente. Páginas podiam ter menos items que `pageSize` mesmo com mais dados disponíveis — utilizador chegava ao fim prematuro.

**Fix (Dart, proposal_repository.dart):** substituído filtro client-side por `.filter('job_requests.status', 'eq', 'completed')` — mesmo padrão já usado em `fetchScheduledWorkerProposals` (`.filter('job_requests.status', 'in', '(confirmed,awaiting_confirmation)')`). PostgREST usa semântica INNER JOIN para filtros em embedded resources, por isso o RANGE/LIMIT é aplicado após o filtro. TODO e `.where()` client-side removidos.

---

### C2 MÉDIO: job_repository.createJob usa .single() após INSERT

**Problema:** `.insert(...).select('id').single()` lança `PostgrestException` se a SELECT policy não cobrir o próprio row (teoricamente impossível — a policy SELECT é `USING: auth.uid() = client_id` e o insertor é o cliente), mas `.single()` é estritamente mais frágil que `.maybeSingle()`.

**Fix (Dart, job_repository.dart):** `.single()` → `.maybeSingle()` com null check explícito: `if (result == null) throw Exception('Job criado mas SELECT não devolveu dados.')`.

---

### Riscos aceites (B4) — documentados como trade-offs intencionais

**auto_confirm_completed_jobs e auto_expire_jobs chamáveis por qualquer autenticado:**
Ambas são SECURITY DEFINER sem `auth.uid()` check. Qualquer utilizador pode chamar via RPC. Efeito real: `auto_confirm` é idempotente (muda jobs `awaiting_confirmation` com `updated_at > 3 dias` para `completed` — no máximo adianta jobs que seriam confirmados de qualquer forma); `auto_expire` move jobs `open` com `expires_at < now()` para `no_response` — também idempotente. O impacto de uma chamada não autorizada é mínimo e não há dados sensíveis expostos. Fix recomendado em fase futura: adicionar `IF auth.uid() IS NULL THEN RAISE EXCEPTION` — não bloqueia a cron mas bloqueia chamadas via RPC externo.

**Ratings INSERT — sem verificação de participação:**
A policy `"Utilizador cria a sua avaliação"` verifica `auth.uid() = rater_id` mas não que o rater participou no job. Um utilizador autenticado pode inserir uma avaliação para qualquer `job_id` e `ratee_id` (o check `check_rater_not_ratee` apenas impede auto-avaliação). As RPCs `submit_client_rating`, `submit_principal_rating`, `submit_helper_rating` são SECURITY DEFINER e fazem verificação de participação completa — devem ser usadas em vez do INSERT directo. O INSERT directo (via REST) sem passar pelas RPCs é um bypass da lógica de negócio; a layer Dart usa sempre as RPCs. Risco aceite no MVP enquanto as RPCs forem o único ponto de acesso.

**Storage INSERT policies sem verificação de path:**
As policies `"Upload avatar autenticado"` e `"Upload autenticado em job-photos"` verificam apenas `auth.role() = 'authenticated'`. Qualquer autenticado pode fazer upload para qualquer path em `avatars` e `job-photos`. A policy de DELETE verifica ownership do path — é possível sobrescrever o avatar de outro utilizador (o path de um avatar é `<userId>.jpg`; a policy de UPDATE verifica o filename, mas o INSERT não). Risco aceite no MVP.

---

### C4: T4 ordering anti-patterns (6 ocorrências) — sem crash em código atual

**Achado:** 6 locais onde `ref.invalidate()` é chamado antes de `router.go()`/`router.pop()`. Verificado via `ref.watch` de cada ecrã que nenhum deles observa os providers invalidados — sem risco de crash T4 no código atual. Ficam como anti-patterns que se tornarão bugs reais se esses providers forem adicionados ao `build()` dos respectivos ecrãs. Documentados como Low, não corrigidos.

---

### Skipped / Não corrigido nesta sessão

- **T4 ordering anti-patterns** (6 locais) — Low, não crash-causing atualmente
- **auto_confirm/expire auth check** — Low, impacto mínimo, aceite no MVP
- **Ratings INSERT policy** — Low, aceite no MVP (RPCs são o único ponto de acesso)
- **Storage INSERT policies** — Low, aceite no MVP
- **worker_setup_screen.dart direct Supabase call** — Medium/Architecture, sem impacto de segurança

## 2026-07-07 — F10-S4 fix definitivo: worker_profiles RLS + view + FKs directos + geocoding

**Decisão de design:** `worker_profiles` restrito a owner-only SELECT (`profile_id = auth.uid()`). View pública `worker_profiles_public` expõe colunas seguras (`bio`, `radius_km`, `tools`, `location_name`, `photos`) a qualquer utilizador autenticado. View criada **sem `security_invoker`** (definer-style, default PostgreSQL) — é deliberado: com `security_invoker=true` a view retornaria 0 rows para não-owners, silenciosamente, sem erro. Diferença crítica face a `worker_rating_summary` (0028, que usa `security_invoker=true` corretamente porque a sua tabela subjacente tem `USING(true)` — sem restrição a bypassed).

**Migration 0031** (`0031_missing_profile_fks.sql`) — NOT APLICADA:
- Adiciona `job_proposals_worker_id_fkey` → `profiles(id)` (FK declarado em 0001_baseline mas nunca registado em `pg_constraint` — mesmo root cause do 0029)
- Adiciona `help_acceptances_worker_id_fkey` → `profiles(id)` (idem)
- Puramente aditivo; zero alteração de comportamento; seguro a qualquer momento

**Migration 0030** (`0030_worker_profiles_security.sql`) — NOT APLICADA (aplicar DEPOIS de 0031 + Dart Phase B verificados em prod):
- `ADD COLUMN IF NOT EXISTS location_name text`
- DROP `"Worker profiles são públicos"` (USING(true) — causa raiz de F10-S4)
- DROP `"Cliente ve perfil de worker com job confirmado"` (0027 — também expunha base_lat/base_lng a clientes confirmados)
- CREATE `"Worker lê o seu próprio perfil"` — `USING (profile_id = auth.uid())`
- CREATE VIEW `worker_profiles_public` (definer-style, sem security_invoker) — `bio, radius_km, tools, location_name, photos`
- INSERT/UPDATE policies não afetadas (`"Worker cria o seu próprio worker profile"`, `"Worker atualiza o seu próprio worker profile"`)

**Phase B Dart** — selects atualizados para join directo (não via worker_profiles):
- `proposal_repository.dart:42` — `profiles!job_proposals_worker_id_fkey(full_name, avatar_url)`
- `help_request_repository.dart:88` — `profiles!help_acceptances_worker_id_fkey(full_name, avatar_url)`
- `proposal_model.dart` + `help_request_model.dart` fromJson — `json['profiles']` (um nível)
- Phase B3: grep exaustivo de `lib/` para `worker_profiles(` como join target — zero ocorrências adicionais

**Phase D Dart** — `create_job_screen.dart`: `GeocodingService.reverseGeocode` chamado após GPS (`_getLocation`) e tap no mapa (`_onMapTap`). Só preenche `_addressController` se estiver vazio — não sobrescreve input manual. Import `geocoding_service.dart` adicionado.

**Ordem de aplicação obrigatória:** 0031 (apply) → Dart Phase B (deploy + verify) → 0030 (apply). Inverter causa janela de quebra.

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Security fix: worker_profiles USING(true) eliminado + GeocodingService (Nominatim)

**Achado de segurança (alta severidade):** a policy `"Worker profiles são públicos"` (0001_baseline.sql) usava `USING (true)` — qualquer utilizador autenticado podia ler `base_lat` e `base_lng` de qualquer worker diretamente via REST. A policy `"Cliente ve perfil de worker com job confirmado"` (migration 0027) ia na mesma direção mas com scope mais restrito.

**Migration 0030** (escrita, NOT APLICADA — aplicar via Supabase SQL Editor):
1. `ALTER TABLE worker_profiles ADD COLUMN IF NOT EXISTS location_name text` — nome público da cidade/zona do worker (sem rua ou coordenadas exatas).
2. DROP `"Worker profiles são públicos"` + DROP `"Cliente ve perfil de worker com job confirmado"` em `worker_profiles`.
3. CREATE `"Worker lê o seu próprio perfil"` — `USING (profile_id = auth.uid())` — worker lê apenas o seu próprio row.
4. CREATE VIEW `public.worker_profiles_public` (`WITH (security_invoker = true)`) — expõe `profile_id, bio, service_radius_km, tools_description, location_name, created_at, updated_at` — sem `base_lat`, `base_lng`, sem `photos`. GRANT SELECT TO authenticated.

**Reads de Dart que precisam de atenção após migration aplicada (NOT alterados agora):**
- `proposal_repository.dart` — join `.select('*, worker_profiles(profiles!...fkey(...))')` chamado pelo cliente. Após remoção da policy de cliente, join devolve null. **Precisa de update para join direto em `profiles`.**
- `help_request_repository.dart` — join `.select('*, worker_profiles(profiles(...))')` chamado pelo worker principal para ver candidatos. Worker A não pode ler `worker_profiles` de worker B após migration. **Precisa de update.**
- `worker_repository.dart fetchProfile()` / `hasProfile()` — leem o próprio row — continuam a funcionar.

**GeocodingService** — `lib/core/services/geocoding_service.dart`:
- Nominatim (OpenStreetMap) — gratuito, sem API key, via `http: ^1.2.2`
- `reverseGeocode(lat, lng)` → `({String locationName, String addressText})?`
- `locationName` = cidade/town/village/county mais específico disponível (para `worker_profiles.location_name`)
- `addressText` = rua + número + código postal + cidade (para uso futuro como `address_text` padrão em criação de job)
- User-Agent: `ProJardim/1.0 (projardim@example.com)` — obrigatório pela política Nominatim
- Retorna `null` em qualquer erro — callers não crasham

**Wiring:** `worker_setup_screen.dart` e `worker_profile_screen.dart` — após GPS ou pesquisa de morada, fire-and-forget `GeocodingService.reverseGeocode` → `_locationName` em estado → passado a `WorkerProfile(locationName: ...)` no save. `toWorkerJson()` inclui `location_name` condicionalmente (`if (locationName.isNotEmpty)`) — evita erro PostgREST antes de migration aplicada.

`flutter analyze`: 0 issues. Migration 0030 NOT aplicada.

---

## 2026-07-06 — AddressMapLink: render por coordenadas, não por address text

**Problema:** `AddressMapLink` nunca aparecia porque todos os callers usavam `if (job.addressText.isNotEmpty)` como guard — e `address_text` estava vazio/null nos dados de teste.

**Fix em 3 partes:**

1. **`address_map_link.dart`** — widget agora renderiza sempre que `lat != 0 || lng != 0`. Se `address` estiver vazio, mostra "Ver no mapa" como label. Só oculta com `SizedBox.shrink()` se `lat == 0 && lng == 0` (sem dados de localização).

2. **Guards substituídos** — `if (job.addressText.isNotEmpty)` → `if (job.locationLat != 0 || job.locationLng != 0)` em todos os 8 pontos de chamada:
   - `client_job_detail_screen.dart`
   - `worker_home_screen.dart`
   - `worker_jobs_screen.dart`
   - `client_jobs_screen.dart`
   - `worker_job_detail_screen.dart` (detalhe + `_ProposalSheet`)
   - `worker_my_job_detail_screen.dart`
   - `worker_help_requests_screen.dart` (`_AcceptedCard`)

3. **`job_model.dart`** — `json['address_text'] as String` → `json['address_text'] as String? ?? ''` — null-safe, evita crash em runtime se a coluna estiver NULL na BD.

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Google Maps integration completa em todos os ecrãs

**URL verificado:** `https://www.google.com/maps/search/?api=1&query=$lat,$lng` via `LaunchMode.externalApplication`. Sem `canLaunchUrl()` — só `launchUrl`. AndroidManifest já tem `<data android:scheme="https"/>` em queries — sem alterações ao manifesto.

**AddressMapLink** (ícone + label "Localização" + morada sublinhada + seta externa) adicionado a:
- `worker_home_screen.dart` — discovery card (substituiu GestureDetector inline)
- `worker_job_detail_screen.dart` — detalhe do pedido + topo do `_ProposalSheet`
- `worker_my_job_detail_screen.dart` — já existia
- `worker_jobs_screen.dart` — cards de propostas (todas as tabs) — **adicionado agora**
- `client_job_detail_screen.dart` — aba Detalhes para todos os estados — **adicionado agora**
- `client_jobs_screen.dart` — cards da lista (plain text substituído por link tappable) — **adicionado agora**
- `worker_help_requests_screen.dart` `_AcceptedCard` — já existia

**Compact map link** (ícone + "Ver no mapa" inline) adicionado a:
- `worker_help_requests_screen.dart` `_HelpRequestCard` (discovery) — **adicionado agora**. `HelpRequestSummary` tem lat/lng mas não `address_text` (RPC `get_help_requests_in_radius` não o devolve) — AddressMapLink inaplicável; link compacto com coordenadas diretas.

**Nota:** o endereço em `client_job_detail_screen.dart` é do próprio pedido do cliente — sem exposição de morada de terceiros.

---

## 2026-07-06 — Bug 3 causa raiz confirmada e corrigida (migration 0029 — NOT APLICADA)

**Causa raiz:** PostgREST devolve `worker_profiles: {profiles: null}` no join de dois saltos `worker_profiles(profiles(full_name, avatar_url))` apesar do JOIN SQL direto funcionar corretamente. A causa mais provável é que o FOREIGN KEY `worker_profiles.profile_id → profiles(id)` (declarado inline em 0001_baseline.sql com `PRIMARY KEY REFERENCES profiles(id)`) está ausente de `pg_constraint` na BD viva — possivelmente porque `CREATE TABLE IF NOT EXISTS` saltou o corpo da tabela quando a tabela já existia sem o FK. Sem este FK em `pg_constraint`, o PostgREST não consegue construir o segundo salto do join no schema cache e retorna null silenciosamente.

**Evidência:** a live query SQL (`JOIN wp ON wp.profile_id = jp.worker_id JOIN p ON p.id = wp.profile_id`) resolve `full_name` corretamente — os dados e a UUID estão certos. O problema é exclusivamente de descoberta de FK pelo PostgREST.

**Fix duplo (belt-and-suspenders):**

**(a) Migration 0029** — `DO $$ BEGIN IF NOT EXISTS (...referential_constraints WHERE table_name='worker_profiles' AND column_name='profile_id') THEN ALTER TABLE worker_profiles ADD CONSTRAINT worker_profiles_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE; END IF; END $$;` — seguro: a query `IF NOT EXISTS` verifica qualquer FK na coluna (independente do nome), pelo que é no-op se o FK já existir. Após aplicar, o PostgREST recalcula o schema cache e o join de dois saltos passa a funcionar.

**(b) FK hint explícito no select** — `proposal_repository.dart fetchPendingProposalsForJob` alterado de `.select('*, worker_profiles(profiles(full_name, avatar_url))')` para `.select('*, worker_profiles(profiles!worker_profiles_profile_id_fkey(full_name, avatar_url))')`. O hint diz ao PostgREST exatamente qual FK usar para o segundo salto, eliminando qualquer ambiguidade mesmo se houver múltiplos FKs de/para `worker_profiles`. `fromJson` não muda — o key path `json['worker_profiles']['profiles']['full_name']` é idêntico.

`[BUG3_DIAG] debugPrint` removido de `proposal_repository.dart`. Import `flutter/foundation.dart` removido.

Migration 0029 **APLICADA** em 2026-07-07.

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Bug 3 diagnóstico + regressão A2 em client_home_screen corrigida

**Bug 3 — Logging de diagnóstico adicionado (aguarda captura de log ao vivo):**

`debugPrint('[BUG3_DIAG] raw first proposal: ${data.first}')` adicionado em `proposal_repository.dart fetchPendingProposalsForJob`, imediatamente antes do `.map(fromJson)`. Quando Henrique abrir o ecrã com propostas, o logcat mostrará o JSON cru para confirmar se a chave `worker_profiles` está presente e com que shape exato chega da BD. Import `package:flutter/foundation.dart` adicionado ao ficheiro (necessário para `debugPrint` fora de um widget).

As linhas exatas de parsing em `JobProposal.fromJson` que estão sob suspeita:
```dart
workerName: (json['worker_profiles'] as Map<String, dynamic>?)?
    ['profiles']?['full_name'] as String?,
workerAvatarUrl: (json['worker_profiles'] as Map<String, dynamic>?)?
    ['profiles']?['avatar_url'] as String?,
```
Se o log mostrar `worker_profiles: null` → workers sem `worker_profiles` row (hipótese de data). Se mostrar `worker_profiles: {profiles: null}` → join chega mas `profiles` está null (FK mismatch). Se mostrar shape diferente → chave errada no `fromJson`.

**Regressão A2 encontrada e corrigida — `client_home_screen.dart` ainda passava `extra: job`:**

Grep exaustivo de `lib/` para `extra:` com objetos de domínio encontrou 1 call site remanescente: `client_home_screen.dart:91` passava `extra: job` (um `JobRequest` completo) no `context.push('/client/job/${job.id}')` do card de job na home do cliente. Esta rota foi migrada para ID-based routing na sessão A2 de 2026-06-29 — todos os outros call sites (`client_jobs_screen.dart`, `notification_handler.dart`) já tinham o extra removido, mas este ficou. Era este o call site que gerava o aviso GoRouter "An extra with complex data type JobRequest is provided without a codec." Corrigido: `extra: job` removido; a rota recebe apenas o ID e carrega via `jobByIdProvider` como os restantes.

Os únicos `extra:` remanescentes em toda a app são `{'initialTabIndex': 1}` em 3 casos em `notification_handler.dart` — passa um `int` primitivo, confirmado seguro (sem codec necessário para primitivos).

`flutter analyze`: 0 issues.

---

## 2026-07-06 — Bugs 1, 2, 4 corrigidos (testes 2026-07-05)

**Bug 1 — Avatar não aparecia após upload (dois sub-problemas):**

**1a — `createProfile` não escrevia `avatar_url` em `profiles`:** `worker_repository.dart createProfile()` atualizava `profiles` apenas com `full_name` e `phone`. `workerProfileProvider` lê `avatar_url` de `profiles` (via `getProfile`), pelo que o avatar carregado durante o setup era silenciosamente ignorado. Corrigido: adicionado `if (profile.avatarUrl != null) 'avatar_url': profile.avatarUrl` ao mapa de `profiles.update()` em `createProfile`, espelhando exatamente o que `updateProfile` já fazia.

**1b — Cache de NetworkImage servia imagem antiga após re-upload:** `uploadAvatar` em ambos os repositórios (`worker_repository.dart` e `client_repository.dart`) faz upsert sempre para o mesmo path `$userId.jpg`. O URL público resultante é idêntico ao anterior — Flutter reutiliza a entrada em cache e a foto nova nunca aparece. Corrigido: `uploadAvatar` retorna agora `'$url?v=${DateTime.now().millisecondsSinceEpoch}'` em ambos os repositórios. O parâmetro de query muda a cada upload, forçando o `NetworkImage` a tratar o URL como novo.

**1c — `workerProfileProvider` não invalidado após setup:** `worker_setup_screen.dart _save()` chamava `sessionStatusProvider.notifier.refresh()` mas não invalidava `workerProfileProvider`. Se o worker navegasse para o perfil imediatamente após o setup, via dados em cache sem avatar. Corrigido: `ref.invalidate(workerProfileProvider)` adicionado imediatamente após `context.go('/worker/home')` (padrão T4: navegar primeiro, invalidar depois).

---

**Bug 2 — Crash keyReservation em notificações de discovery (newJobInRadius, proposalRejected, jobReopened):**

`notification_handler.dart` usava `context.push` nos 3 casos de discovery do worker. Se o worker já estivesse a ver o ecrã de detalhe de um job quando a notificação chegava, o push duplicava a rota ativa, causando a assert `keyReservation.contains(key) is not true` (mesma classe do RT1). A decisão de usar `push` para preservar navegação para trás foi reavaliada: o custo de crash supera o benefício de UX da back-navigation a partir de uma notificação. Corrigido: `context.push` → `context.go` nos 3 casos (`newJobInRadius` linha 19, `proposalRejected` linha 55, `jobReopened` linha 83). `context.go` substitui o stack — sem possibilidade de rota duplicada.

---

**Bug 4 — Foto do cliente ausente no card de contacto do worker (dupla omissão):**

`client_repository.dart fetchClientBasicInfo()` selecionava apenas `full_name, phone` — `avatar_url` nunca era fetched. Adicionado `avatar_url` ao select e ao mapa de retorno (default `''` para null). Fallback vazio em `client_providers.dart` atualizado para incluir `'avatar_url': ''`. Na UI, `worker_my_job_detail_screen.dart` (card "Cliente") substituiu `Row(Icon + Text)` pelo widget reutilizável `UserAvatarWithName` — passa `name`, `avatarUrl` (null se string vazia), e `nameStyle` com a cor `onPrimaryContainer` do tema. Import `user_avatar_with_name.dart` adicionado.

---

**Bug 5 — Restart após conclusão de job (não é bug de código):**

Investigado e documentado como limitação conhecida: a atualização de estado em tempo real depende da stream do Supabase Realtime estar ativa. Se o utilizador tiver a app em background quando a notificação `jobMarkedDone`/`jobCompleted` chega, a stream pode estar desligada e o estado não atualiza sem restart. Código de invalidação nos dois lados confirmado correto (`_markCompleted` invalida providers do worker; `notification_providers.dart` invalida providers do cliente via `jobMarkedDone`). Push notifications via FCM resolveria este problema — ver item de alta prioridade em `improvements.md`.

**Bug 3 — Pending:** aguarda resultado de live query para confirmar workers sem `worker_profiles` row.

`flutter analyze` após todas as alterações: **0 issues**.

---

## 2026-07-04 — Auditoria de segurança Fase 10 (dados/RLS apenas; UI ignorada por redesign pendente)

3 achados confirmados, 2 corrigidos em migration 0028, 1 confirmado já correto:

**F10-S1 — policy INSERT de `job_reports` demasiado permissiva:** `"Utilizador reporta problema"` (0001_baseline.sql:442) verificava apenas `auth.uid() = reporter_id` — qualquer utilizador autenticado podia submeter um report para qualquer `job_id`. Corrigido em 0028: nova policy `"Participante pode reportar o seu job"` exige que o reporter seja o cliente do job OU o worker com proposta aceite. Nota: a policy anterior foi confirmada pelo nome exato (`"Utilizador reporta problema"`) — a policy `"Authenticated users can report jobs"` mencionada no brief era um placeholder incorreto.

**F10-S2 — `worker_rating_summary` sem `security_invoker` capturado em migration:** 0024 criou a view sem `security_invoker = true`; fix aplicado no SQL Editor após 0024 não estava em nenhuma migration — rebuild a partir de migrations revertia o fix. Capturado em 0028 com `CREATE OR REPLACE VIEW ... WITH (security_invoker = true)`. Comportamento atual não muda (ratings SELECT USING (true) é público), mas qualquer future tightening de RLS na tabela `ratings` seria silenciosamente bypassado por uma view security-definer.

**F10-S3 — `fetchRatingsWithRaterNames` audited, sem alteração necessária:** Select atual é `'*, rater:profiles!rater_id(full_name)'` — phone já não estava incluído no join. O `*` aplica-se apenas a colunas de `ratings` (stars, comment, rater_id, ratee_id, job_id, created_at). Nenhuma exposição de phone; nenhuma alteração ao código Dart.

Migration 0028 **APLICADA** em 2026-07-07.

---

## 2026-07-04 — M4 implementado: PendingSignupNotifier substitui state.extra no fluxo de registo

`state.extra` removido como portador de `fullName`/`phone` entre `SignupScreen` e `ChooseRoleScreen`. Substituído por `NotifierProvider<PendingSignupNotifier, PendingSignupState>` em `lib/features/auth/application/pending_signup_provider.dart`. Dados ficam em memória Riverpod — sobrevivem a qualquer tick de auth-state ou redirect do router, sem dependência de navigation stack.

Ficheiros alterados: `signup_screen.dart` escreve para o provider antes de `context.go('/choose-role')` (sem extra); `choose_role_screen.dart` lê via `ref.read(pendingSignupProvider)` em `_submit()` e chama `.clear()` após `createProfile` com sucesso; `app_router.dart` simplificado para `builder: (_, _) => const ChooseRoleScreen()` (sem leitura de `state.extra`). Campos `required this.fullName`/`required this.phone` removidos do construtor de `ChooseRoleScreen`. Riverpod 3.x — usado `Notifier`/`NotifierProvider` (não `StateNotifier`/`StateNotifierProvider`, removidos na v2).

---

## 2026-07-04 — P-8-7 filtro server-side em fetchScheduledWorkerProposals; P-10-2 confirmado já resolvido

**P-8-7 — filtro movido para servidor:** `fetchScheduledWorkerProposals` em `proposal_repository.dart` — adicionado `.filter('job_requests.status', 'in', '(confirmed,awaiting_confirmation)')` ao query PostgREST via embedded resource filter. Bloco `.where()` Dart eliminado. Sort por `confirmed_date` mantido client-side (PostgREST não suporta ORDER BY em campos de embedded resource). Antes: worker com N jobs concluídos transferia todos os N registos `accepted` para filtrar 1-2 no cliente. Depois: apenas registos com job `confirmed | awaiting_confirmation` chegam ao cliente.

**P-10-2 — confirmado já resolvido:** Leitura de `help_request_model.dart` confirmou que `HelpAcceptanceSummary` já tem `principalPhone: String` e `principalWorkerId: String` com defaults `''`, parseados em `fromJson`. `_AcceptedCard` em `worker_help_requests_screen.dart` já apresenta botão WhatsApp gated em `principalPhone.isNotEmpty`. Implementação completa — provavelmente introduzida em RC3 / migration 0022 (2026-06-27). Nenhum código alterado; apenas marcado resolvido em `improvements.md`.

---

## 2026-07-04 — proposalRejected invalida workerProposalForJobProvider; P-8-2 N+1 eliminado

**FIX 1 — `proposalRejected` invalidation gap:** `notification_providers.dart`, case `proposalRejected` — adicionado `ref.invalidate(workerProposalForJobProvider)` (família completa, sem chave — `workerId` não está disponível no contexto do sync provider; mesmo padrão de `proposalWithdrawn`). `relatedId = p_job_id` confirmado via migration 0001_baseline.sql. Gap identificado na auditoria de 2026-07-01 e agora fechado.

**FIX 2 (P-8-2) — N+1 eliminado em `_ProposalCard`:** `fetchPendingProposalsForJob` em `proposal_repository.dart` alterado de `.select()` para `.select('*, worker_profiles(profiles(full_name, avatar_url))')` — join de dois saltos (padrão idêntico ao T7 fix: `job_proposals.worker_id → worker_profiles.profile_id → profiles.id`; FK direta `job_proposals → profiles` não existe). `JobProposal` recebeu dois campos opcionais: `workerName: String?` e `workerAvatarUrl: String?`, parsed via `(json['worker_profiles'] as Map?)?['profiles']?['full_name/avatar_url']`. `_ProposalCard` em `client_job_detail_screen.dart` removeu `ref.watch(workerBasicInfoProvider(proposal.workerId))` e lê `proposal.workerName` / `proposal.workerAvatarUrl` diretamente — N queries por lista → 1 query. `workerBasicInfoProvider` permanece em uso na mesma classe para `_workerContactCard` (line 533); import mantido.

---

## 2026-07-01 — Parte A: UX do formulário de proposta reestruturado + Parte B: ícone de mapa

**Parte A — Formulário de proposta (`worker_job_detail_screen.dart` `_ProposalSheet`):** Campo `TextFormField` "Pessoas necessárias" substituído por `CheckboxListTile` "Preciso de ajuda". Quando desmarcada: `people_needed = 1` e `helpers_equipment_required = false` (valores por omissão, sem submenu visível). Quando marcada: revela `DropdownButton<int>` (opções 2–5, total incluindo o principal) mapeado para `people_needed` e `SwitchListTile` "Ajudantes devem trazer equipamento próprio" mapeado para `helpers_equipment_required`. Ao desmarcar: ambos os valores resetam antes de ocultar o submenu. `_peopleController` removido; `_needsHelp`, `_peopleNeeded`, `_helpersEquipmentRequired` substituem.

**Parte A — Discovery do ajudante (`worker_help_requests_screen.dart` `_HelpRequestCard`):** Quando `equipment_required = false`, o checkbox "Levo o meu equipamento" foi substituído por texto estático "Sem equipamento necessário" com ícone neutro. `broughtEquipment` passa sempre como `summary.equipmentRequired` (true quando obrigatório, false quando não). `_broughtEquipment` Map e parâmetros `broughtEquipment`/`onBroughtEquipmentChanged` removidos do widget e do estado pai.

**Parte B — Ícone de mapa nos cards do worker (`worker_home_screen.dart`):** Endereço em texto removido dos cards de discovery. Substituído por `GestureDetector` com `Icon(Icons.map_outlined)` que abre Google Maps diretamente via `launchUrl` com as coordenadas do job. `url_launcher` importado.

**Parte B — AddressMapLink no detalhe de job (`worker_job_detail_screen.dart`):** Bloco `Row(Icon + Text)` com endereço em texto simples substituído por `AddressMapLink` (já existia noutros ecrãs — padrão reutilizado). `address_map_link.dart` importado.

**Parte B — Confirmações:** `worker_my_job_detail_screen.dart` já usava `AddressMapLink`. `worker_help_requests_screen.dart` já usava `AddressMapLink` na tab "As minhas candidaturas" (linha 547). `client_job_detail_screen.dart` não mostra morada de terceiros — sem mapa no ecrã do cliente (confirmado, skip intencional).

---

## 2026-07-01 — RT3, RT5, RT9 resolvidos + widget UserAvatarWithName criado

**RT3:** `fetchWorkerBasicInfo` estendido para incluir `avatar_url` (SELECT `full_name, phone, avatar_url`). `_workerContactCard` em `client_job_detail_screen.dart` substituiu `Icon(Icons.person_outlined) + Text(name)` pelo novo widget `UserAvatarWithName`. Widget criado em `lib/core/widgets/user_avatar_with_name.dart` — `StatelessWidget` que exibe `CircleAvatar` com `NetworkImage(avatarUrl)` se URL não-vazio, ou inicial do nome caso contrário, seguido do nome em `Text` expandido.

**RT5:** `_acceptedProposalCard` adicionado a `client_job_detail_screen.dart`. No bloco `confirmed`, inserido antes de `_workerContactCard` quando `acceptedProposalAsync.asData?.value != null`. Mostra taxa/hora, horas estimadas, total estimado, pessoas. `acceptedProposalForJobProvider` já era watchado no mesmo `data` block desde sessão anterior — nenhum novo provider necessário.

**RT9:** `_RatingChip` (`ConsumerWidget`) adicionado a `worker_jobs_screen.dart`. Observa `myRatingForJobProvider(jobId)`. Quando rating existe, exibe chip `★ N/5` na `_JobCard` dos jobs com `job.status == JobStatus.completed`. `_buildCompletedSection` em `worker_my_job_detail_screen.dart` confirmado correto (gated em job.status == completed dentro de proposal.status == accepted).

**Bónus (STEP 6):** `_ProposalCard` em `client_job_detail_screen.dart` actualizado para usar `workerBasicInfoProvider` em vez de `workerNameProvider` — `CircleAvatar` com avatar ou inicial substitui `Icon(Icons.person_outlined)`. Rating star e restante layout inalterados.

---

## 2026-07-01 — Auditoria completa de notification_handler.dart (RT1, RT4, T6 resolvidos)

Auditoria de todos os 19 tipos de notificação em `notification_handler.dart`. Casos corrigidos: (1) **RT4** — `proposalAccepted` com fetch nulo agora faz `context.go('/worker/home')` + SnackBar em vez de break silencioso; mesmo padrão aplicado a `helpRequestApproved` e `helpWithdrew`. (2) **RT1** — todos os lifecycle cases convertidos de `context.push` para `context.go`, eliminando o keyReservation crash por push duplicado para rota já ativa. (3) **T6 completo** — `jobCancelled`, `rescheduleProposed/Accepted/Rejected`, `jobCompleted` agora têm split por role (cliente → `/client/job/$id`; worker → async fetch proposalId → `/worker/my-job/$pid?jobId=$id`, fallback home); `jobMarkedDone` e `jobNoResponse` navegam para `/client/job/$id` (client-only); `jobReopened` navega para `/worker/job/$id` (push). (4) `helpRejected` agora navega para candidaturas em vez de break silencioso. (5) `context.mounted` verificado após cada `await` em todos os casos. Import `job_providers.dart` removido (deixou de ser usado após mover `ref.invalidate` para `notification_providers.dart`). RT2 e RT8 confirmados presentes em `notification_providers.dart`. Gap menor identificado: `proposalRejected` em `notification_providers.dart` não invalida `workerProposalForJobProvider` (não bloqueante).

---

## 2026-07-01 — RT2, RT6, RT8 corrigidos (Grupo 1 do plano de ataque do Run 1)

`proposalReceived` em `notification_providers.dart` agora invalida `jobByIdProvider(notification.relatedId)` (RT2) — garante que o cliente no ecrã de detalhe vê a pill de estado actualizada quando chega uma nova proposta. Handlers de remarcação do worker (`_proposeReschedule`, `_acceptReschedule`, `_rejectReschedule` em `worker_my_job_detail_screen.dart`) confirmados já correctos por leitura directa — todos têm `ref.invalidate(jobByIdProvider(widget.jobId))` após `router.pop()` (RT6 já estava resolvido). `jobCompleted` em `notification_providers.dart` agora invalida `myRatingForJobProvider(notification.relatedId)` e `myRatingForJobAndRateeProvider` (família completa) para que o ecrã de avaliação reflicta o estado correcto sem restart (RT8); import `rating_providers.dart` adicionado ao ficheiro.

---

## 2026-07-01 — Run 1 do dashboard de testes: 9 achados cross-referenciados

Run 1 do dashboard de testes manuais (executado no dia anterior, cross-referenciado hoje) revelou 9 achados: 1 crash novo (RT1), 1 avatar ausente no card de contacto (RT3 — NOVO), 1 gap de UI genuíno já identificado duas vezes no mesmo dia (RT5), 3 gaps concretos em fixes já existentes mas incompletos (RT2, RT4, RT8), e 2 achados a confirmar por leitura directa de código antes de corrigir (RT6, RT9). RT7 confirma que o padrão de fix já correto (T4) funciona quando aplicado — usar como referência para os restantes. Todos registados em `improvements.md` com códigos RT1–RT9. Nenhum corrigido nesta sessão — documentação apenas.

---

## 2026-07-01 — Migration 0027 aplicada à BD viva

Migration `0027_doc_audit_fixes.sql` aplicada manualmente via Supabase SQL Editor por Henrique. Todos os 5 fixes activos: `client_has_confirmed_job_with_worker` + policy (P-FA1), `sync_worker_service_types` RPC (P-67-2), 4 índices em falta (P-FA5+M3), `help_acceptances.status DEFAULT 'pending'` (P-FA6), policy SELECT cliente `help_requests` (M5).

---

## 2026-06-30 — Auditoria de docs: 5 gaps confirmados corrigidos via migration 0027 + T6 expandido

### Contexto

Verificação manual dos itens "Crítico" e "Alta prioridade" de `improvements.md` contra a BD viva e o código actual. Henrique confirmou dois items via live query directa:
- **P-FA5:** `SELECT indexname FROM pg_indexes WHERE tablename IN ('help_requests','help_acceptances')` → **0 rows** — nenhum dos 3 índices existia.
- **P-FA6:** `SELECT column_default FROM information_schema.columns WHERE table_name='help_acceptances' AND column_name='status'` → `'accepted'::text` — default incorreto confirmado.

Os restantes 3 items (P-FA1, P-67-2, M5) confirmados por grep exaustivo de migrations 0001–0026 e inspeção do código Dart.

**Achado adicional:** item `get_jobs_in_radius overload antigo` em `improvements.md` estava marcado como "ainda por remover". Verificação de `0011_drop_obsolete_get_jobs_in_radius.sql` confirmou que já contém `DROP FUNCTION IF EXISTS get_jobs_in_radius(numeric, numeric, integer)` — item era STALE; nenhuma acção necessária.

### Migration 0027_doc_audit_fixes.sql — CRIADA, NÃO APLICADA

**IMPORTANTE: Este ficheiro foi criado mas NÃO aplicado à base de dados. Aplicar manualmente via Supabase SQL Editor.**

Cinco fixes num único ficheiro (`supabase/migrations/0027_doc_audit_fixes.sql`):

#### P-FA1 — `client_has_confirmed_job_with_worker` + policy ausentes de todas as migrations

`CREATE OR REPLACE FUNCTION client_has_confirmed_job_with_worker(p_worker_id uuid)` com os três estados correctos (`confirmed`, `awaiting_confirmation`, `completed`) + `CREATE POLICY "Cliente ve perfil de worker com job confirmado" ON worker_profiles FOR SELECT USING (client_has_confirmed_job_with_worker(profile_id))`.

Nota: `worker_profiles` PK é `profile_id` (confirmado em `0001_baseline.sql` linha 35) — a policy usa `profile_id`, não `id`.

#### P-67-2 — sync de serviços do worker agora atómico via RPC

Dart: `_syncServiceTypes` em `worker_repository.dart` substituído por chamada única `_client.rpc('sync_worker_service_types', params: {...})`. As duas chamadas PostgREST separadas (DELETE + INSERT) sem transação foram eliminadas — o intervalo de tempo em que o worker podia ficar com ZERO serviços deixa de existir.

SQL: `CREATE OR REPLACE FUNCTION sync_worker_service_types(p_worker_id uuid, p_service_type_ids uuid[]) RETURNS void LANGUAGE plpgsql SECURITY DEFINER` — DELETE + INSERT numa única transação.

#### P-FA5 + M3 — índices em falta criados

```sql
CREATE INDEX IF NOT EXISTS idx_help_requests_job_id ON help_requests (job_id);
CREATE INDEX IF NOT EXISTS idx_help_requests_proposal_id ON help_requests (proposal_id);
CREATE INDEX IF NOT EXISTS idx_help_acceptances_worker_id ON help_acceptances (worker_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications (user_id, created_at DESC);
```

`help_acceptances.worker_id` era o mais urgente: avaliado pelo RLS em TODAS as queries à tabela, não só em queries explícitas da app. M3 (índice de notificações) agrupado aqui por ser a mesma classe de fix — índice ausente confirmado por grep de todas as migrations anteriores.

#### P-FA6 — DEFAULT de `help_acceptances.status` corrigido

`ALTER TABLE help_acceptances ALTER COLUMN status SET DEFAULT 'pending';`

O DEFAULT `'accepted'` causava rejeição silenciosa de qualquer INSERT que omitisse `status` (RLS WITH CHECK `status = 'pending'` bloqueava com count=0, sem erro visível). Só rows futuras são afectadas — rows existentes não mudam.

#### M5 — policy SELECT para cliente em `help_requests` alargada

`DROP POLICY IF EXISTS "Cliente vê help requests pendentes de aprovação" ON help_requests; CREATE POLICY "Cliente vê help requests dos seus jobs" ON help_requests FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM job_requests WHERE id = help_requests.job_id AND client_id = auth.uid()))` — a policy anterior (migration 0003) só cobria `pending_approval`; a nova cobre todos os estados para jobs do próprio cliente.

### T6 — 5 tipos de notificação adicionais resolvidos em `notification_handler.dart`

Adicionada navegação precisa para 5 tipos anteriormente ausentes do switch de `NotificationHandler`:

| Tipo | `relatedId` | Acção |
|---|---|---|
| `newJobInRadius` | `job_id` | `context.push('/worker/job/${relatedId}')` |
| `proposalReceived` / `proposalWithdrawn` | `job_id` | `context.push('/client/job/${relatedId}')` |
| `proposalRejected` | `job_id` | `context.push('/worker/job/${relatedId}')` |
| `proposalAccepted` | `job_id` | fetch `fetchAcceptedProposalForJob(jobId)` → `context.push('/worker/my-job/${proposal.id}?jobId=${relatedId}')` |

`proposalAccepted` requer fetch assíncrono porque `relatedId = job_id` mas a rota precisa de `proposalId` — reutilizado o padrão async já existente para `helpRequestApproved`/`helpWithdrew`.

`helpAccepted`/`helpJobCancelled`: mantidos com `extra: {'initialTabIndex': 1}` — avaliado que passar um `int` primitivo em `extra` para um ecrã de lista é seguro (sem objeto de domínio stale, sem crash risk; pior caso é degradação de UX para tab errada).

`helpRequestReopened`: mantido com `context.push('/worker/help-requests')` (descoberta) — destino correcto para o worker re-candidatar-se ao slot reaberto.

**T6 ainda aberto:** `jobCancelled`, `jobReopened`, `rescheduleProposed`, `rescheduleAccepted`, `rescheduleRejected`, `jobMarkedDone`, `jobCompleted` — navegam para lista genérica. Fix: push para `/client/job/$relatedId` ou `/worker/my-job/$proposalId?jobId=$relatedId` conforme role. Worker paths requerem `fetchAcceptedProposalForJob(relatedId)` para obter `proposalId`.

**`flutter analyze`:** limpo após todas as alterações (0 issues).

---

## 2026-06-29 — T4 corrigido: ordering race entre ref.invalidate() e router.go() em _markCompleted()

Causa raiz: `ref.invalidate()` chamado **antes** de `router.go()` no caminho de sucesso de `_markCompleted()` em `worker_my_job_detail_screen.dart`. As três invalidações (`scheduledWorkerProposalsProvider`, `completedWorkerProposalsProvider`, `jobsInRadiusProvider`) disparavam notificações síncronas ao `WidgetRef` do ecrã, registando-o como dependente ativo a reconstruir. De seguida, `dialogNavigator.pop()` e `router.go('/worker/home')` iniciavam a desmontagem do ecrã — mas o `WidgetRef` ainda estava na lista `_dependents` dos elementos de provider que tinham acabado de notificá-lo. O `ProviderElement.dispose()` do Riverpod asserta `_dependents.isEmpty`, falhando com `'_dependents.isEmpty': is not true`. Agravado pelo bloco `finally` que chamava `setState()` com `mounted == true` após a navegação já ter sido iniciada, agendando mais uma reconstrução.

**Fix aplicado:** reordenação no caminho de sucesso para `pop → go → snackBar → invalidate`. A invalidação acontece depois do ecrã já ter começado a sair da árvore — o `WidgetRef` está a ser limpo, não a receber notificações novas. Adicionado `navigatedAway = true` antes de `router.go()`; bloco `finally` alterado para `if (!navigatedAway && mounted) setState(...)`, eliminando o `setState` supérfluo no caminho de sucesso.

**Lição geral:** nunca invalidar providers **antes** de uma navegação que vai desmontar o ecrã atual. A invalidação dispara `notifyListeners()` síncronos — se o `WidgetRef` do ecrã for dependente do provider, é marcado como dirty. Se a desmontagem começar antes do rebuild ser processado, o Riverpod encontra a inconsistência na limpeza de dependentes. A regra de ouro: `navigate → then invalidate`, não `invalidate → then navigate`.

**Candidatos adicionais da mesma classe de bug identificados em `client_job_detail_screen.dart` — corrigidos preventivamente na sessão seguinte:** linhas 80-84 (cancel open job), 130-141 (cancel confirmed job), 374-378 (accept proposal). Ver entrada seguinte.

---

## 2026-06-29 — Bug do nome/avatar do candidato no lobby corrigido

Causa: 3.º waterfall (`profileSummaryProvider` por candidato) mascarava erros silenciosamente via `?? {}` e mostrava `'—'` enquanto carregava. Fix: join direto de `profiles` na query de `fetchCandidatesForHelpRequest`, eliminando o waterfall e a possibilidade de erro mascarado.

**Detalhe técnico do join:** `help_acceptances.worker_id` aponta para `worker_profiles(profile_id)` e NÃO diretamente para `profiles(id)`. O join correto é de dois saltos via PostgREST embedded resources: `.select('*, worker_profiles(profiles(full_name, avatar_url))')`. A FK sugerida originalmente `profiles!help_acceptances_worker_id_fkey` seria inválida (não existe essa FK direta). O JSON aninhado é desserializado em `HelpAcceptance.fromJson` via `json['worker_profiles']?['profiles']`. `HelpAcceptance` passou a ter os campos `fullName` e `avatarUrl` (ambos `String?`). O bloco `profileSummaries` e as funções `nameOf`/`avatarOf` do `worker_help_requests_lobby_screen.dart` foram removidos; os cards passam a ler `c.fullName ?? 'Sem nome'` e `c.avatarUrl` diretamente.

---

## 2026-06-29 — T2 corrigido: overflow no card de contacto do worker

T2 corrigido. Nome do worker no card de contacto envolvido em `Expanded` + `TextOverflow.ellipsis`, eliminando o overflow de 52px confirmado em dispositivo real.

**Ficheiros alterados:**
- `client_job_detail_screen.dart` — `_workerContactCard()`: Row do nome e Row da data/hora do agendamento, ambos sem `Expanded`. Dois textos dinâmicos (nome do worker, output de `_formatConfirmedSchedule()`) agora envolvidos em `Expanded(child: Text(..., overflow: TextOverflow.ellipsis, maxLines: 1))`.
- `worker_my_job_detail_screen.dart` — card de contacto do cliente (linhas ~640-652): Row do nome do cliente com `Text(info['full_name'])` sem `Expanded` — mesma classe de bug, corrigido preventivamente com o mesmo padrão.

**Outros Rows inspecionados e confirmados seguros:** reschedule banner (ambos os ficheiros), awaiting-completion banner, status banners (rejected, superseded, pending), rating card — todos já tinham `Expanded`. `Text('Trabalho avaliado')` (linha ~994, `client_job_detail_screen.dart`) é string estática de 16 chars, sem risco de overflow.

---

## 2026-06-29 — Fix preventivo do padrão T4 em 3 locais de client_job_detail_screen.dart

Aplicado o mesmo padrão de reordenação do T4 a 3 locais de `client_job_detail_screen.dart` que tinham a mesma classe de risco de `_dependents.isEmpty`, antes de crashar em produção.

**Locais corrigidos:**
- `_cancelJob` (path `job.status == open`): `_cancelOpenJob` block — `cancelJob()` → `navigatedAway = true` → `router.go('/client/jobs')` → snackBar → `invalidate` ×2. Guard `!navigatedAway && mounted` no `finally`.
- `_cancelJob` (path `job.status == confirmed`): mesmo padrão — `newJobId` capturado antes, navega primeiro, snackbar condicional (newJobId != null), depois invalidate. Guard `!navigatedAway && mounted` no `finally`.
- `_acceptProposal`: sem `finally` — apenas reordenação: `acceptProposal()` → `router.go('/client/jobs')` → snackBar → `invalidate` ×2. Sem guard necessário (catch block só reseta estado de erro, não existe `finally`).

**Por que só estes 3:** as funções de reschedule (`_proposeReschedule`, `_acceptReschedule`, `_rejectReschedule`) invalidam `jobByIdProvider(widget.jobId)` (watched pelo ecrã) mas **não navegam para fora** — o ecrã permanece na árvore e o rebuild da invalidação é processado normalmente. `_confirmJobCompletion` invalida `clientJobsProvider` (não watched pelo ecrã) antes de navegar — sem risco. Confirmado por grep exaustivo do ficheiro.

---

## 2026-06-29 — 3 bugs reais na área de ajudantes corrigidos via migration 0026

Investigação completa de 3 bugs confirmados em `help_requests`. Causa raiz identificada em todos os 3; migration `0026_helper_lobby_fixes.sql` criada — **NÃO aplicada, aplicar manualmente via Supabase SQL Editor.**

**(1+2) Policy SELECT em falta para o worker principal em `help_requests` (gap C3.2)** — causava dois comportamentos distintos:
- `createHelpRequest()` lançava exceção em Dart: o INSERT tem WITH CHECK correto e passa (proposta accepted verificada), mas o `.select('id').single()` encadeado usa `RETURNING id` internamente (PostgREST `Prefer: return=representation`). O `RETURNING` está sujeito a RLS SELECT — sem policy SELECT para o principal, devolve 0 rows e `.single()` lança. A row **fica na BD**; Dart vê exceção. Fix: `CREATE POLICY "Worker principal vê os seus help requests" ON help_requests FOR SELECT USING (EXISTS (SELECT 1 FROM job_proposals WHERE id = proposal_id AND worker_id = auth.uid()))`.
- Lobby vazio (`WorkerHelpRequestsLobbyScreen`): `fetchHelpRequestsForJob()` é um SELECT PostgREST direto em `help_requests`; sem policy SELECT, o principal obtém sempre 0 rows mesmo havendo rows na BD. Fix: mesma policy.

**(3) Exclusão `NOT EXISTS` em falta em `get_help_requests_in_radius`** — depois de se candidatar a um help_request, o worker continuava a vê-lo na lista de descoberta porque a função não exclui help_requests onde o caller já tem uma `help_acceptance`. Item catalogado como A2/cluster η nas melhorias da Fase 9 (improvements.md) desde a auditoria original — nunca implementado em nenhuma migration subsequente (0008–0025), não era uma regressão. Fix: `AND NOT EXISTS (SELECT 1 FROM help_acceptances ha WHERE ha.help_request_id = hr.id AND ha.worker_id = auth.uid())` adicionado ao WHERE da função.

**Lição geral registada:** qualquer `.insert().select().single()` está sujeito a RLS SELECT no `RETURNING`, não só a RLS INSERT. Verificar SEMPRE que existe policy SELECT correspondente antes de assumir que um INSERT funcional implica leitura funcional.

---

## 2026-06-29 — A2 Prompt B: /worker/my-job/:id e /worker/job/:id/help-requests convertidos para ID-based routing

Route `/worker/my-job/:id` usa query param `?jobId=` para carregamento paralelo (decisão 2026-06-29, evita cascade sequencial proposta→job). `WorkerMyJobDetailScreen` reescrito com `required this.proposalId, required this.jobId` (ambos String): ambos os providers observados em paralelo no topo de `build()`, `liveStatus`/`liveJobStatus` simplificados — providers são a única fonte, fallback para widget eliminado. Route `/worker/job/:id/help-requests` simplificada para só `jobId`; `WorkerHelpRequestsLobbyScreen` usa `acceptedProposalForJobProvider(widget.jobId)` para obter proposta, `_suggestedRate()` aceita `JobProposal?` nulo, degrada para taxa 0 com validação existente `> 0` no sheet. `notification_handler.dart` simplificado nos dois casos de help_request (`helpRequestApproved`, `helpWithdrew`): pre-fetch manual de job+proposal removido — o fetch do `help_request` permanece apenas para resolver `job_id` a partir do `help_request_id` (confirmed: `related_id` IS `help_request_id`). `flutter analyze` limpo. Completa A2 — fecha P6 (todas as 4 rotas convertidas), resolve T1/T3 nestes 2 ecrãs finais, desbloqueia T6.

## 2026-06-29 — A2 Prompt A: /client/job/:id e /worker/job/:id convertidos de state.extra para ID-based routing

`state.extra! as JobRequest` removido das duas rotas — elimina o crash T3 (nullable extra em deep-link/notification) e o problema T1 (snapshot estático diverge do provider quando o job muda). Ambas as telas passam a receber `jobId: String` e carregam dados via `jobByIdProvider(jobId)` que já existia. Call sites (`client_jobs_screen.dart`, `worker_home_screen.dart`) simplificados — `extra: job` removido. `_job.copyWith()` optimistic updates substituídos por `ref.invalidate(jobByIdProvider(...))`. `/worker/my-job/:id` e `/worker/job/:id/help-requests` ficam para Prompt B (dependência de cascade loading com proposal).

## 2026-06-29 — T5: cancelamento de job confirmado pelo cliente agora opt-in (migration 0025)

**Problema confirmado:** `cancel_job` RPC aplicava reabertura automática ao path do cliente (quando `reopen_count_client < 1`) sem pedir consentimento. Comportamento correto apenas para o worker — quando o worker cancela, faz sentido encontrar um substituto; quando o cliente cancela, não.

**Inspeção direta do SQL (0013) revelou:** o `array_append` de `excluded_worker_ids` já estava dentro de `IF v_is_worker THEN` — a exclusão do worker nunca se aplicava ao path do cliente. O único problema real era a reabertura sem consentimento.

**Decisão de produto (2026-06-29):** cancelamento de job confirmado pelo cliente mostra dois diálogos sequenciais:
1. `CancelJobDialog` — picker de razão (existente, inalterado)
2. Novo dialog — "Voltar a publicar? Queres voltar a publicar este pedido para encontrar outro prestador?" (Sim/Não)

A reabertura só acontece se o cliente carregar em Sim E `reopen_count_client < 1`. Sem exclusão de workers no path do cliente — a exclusão é uma medida de responsabilização do worker, não se aplica aqui.

**Worker path completamente inalterado:** auto-reabre sempre (dentro do limite de 2), exclui sempre o worker que cancelou, notifica o cliente com `job_reopened`.

**Ficheiros alterados:**
- `supabase/migrations/0025_cancel_job_client_reopen_choice.sql` — DROP overload antigo + CREATE com `p_client_wants_reopen boolean DEFAULT NULL`. **NÃO aplicado — aplicar manualmente via Supabase SQL Editor.**
- `lib/features/jobs/data/job_repository.dart` — `cancelJob()` aceita `bool? clientWantsReopen`, só passa ao RPC quando não null.
- `lib/features/jobs/presentation/client_job_detail_screen.dart` — segundo dialog após CancelJobDialog; passa `clientWantsReopen` ao repository.

---

## 2026-06-29 — Sessão de testes manuais extensa: 6 bugs reais encontrados (T1-T6)

Henrique testou a app em dispositivo físico. 6 findings confirmados por observação direta (screenshots 1-6). Documentados em `improvements.md` — secção "Sessão de testes manuais — 2026-06-29" com códigos T1-T6.

**Resumo dos findings:**
- **T1** — Desync de estado de propostas: home mostra "1 proposta", detalhe do mesmo job mostra "À espera de proposta". Resolvido por force-close; confirma divergência entre snapshot stale em `state.extra` e estado real da BD.
- **T2** — Overflow de renderização no card de contacto do worker (`client_job_detail_screen.dart`, método `_workerContactCard`): "OVERFLOWED BY 52 PIXELS" na borda direita.
- **T3** — Red screen: `Null check operator used on a null value` durante navegação na área de lista de jobs. Alta correlação com P6 (`state.extra!` sem fallback em 4 rotas).
- **T4** — Red screen: `'_dependents.isEmpty': is not true` — assertion Flutter de ChangeNotifier/InheritedWidget, reproduzido duas vezes no fluxo de "Confirmar conclusão?" em `worker_my_job_detail_screen.dart`. Bug mais crítico da sessão por ser hard crash consistentemente reproduzível.
- **T5** — Lógica de cancelamento invertida: quando o **cliente** cancela, o RPC `cancel_job` recria o job e exclui o worker — comportamento desenhado para quando é o **worker** que cancela. O branch de reopen+exclusão não distingue o caller.
- **T6** — Gap de routing de notificações elevado a prioridade alta. Henrique confirmou explicitamente: *"a notificação deve levar o utilizador ao sítio exato a que se refere, não a uma lista genérica."* T1 e T3 são provavelmente sintomas diretos desta lacuna. P6 e P-8-9 re-priorizados de gap diferido para Tier 0/1 em `improvements.md`.

**Nenhum ficheiro `.dart` ou `.sql` foi alterado nesta sessão — só documentação.**

---

## 2026-06-28 — Substituído loadingExempt por fix estrutural no redirect()

`loadingExempt` (allowlist de rotas imunes ao redirect `/loading`) eliminado de `app_router.dart`. Substituído por `return null` incondicional no bloco `if (sessionAsync.isLoading)`.

**Motivo:** a allowlist era uma correção sintomática — crescia sintoma a sintoma (`/worker/setup` → depois três rotas adicionais) sem atacar a causa raiz. A causa raiz: `redirect()` nunca devia redirecionar para `/loading` quando o utilizador já está numa rota estabelecida. Um tick transitório de `isLoading` (ex: refresh de token a cada 60 min) não representa um estado desconhecido — representa uma sessão já resolvida a renovar o seu token. Redirecionar para `/loading` neste momento destrói o widget tree corrente mid-flight (ImagePicker a aguardar, upload em curso, etc.) e descarta trabalho silenciosamente.

**Comportamento correto com `return null`:**
- Arranque a frio (`loc == '/loading'`, `isLoading == true`): fica no spinner — correto.
- Tick mid-session em qualquer rota autenticada: fica onde está — correto.
- `/choose-role` com `extra` após signUp: fica onde está, preserva `fullName`/`phone` — correto.

**Backcompatibility com fixes anteriores:**
- P-67-1: coberto (caso geral inclui o caso específico).
- `/choose-role` extra loss: coberto (return null ≡ allowlist para esta rota).
- `role == null` skip, cross-role guard, worker profile complete: só são alcançados após `!isLoading` — inalterados.
- `loadingExempt` era uma `const List<String>` file-local sem outros usos — removida sem rastos.

**Hipótese:** resolve também o bug de criação de job com foto (mesma causa raiz — tick de token-refresh a meio do submit, entre `createJob` e `uploadJobPhoto`, destrói `_CreateJobScreenState` enquanto a sequência de upload está a aguardar). Diagnostic logging em `job_repository.dart`/`create_job_screen.dart` **mantido propositadamente** até confirmação por teste real — remover só depois.

---

## 2026-06-28 — loadingExempt expandido: P-67-1 era instância de classe de bug mais ampla

Confirmado via bug real reportado por Henrique (logcat + reprodução): qualquer rota com `ImagePicker` (ou outro `await` sobre interação OS assíncrona longa) está vulnerável ao mesmo redirect `/loading` → home que destrói silenciosamente a foto em curso. O guard `if (!mounted) return;` é defensivo mas o dano já está feito antes de disparar — o `State` foi descartado pelo router antes do picker retornar.

A fix original de P-67-1 (2026-06-26) adicionou apenas `/worker/setup` a `loadingExempt`. A investigação de 2026-06-28 confirmou que mais três rotas com `ImagePicker` estavam desprotegidas:

| Rota | Interação OS | Resultado sem fix |
|---|---|---|
| `/worker/profile` | `ImagePicker` + `Geolocator.requestPermission` / `getCurrentPosition` | Avatar não muda; picker retorna com `!mounted` |
| `/client/profile` | `ImagePicker` | Avatar não muda; picker retorna com `!mounted` |
| `/client/create-job` | `ImagePicker` + `Geolocator.requestPermission` / `getCurrentPosition` | Foto descartada; picker retorna com `!mounted` |

Todas três adicionadas a `loadingExempt` em `app_router.dart` (mesmo ficheiro, mesma lista, mesma fix class que P-67-1).

**Outras interações OS encontradas — não adicionadas:**
- `launchUrl(LaunchMode.externalApplication)` em `worker_my_job_detail_screen.dart`, `client_job_detail_screen.dart`, `worker_help_requests_screen.dart`, `address_map_link.dart` (widget reutilizável): abre WhatsApp/Maps. O `await` retorna imediatamente (basta iniciar o intent), não aguarda o utilizador regressar. Quando regressa, o tick de auth pode disparar, causando navegação para home — incómodo mas sem perda de dados. Não adicionado a `loadingExempt` por agora (diferente mecanismo, sem in-flight async ao regressar).
- `showDatePicker` / `showTimePicker`: dialogs Flutter in-app, não atividades Android. Não backgroundam o engine, não disparam tick de auth. Seguros.
- `Geolocator.distanceBetween()`: síncrono, sem interação OS. Seguro.

**Lição:** ao corrigir este tipo de bug no futuro, verificar TODAS as rotas com interações OS assíncronas de uma vez, não rota a rota.

---

## 2026-06-28 — Desbloqueado fluxo `pending_approval` (inventário backend-sem-UI)

Dois pontos de entrada de UI adicionados para o fluxo de expansão de equipa pós-confirmação, identificado no inventário de 2026-06-28 como "backend completo, zero UI".

### Lado do principal (`worker_my_job_detail_screen.dart`)

Botão **"Adicionar ajudante"** (`OutlinedButton.icon`, ícone `group_add_outlined`) dentro do bloco `liveJobStatus == JobStatus.confirmed`. Toca abre um `showModalBottomSheet` com `StatefulBuilder`:
- Stepper de quantidade (mín. 1) — `slotsNeeded`
- `CheckboxListTile` "Exigir equipamento próprio" — `equipmentRequired`
- Botão "Enviar pedido" chama `createHelpRequest(createdPostConfirmation: true)` → cria `help_request` com status `pending_approval`
- Sucesso: SnackBar "Pedido de ajuda enviado para aprovação do cliente." + invalida `helpRequestsForJobProvider`
- Removido o card placeholder "A funcionalidade de equipa estará disponível em breve." (já não necessário)

### Lado do cliente (`client_job_detail_screen.dart`)

Card **`_PendingHelpRequestCard`** (widget privado, cor `secondaryContainer`) injetado na secção `confirmed` logo após o `_workerContactCard`. Aparece para cada `help_request` com `status == pending_approval` (RLS já filtra — clientes só veem `pending_approval`):
- Ícone + texto "O prestador pediu ajuda extra para este trabalho"
- Linha de detalhe: nº de ajudantes + indicador de equipamento
- Botão "Aprovar equipa" chama `approveHelpRequest(helpRequestId)` → muda para `open`, notifica principal
- Sucesso: SnackBar "Equipa aprovada! O prestador pode agora procurar ajudantes." + invalida `helpRequestsForJobProvider`
- Se não houver `pending_approval` para o job, nada é renderizado (sem clutter de estado vazio)

### Notificação `helpRequestApproved` — sem alteração necessária

`notification_handler.dart` já encaminha `helpRequestApproved` para o lobby do principal com job + proposal objects resolvidos (`/worker/job/{jobId}/help-requests`). O fluxo de ponta a ponta está completo sem alteração no handler.

---

## 2026-06-27 — RCB1 + RCB2 + RCB3 (migration 0023 + 1-line Dart fix)

### RCB1 — `withdraw_help_acceptance`: guarda de job-status adicionada

A função não validava o estado do job pai — um ajudante podia "desistir" de um job
já `completed` ou `cancelled`, o que enviava notificações `help_request_reopened`
para uma vaga que já não existia.

**Fix (migration 0023):** adicionado `v_job_status text` ao DECLARE e, depois das
validações de propriedade e status da candidatura, um SELECT que lê
`job_requests.status` via `help_requests.job_id`. Se o job não estiver em
`'confirmed'` ou `'awaiting_confirmation'`, a função lança exceção antes de qualquer
UPDATE ou notificação.

### RCB2 — `cancel_job`: ajudantes aceites passam para `'cancelled'`

A cascata de `cancel_job` (desde migration 0007) rejeitava apenas candidaturas
`pending`, deixando as `accepted` no estado `'accepted'` indefinidamente após o
job cancelar.

**Decisão RC1 (Henrique):** reutilizar `'cancelled'` existente — *"foi só cancelado
é info suficiente"*. Nenhum novo status necessário.

**Fix (migration 0023):** um segundo `UPDATE help_acceptances SET status = 'cancelled'
WHERE status = 'accepted'` adicionado **depois** do INSERT de notificações
`help_job_cancelled` (que faz SELECT WHERE ha.status = 'accepted'). A ordem é
intencional: a notificação precisa de encontrar os helpers ainda em `'accepted'`
antes de os mover.

### RCB3 — Texto de `job_reports` corrigido

`client_job_detail_screen.dart:266` — substituído:
> "Descreve o que aconteceu. A nossa equipa vai rever o caso."

por:
> "Descreve o que aconteceu. O teu relato fica registado para referência futura."

`job_reports` é write-only (sem trigger, sem webhook, sem notificação). A promessa
de revisão era falsa e poderia criar expectativas erradas nos utilizadores.

---

## 2026-06-27 — RC3 fix: ajudantes passam a ver logística do job (migration 0022)

### Contexto

Revisão conceptual 2026-06-27 (RC3 em `improvements.md`) identificou que um ajudante
aceite não via dentro da app: data/hora confirmada, endereço do trabalho, nem contacto
do prestador principal. Tinha de obter essa informação fora da app.

### Extensão de `get_my_help_acceptances` (migration 0022)

Mesmo padrão DROP + CREATE de migration 0021 (mudança de shape de RETURNS TABLE).
Novos campos adicionados ao SELECT existente — o JOIN com `profiles p` já existia
(para `principal_name`), bastou acrescentar `p.phone` e os campos de `job_requests`:

| Coluna nova | Fonte | Notas |
|---|---|---|
| `confirmed_date` | `jr.confirmed_date` | nullable — null até job confirmado |
| `confirmed_time` | `jr.confirmed_time` | nullable — "HH:MM:SS" do PostgreSQL |
| `address_text` | `jr.address_text` | string vazia se não preenchida |
| `location_lat` | `jr.location_lat` | numeric |
| `location_lng` | `jr.location_lng` | numeric |
| `principal_phone` | `p.phone` | nullable — string vazia se null |

`HelpAcceptanceSummary` (Dart) extendido com 6 campos retrocompatíveis (defaults
seguros: `null` para datas, `''` para strings, `0.0` para coords).

### Widget reutilizável: `AddressMapLink`

`lib/core/widgets/address_map_link.dart` — `StatelessWidget` que:
- Recebe `address` (String), `lat` (double), `lng` (double)
- Renderiza uma linha tappable (ícone de mapa + texto sublinhado + seta de abertura)
- Abre `https://www.google.com/maps/search/?api=1&query=lat,lng` via `url_launcher`
  (`LaunchMode.externalApplication` — mesmo modo usado para WhatsApp)
- Padding idêntico ao `_infoRow` existente (6px vertical) para manter consistência visual

Aplicado em dois locais:
- `worker_help_requests_screen.dart` — `_AcceptedCard`: ajudante vê data agendada,
  link de mapa e botão WhatsApp para o principal (todos condicionais: só renderiza se
  o campo não for null/vazio)
- `worker_my_job_detail_screen.dart` — prestador principal: endereço do job passa de
  `_infoRow` estático para `AddressMapLink` tappable

### Cliente explicitamente excluído

`AddressMapLink` não é adicionado a nenhum ecrã de cliente. O cliente criou o job e
conhece o endereço — não precisa de direções para o seu próprio local.

---

## 2026-06-26 — Fase 11 (Avaliações): design e implementação

### Quatro relações de avaliação

| Quem avalia | Quem é avaliado | RPC | Notas |
|---|---|---|---|
| Cliente | Prestador principal | `submit_client_rating` | Nota propaga-se também a cada ajudante; comentário fica só no registo do principal |
| Cliente | Cada ajudante aceite | `submit_client_rating` (propagação automática) | Sem comentário; idempotente via ON CONFLICT DO NOTHING |
| Prestador principal | Cliente | `submit_principal_rating` | `p_ratee_id` = `client_id` |
| Prestador principal | Cada ajudante | `submit_principal_rating` | `p_ratee_id` = `worker_id` do ajudante |
| Ajudante | Prestador principal | `submit_helper_rating` | Principal auto-resolvido a partir de `accepted_proposal_id` |

### Decisão UX: Option A — inline, sem popup, sem novo tipo de notificação

Rejeitadas: notificação `rating_reminder` (custo de infra + noise) e popup automático (padrão intrusivo). A UI de avaliação é um card persistente no bloco "completed" de cada ecrã. O utilizador vê o prompt sempre que abre o detalhe de um trabalho concluído até avaliar.

### Constraint nova: `check_rater_not_ratee`

`ALTER TABLE ratings ADD CONSTRAINT check_rater_not_ratee CHECK (rater_id <> ratee_id)` — adicionado em migration 0021 para impedir auto-avaliação que os RPCs SECURITY DEFINER já proibiam por lógica mas não por constraint.

### `get_my_help_acceptances` atualizado (migration 0021)

Adicionadas colunas `job_id` e `principal_worker_id` ao resultado do RPC. Necessário para que `_AcceptedCard` consiga chamar `submit_helper_rating(p_job_id)` sem round-trip extra. `HelpAcceptanceSummary` tratado como retrocompatível: novos campos têm default `''` quando o RPC antigo não os devolve.

### Novo RPC `get_accepted_helpers_for_job(p_job_id)`

Usado pelo ecrã do prestador principal para listar ajudantes aceites com nome, para mostrar um card de avaliação individual por ajudante. Só retorna resultados se `jp.worker_id = auth.uid()` (caller é o principal).

### Provider para multi-ratee: `myRatingForJobAndRateeProvider((String, String))`

Chave é record Dart 3 `(jobId, rateeId)`. Necessário porque o principal tem múltiplos ratees por job (cliente + N ajudantes), cada um com estado de avaliação independente. Os rating cards do principal são `ConsumerStatefulWidget` privados que fazem o seu próprio watch.

---

## 2026-06-26 — Sessão 7 (quick wins): friendlyError, foto compressão, maybeSingle, _mapError

### Grupo 1 — friendlyError em 4 ecrãs (P-67-3, P-67-4, P-8-6)

`client_profile_screen.dart:97` — SnackBar de erro mostrava exceção em bruto; substituído por `friendlyError(e)`.
`worker_setup_screen.dart:384`, `worker_profile_screen.dart:452`, `create_job_screen.dart:281` — mesmo fix no widget `error:` de `serviceTypesAsync.when`.

### Grupo 2 — Compressão de fotos (P-8-3)

`job_repository.dart:58` — `minWidth`/`minHeight` 1280 → 800, `quality` 72 → 60. Alinhado com decisão de 2026-06-02 (limite 50MB do Free Plan).

### Grupo 3 — Auth UX pré-lançamento (P-67-5, P-67-6)

`worker_setup_screen.dart:178` — `.single()` → `.maybeSingle()` + null check com mensagem acionável "Perfil de utilizador não encontrado. Tenta fazer login novamente." (evita PGRST116 opaco em signup parcialmente falhado).
`auth_controller.dart:_mapError` — adicionados handlers para `email_not_confirmed` e `rate_limit`/`over_request_rate_limit` antes do fallback genérico. Necessário antes de reativar verificação de email para o launch.

---

## 2026-06-26 — P-8-1 + P-10-3 corrigidos (migration 0020, não aplicada)

Confirmado via live query directo por Henrique: `auto_confirm_completed_jobs` existe e está
agendado de 3h em 3h, mas só notificava o worker. `auto_expire_jobs` não existia.

**Migration 0020** criada localmente (`0020_no_response_cron_and_client_notify.sql`):
- `auto_expire_jobs()` — novo função SECURITY DEFINER com `FOR UPDATE SKIP LOCKED`,
  transição `open → no_response` quando `expires_at < now()` e `proposal_count = 0`,
  notificação `job_no_response` ao cliente. Cron job `'auto-expire-jobs'` com schedule `0 */3 * * *`.
- `auto_confirm_completed_jobs()` — recreada com second INSERT para `v_job.client_id`
  com tipo `job_completed` e body distinto ("sem resposta" vs "sem confirmação" para o worker).

**Dart:**
- `notification_handler.dart` — `jobNoResponse`: invalida `clientJobsProvider`, navega `/client/jobs`.
- `notification_providers.dart` — `jobNoResponse`: invalida `clientJobsProvider`.
- `notification_providers.dart` — `jobCompleted`: adicionado `clientJobsProvider` (necessário
  pois o cliente agora recebe `job_completed` via cron; o double-invalidate para confirmação
  manual é inócuo).

**NÃO aplicada à BD viva.** Aplicar via SQL Editor. Verificar após aplicar:
```sql
SELECT jobname, schedule, active FROM cron.job
WHERE jobname IN ('auto-expire-jobs', 'auto-confirm-completed-jobs');
```

---

## 2026-06-26 — Sincronização total via schema snapshot direto da BD viva

### Método
Query SQL única (UNION ALL 7 secções) executada directamente no SQL Editor do Supabase e gravada em `schema_snapshot_2026-06-26.csv`. Resultado: 1 339 linhas cobrindo tabelas, constraints, índices, funções (corpos completos), políticas RLS, triggers, storage buckets e cron jobs. Ficheiro apagado após sync (era artefacto temporário).

### Achado crítico — migrations 0011–0014 confirmadas todas aplicadas

Anteriormente os docs diziam que 0011–0014 estavam apenas escritas localmente. A BD viva prova o contrário:

| Migration | Evidência no snapshot |
|---|---|
| 0011 | `get_jobs_in_radius` só existe na versão de 4 parâmetros; overload antigo de 3 parâmetros ausente |
| 0012 | políticas de `job_proposals` sem duplicados; política SELECT "Worker candidato vê help requests onde se candidatou" presente |
| 0013 | corpo de `cancel_job` contém a regra das 24h (`IF v_job.status = 'confirmed' AND v_job.confirmed_date IS NOT NULL AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN RAISE EXCEPTION '...'`) |
| 0014 | função `auto_confirm_completed_jobs` presente; registo `auto-confirm-completed-jobs` activo em `cron.job` com schedule `0 */3 * * *` |

Todos os docs actualizados para reflectir estado real: `database_schema.md`, `implementation_plan.md`.

### Overloads — nenhum encontrado

23 funções no schema público, todas com exactamente uma versão. Não há `⚠ OVERLOAD` no snapshot. Histórico de overloads limpo.

### Correcção de correcção — size_estimate CHECK

A entrada de 2026-06-25 neste log registou: "migration 0001 inclui CHECK (size_estimate IN ('small', 'medium', 'large')). Corrigido." Essa correcção estava **errada**: o snapshot directo da BD mostra claramente que `job_requests` não tem nenhuma constraint CHECK sobre `size_estimate`. A validação é exclusivamente do lado do Dart via enum `SizeEstimate`. `database_schema.md` corrigido novamente para dizer "sem CHECK na BD viva".

### P-8-4 (auth bypass em reschedule RPCs) — estado definitivo

| Função | Estado |
|---|---|
| `propose_reschedule` | **Corrigido na BD viva** — corpo tem verificação completa `v_is_client` / `v_is_worker` / `not (v_is_client or v_is_worker) → RAISE`. `p_new_time` é `time without time zone` (não `text` como em 0001_baseline.sql). Ambas as alterações foram feitas interactivamente na BD, sem migration registada. |
| `accept_reschedule` | **Corrigido na BD viva** — mesmo padrão de verificação de autorização. |
| `reject_reschedule` | **Ainda vulnerável** — só verifica `reschedule_proposed_by = auth.uid()` (quem propôs não pode rejeitar). Não verifica se o caller é o cliente ou o worker do job. Qualquer utilizador autenticado que conheça o `job_id` pode rejeitar uma remarcação pendente. Flagged em `database_schema.md` para triage. |

### P-FA4 (job_proposals UPDATE sem WITH CHECK) — ainda aberto

A política `[UPDATE] Worker atualiza as suas propostas` tem `check=[ — ]` (sem WITH CHECK). Confirmado no snapshot. Não foi corrigido. Flagged em `database_schema.md`.

### P-10-1 — falso alarme confirmado definitivamente

`client_has_confirmed_job_with_worker` corpo live:
```sql
select exists (
  select 1 from public.job_requests jr
  join public.job_proposals jp on jp.id = jr.accepted_proposal_id
  where jr.client_id = auth.uid()
  and jp.worker_id = client_has_confirmed_job_with_worker.worker_id
  and jr.status in ('confirmed', 'awaiting_confirmation', 'completed')
);
```
Inclui os três estados. O card de contacto do worker funciona correctamente em todos eles. P-10-1 é falso alarme confirmado — fechar no triage.

### Outros achados documentados

- `profiles.phone` é `nullable` na BD viva (não estava documentado) — corrigido em `database_schema.md`.
- `worker_profiles.base_lat` / `base_lng` são NOT NULL — adicionado à doc.
- `confirmed_flexible` não tem default de coluna (só COALESCE na RPC) — corrigido.
- `worker-photos` storage bucket: **zero políticas RLS** — bucket existe mas upload via API falha. Bucket criado como stub para fotos de trabalho do worker (pós-MVP). Documentado em `database_schema.md`.
- Trigger `on_job_created` (AFTER INSERT em `job_requests` → `notify_workers_new_job()`) adicionado ao `database_schema.md` numa nova secção Triggers.
- Funções internas `client_has_confirmed_job_with_worker`, `is_principal_worker_for_help_request`, `notify_workers_new_job` documentadas em `database_schema.md`.
- Gap C3.2 ainda aberto: worker principal e cliente não têm política SELECT para `help_requests` em estado `open`/`filled`. Documentado em RLS section.

---

## 2026-06-26 — P-8-4 e P-FA4 corrigidos (migration 0016)

### Contexto

Dois gaps de segurança confirmados via corpo exacto de cada função no snapshot directo da BD (`schema_snapshot_2026-06-26.csv` — `pg_get_functiondef`), não inferidos de ficheiros de migration.

### P-8-4 — `reject_reschedule` sem verificação de autorização

`propose_reschedule` e `accept_reschedule` já tinham a verificação completa de que o caller é o cliente ou o worker aceite do job (padrão `v_is_client` / `v_is_worker` / `if not (v_is_client or v_is_worker) then raise exception 'Não autorizado'`). Estas foram provavelmente corrigidas interactivamente na BD numa sessão anterior não registada explicitamente neste log.

`reject_reschedule` não tinha essa verificação — apenas bloqueava o próprio proponente (`if v_job.reschedule_proposed_by = v_user_id then raise`). Qualquer utilizador autenticado que conhecesse o `job_id` e não fosse o proponente podia rejeitar remarcações alheias.

**Correcção (migration 0016):** corpo de `reject_reschedule` substituído por `CREATE OR REPLACE FUNCTION` copiando o padrão de `accept_reschedule` — adiciona as duas variáveis `v_is_client` / `v_is_worker` e o bloco `if not (v_is_client or v_is_worker) then raise exception 'Não autorizado'` antes de qualquer efeito na BD.

### P-FA4 — `job_proposals` UPDATE sem `WITH CHECK`

A política `"Worker atualiza as suas propostas"` tinha `USING (auth.uid() = worker_id)` mas nenhum `WITH CHECK`. Um worker podia fazer UPDATE directo via REST API em qualquer coluna da sua proposta (incluindo `status = 'accepted'`, `status = 'rejected'`, `hourly_rate`, etc.), contornando completamente as RPCs e toda a lógica de negócio associada.

**Correcção (migration 0016):** política recriada com `WITH CHECK (auth.uid() = worker_id AND status = 'superseded')`. O único estado que o worker pode escrever directamente via REST é `superseded` (retirada de proposta). Todas as outras transições (`accepted`, `rejected`) são feitas por RPCs `SECURITY DEFINER` que contornam RLS — ficam inalteradas.

### Estado

**migration 0016 criada localmente — NÃO aplicada à BD. Aplicar manualmente via SQL Editor.**

Após aplicar, verificar:
```sql
-- Confirmar corpo de reject_reschedule tem ambas as variáveis v_is_client/v_is_worker
SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'reject_reschedule';

-- Confirmar WITH CHECK na nova política
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'job_proposals' AND cmd = 'UPDATE';
```

---

## 2026-06-26 — P-FA2 + P-FA7 corrigidos via migration 0019 + Dart

### Confirmação via live query

Query directa ao `pg_policy` (2026-06-26) confirmou que **não existe nenhuma DELETE policy** em `storage.objects` para o bucket `job-photos`. A auditoria original (P-FA2) diagnosticou a policy de 0001 como "não-funcional" — o diagnóstico mais exacto é "ausente": a policy do 0001 nunca chegou a existir na BD viva, ou foi dropada em algum momento sem registo. Igualmente, **nenhuma DELETE policy existe na tabela `job_photos`** (P-FA7 confirmado).

### Causa-raiz: path incompatível com auth.uid()

Com o path de upload antigo `$jobId/<timestamp>.jpg`, `storage.foldername(name)[1]` extrai o `job_id` (UUID do job), não o `auth.uid()` (UUID do cliente). Mesmo que a storage DELETE policy tivesse existido, nunca poderia funcionar com este path.

### Correcção

**Dart — `job_repository.dart`:** `uploadJobPhoto` recebe agora `required String clientId`. Path de upload alterado de:
```
$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg
```
para:
```
$clientId/$jobId/${DateTime.now().millisecondsSinceEpoch}.jpg
```
Com o novo path, `storage.foldername(name)[1]` extrai `clientId` = `auth.uid()` para o cliente que criou o job.

**`create_job_screen.dart:190`:** call site actualizado para passar `clientId: user.id` (variável já em scope na mesma função).

**Migration 0019:** cria dois blocos em simultâneo:
1. Storage DELETE policy `"job-photos: delete pelo dono"` usando `foldername(name)[1]` — agora correcto com o novo path.
2. Table DELETE policy `"Client apaga fotos do seu job"` em `job_photos` — verifica ownership via EXISTS subquery em `job_requests`.

### Caveat: fotos anteriores

Fotos já existentes na BD têm o path antigo (`$jobId/<timestamp>.jpg`). Para essas, `foldername(name)[1]` continua a extrair o `job_id` — não o `client_id` — e a nova storage DELETE policy não as abrange. Sem impacto: a app não tem ainda UI de apagamento de fotos.

### Estado

**Migration 0019 criada localmente — NÃO aplicada à BD. Aplicar manualmente via SQL Editor.**

---

## 2026-06-26 — P-FA3 (CRÍTICO) corrigido via migration 0018

### Confirmação do bug via pg_policy

Query directa ao `pg_policy` (2026-06-26) confirmou que a policy de UPDATE de avatars (`"Update avatar pelo próprio utilizador"`) usava `(storage.foldername(name))[1]` — incompatível com o path real `$userId.jpg` (ficheiro no root do bucket, sem subpasta) usado pelo app em `worker_repository.dart:142` e `client_repository.dart:24`.

`storage.foldername('abc-uuid.jpg')` num ficheiro root-level devolve `{}` (array vazio); `[1]` é NULL; `auth.uid()::text = NULL` avalia a NULL (falso em PostgreSQL). A policy bloqueia silenciosamente todos os re-uploads.

O fix interativo de 2026-06-15 corrigiu **apenas a policy de INSERT** (primeiro upload de avatar) — a policy de UPDATE ficou por corrigir, o que significa que qualquer re-upload de avatar (mudança de foto de perfil após a primeira) estava a falhar silenciosamente em produção.

A policy de DELETE foi confirmada **totalmente ausente** da BD viva via pg_policy.

### Step 1 — Diagnóstico de impacto em utilizadores reais

Query de diagnóstico (requer acesso directo à BD — assistente não pode executar):
```sql
SELECT id, avatar_url, updated_at
FROM   profiles
WHERE  avatar_url IS NOT NULL
ORDER  BY updated_at DESC
LIMIT  10;
```
**Resultado: pendente** — executar manualmente para determinar se algum avatar foi actualizado com sucesso após o primeiro upload. Se `updated_at` de alguma linha for significativamente posterior a `created_at`, indica que o UPDATE path funcionou (ou que o utilizador re-fez upload e o INSERT policy foi avaliado porque o ficheiro não existia por outra razão). Se todos os avatars mostram `updated_at ≈ created_at`, é provável que nenhum utilizador alguma vez conseguiu mudar a foto de perfil com sucesso.

### Correcção (migration 0018)

- DROP de `"Update avatar pelo próprio utilizador"` (nome confirmado via pg_policy) e de `"avatars: update pelo dono"` (nome do 0001) por idempotência.
- CREATE policy de UPDATE com `regexp_replace(storage.filename(name), '\.[^.]+$', '')` — extrai UUID do filename sem extensão.
- CREATE policy de DELETE com a mesma lógica (DROP precautório de ambas as denominações possíveis).
- `storage.filename()` escolhido por ser sibling function de `storage.foldername()` (já confirmada funcional na BD viva pela sua presença nas policies existentes).

### Estado

**migration 0018 criada localmente — NÃO aplicada à BD. Aplicar manualmente via SQL Editor.**

Após aplicar, verificar:
```sql
SELECT polname, cmd,
       pg_get_expr(polqual,      polrelid) AS using_expr,
       pg_get_expr(polwithcheck, polrelid) AS withcheck_expr
FROM   pg_policy
WHERE  polrelid = 'storage.objects'::regclass
  AND  polname  LIKE 'avatars%'
ORDER  BY polname;
```
Confirmar que `"avatars: update pelo próprio utilizador"` e `"avatars: delete pelo próprio utilizador"` aparecem com `regexp_replace(storage.filename(name)...)` nas expressões USING/WITH CHECK, e que `"Update avatar pelo próprio utilizador"` e `"avatars: update pelo dono"` desapareceram.

---

## 2026-06-26 — Sessão 3: lobby de ajudantes reestruturado; P-9-1 implementado (migration 0017)

### Bug real confirmado por Henrique — candidatos além da contagem visível não podiam ser aceites

O lobby usava um modelo de "grelha de N vagas fixas": cada vaga era mapeada a um candidato por ordem de chegada. Candidatos além do `slots_needed` ficavam marcados como `isOverflow = true` e eram não acionáveis — o botão de aceitar não aparecia. Isto era ERRADO: com 3 vagas e 5 candidatos pending, o principal só podia aceitar os primeiros 3. Os candidatos 4 e 5 ficavam invisíveis ao processo de seleção, mesmo com vagas abertas.

**Decisão de produto confirmada:** o principal pode escolher QUAIS candidatos aceitar entre TODOS os pending, não por ordem de chegada. Exemplo: 3 vagas, 5 candidatos — pode aceitar o 1.º, 4.º e 5.º especificamente, rejeitando o 2.º e 3.º.

### Mudança na UI: de "grelha de N vagas" para "lista de candidatos"

Lobby reestruturado em `worker_help_requests_lobby_screen.dart`:
- Removido `_SlotVM`, `_buildSlots()`, `_summaryCaption()`, `_SlotCard` e o conceito `isOverflow`
- Adicionado `_CandidateCard` — card tipo ListTile com avatar, nome, equipamento, taxa (se aceite), e botões de aceitar/rejeitar
- Cabeçalho por help_request: `"X de Y vagas preenchidas"` (conta real, não grid)
- Secção "Aceites" — candidatos aceites com taxa e checkmark, não acionáveis
- Secção "Por decidir" — TODOS os candidatos pending, cada um com botão "Aceitar" ativo e botão X de rejeição
- Guarda client-side: se `accepted_count >= slots_needed` (cache stale antes de refetch), o botão "Aceitar" é desativado; X permanece ativo independentemente do estado

### P-9-1 implementado (migration 0017)

`accept_help_candidate` recriado com loop FOR após o UPDATE que marca `help_request.status = 'filled'`:
- Rejeita todos os pending restantes (`status → 'rejected'`) excluindo o candidato recém-aceite
- Insere notificação `help_rejected` com corpo `'Todas as vagas foram preenchidas.'` para cada um
- Idêntico ao padrão de `auto_confirm_completed_jobs` (migration 0014)

Migration inclui também um DO block de cleanup único: rejeita + notifica todos os `help_acceptances` com `status = 'pending'` cujo `help_request` já está `'filled'` (órfãos de antes desta migration). Idempotente se count = 0. Count de órfãos na BD viva: desconhecido — correr `SELECT COUNT(*) FROM help_acceptances ha JOIN help_requests hr ON hr.id = ha.help_request_id WHERE ha.status = 'pending' AND hr.status = 'filled';` antes de aplicar.

### P-9-2 e P-9-4 fechados por mudança estrutural

P-9-2 ("candidatos overflow não acionáveis") e P-9-4 ("label 'Preenchida' ambígua no card overflow") tornaram-se moot: o modelo de overflow não existe. Não houve fix dirigido — a reestruturação para lista elimina a classe de problema inteiramente.

---

## 2026-06-26 — Sessão 2 da triagem pós-auditoria: P-67-1 e P5 corrigidos em `app_router.dart`

### P-67-1 — `/worker/setup` adicionado a `loadingExempt`

`loadingExempt` passou de `['/loading', '/choose-role']` para `['/loading', '/choose-role', '/worker/setup']`.

**Motivo:** o token Supabase é refrescado automaticamente a cada 60 minutos. Cada refresh dispara `SessionNotifier.build()` → `AsyncValue.loading()` → `RouterNotifier.notifyListeners()` → `redirect()` com `sessionAsync.isLoading = true`. Sem `/worker/setup` na lista de excepções, o redirect enviava o worker para `/loading` e de volta a uma nova instância vazia de `WorkerSetupScreen` — bio, serviços, raio, ferramentas todos perdidos silenciosamente, sem erro nenhum mostrado.

### P5 — Guard cross-role adicionado ao `redirect()`

Adicionado imediatamente após o bloco `role == null`:

```dart
if (role.value == 'client' && loc.startsWith('/worker/')) return '/client/home';
if (role.value == 'worker' && loc.startsWith('/client/')) return '/worker/home';
```

Usa `role.value` string comparison (padrão já existente no ficheiro, não enum identity). Colocado antes dos redirects de "rota pública → home" para evitar duplo redirect.

**Nota de scope:** este guard é uma mitigação parcial. Actualmente (P6 ainda aberto), acesso cross-role às rotas com `state.extra!` causa crash antes de chegar ao ecrã — o guard intercepta antes desse crash. Após P6 ser corrigido (routing baseado em ID), o guard passa a ser a protecção primária contra estado vazio silencioso com dados do UID errado.

---

## 2026-06-25 — Verificação retroativa das Fases 0–7

Verificação completa e independente das Fases 0–7 (marcadas `[x]` no plano mas nunca
auditadas contra o estado real do código e da BD viva). Resultado: **nenhum gap funcional**
encontrado — ao contrário das Fases 8–10, que tinham gaps reais (contactos limitados a
`confirmed`, 24h rule ausente de `cancel_job`, etc.).

**4 issues de documentação corrigidos nesta sessão:**
1. `implementation_plan.md` — Fase 4: todos os itens estavam `[ ]` (não marcados). Corrigido.
2. `implementation_plan.md` — Fase 5: todos os itens estavam `[ ]` (não marcados). Corrigido.
3. `implementation_plan.md` — Fase 10: todos os itens estavam `[ ]` apesar de implementados hoje. Corrigido.
4. `database_schema.md` — `size_estimate`: dizia "sem CHECK na BD viva" mas migration 0001
   inclui `CHECK (size_estimate IN ('small', 'medium', 'large'))`. Corrigido.

**Nota informativa — `create_user_profile` RPC:** existe na BD (migration 0001, linha 473)
mas nunca é chamado pelo código Dart. A app usa `from('profiles').upsert(...)` diretamente,
autorizado pela política INSERT em `profiles`. A própria migration documenta esta escolha:
*"The Dart app currently uses a direct upsert on profiles; this function is kept for
DB-level or admin use."* Não é um bug — é uma decisão de implementação intencional.

## 2026-06-02 — Fotos: máximo 2 por job, compressão obrigatória
Supabase Free Plan tem 50mb de storage. Para maximizar espaço:
- Máximo 2 fotos por job_request.
- Compressão obrigatória antes do upload: largura máxima 800px, qualidade 60%.
- Implementar na Fase 8 com o package `flutter_image_compress`.
- Validação no cliente antes do upload (tamanho + número de fotos).

## 2026-06-02 — Credenciais Supabase via --dart-define + launch.json
As credenciais do Supabase (URL e anon key) são passadas via `--dart-define`
em tempo de execução. Configuradas em `.vscode/launch.json` (no .gitignore).
Sem packages extra (flutter_dotenv descartado). O launch.json nunca vai para
o repositório — cada developer configura o seu localmente.

## 2026-06-02 — Domínio "provider" renomeado para "worker"
No código Dart o domínio do prestador chama-se `worker` (não `provider`), para
evitar colisão com Riverpod e `package:provider`. UI mostra "jardineiro";
tabela na BD é `worker_profiles`.

## 2026-06-02 — Organização por feature
Estrutura `features/<feature>/{data,application,presentation}` em vez de
`data/` global. `core/` só para o que é partilhado por 2+ features.

## 2026-06-02 — Estados como enums + constraints
Estados de jobs/propostas são enums centralizados em `core/constants/` e
refletidos como CHECK/constraints na base de dados. Nunca strings soltas.

## 2026-06-02 — Associação de proposta resolvida na BD
"Primeiro worker a enviar proposta válida fica associado" tem condição de
corrida. Garantir na base de dados (transação/constraint), não na app.

## 2026-06-02 — Fase 7: Perfis
- Localização base do worker via GPS (geolocator).
- Foto de perfil para client e worker (câmara ou galeria, imageQuality 70, maxWidth 400).
- Fotos de trabalhos do worker deixadas para pós-MVP.
- Worker obrigado a completar perfil antes de entrar na home (router redirect).
- Serviços selecionados via FilterChips; ferramentas via texto livre.
- Perfil acessível via ícone no AppBar (designer integra navegação depois).

## 2026-06-02 — Auth: registo em 2 ecrãs
Registo dividido em: Ecrã 1 (email, password, nome, telefone) → Ecrã 2 (escolher
role: client ou worker). Perfil criado na tabela `profiles` após escolha de role.
Validações mínimas: email válido, password ≥ 6 chars, nome e telefone não vazios.
Recuperação de password deixada para pós-MVP.

## 2026-06-02 — /docs reduzido a 5 ficheiros
Essenciais: project_overview, architecture, database_schema,
implementation_plan, decisions_log. workflow/ai_roles/design_handoff ficam nos
documentos originais; só se criam aqui se divergirem.

## 2026-06-05 — Fase 7: bugs resolvidos
- Router redirect usava queries async à BD em cada navegação → refatorado para
  `AsyncNotifierProvider` (SessionNotifier) com refresh explícito.
- `currentUserProvider` era cached permanentemente → corrigido com
  `ref.watch(authStateProvider)` para re-avaliar em cada evento de auth.
- `createProfile` usava INSERT direto → substituído por upsert para ser
  idempotente (resolve duplicate key em retries e trigger handle_new_user).
- Worker setup não refrescava a sessão antes de navegar → adicionado
  `await sessionStatusProvider.notifier.refresh()` antes de `context.go`.
- `/choose-role` não estava na lista de rotas permitidas para utilizadores
  não autenticados → adicionado para evitar redirect loop no primeiro registo.
- Confirmação de email Supabase desativada para MVP — reativar antes do launch.

## 2026-06-08 — Fase 8C.1: Pedidos disponíveis (worker)
- Lista de jobs abertos no raio via RPC get_jobs_in_radius (Haversine na BD).
- Distância calculada no cliente (Geolocator.distanceBetween) para exibição.
- Ordenação por distância (da RPC). Morada só mostrada se existir.
- Envio de proposta via RPC create_proposal (resolve condição de corrida).
- Notificações ficam para a Fase 8C.2 (tabela dedicada + triggers + realtime).

## 2026-06-08 — Fase 8A: decisões de criação de pedido
- Localização via flutter_map + GPS + morada texto; pino define coordenadas; sem geocoding.
- Serviço por dropdown (seleção única). Data com opção "flexível" (preferred_date nullable).
- Urgência: toggle (normal/urgent). Tamanho: chips (small/medium/large).
- Fotos comprimidas no cliente a 1280px/qualidade 72% (flutter_image_compress) antes do upload.
- preferred_date passou a nullable. Adicionadas políticas RLS a job_photos e storage (job-photos).
- ServiceType/serviceTypesProvider reutilizados de features/worker por agora; mover para shared no futuro se necessário.

## 2026-06-09 — Fase 8B: decisões de lista e detalhe de pedidos (cliente)
- Proposta aceite/recusada via update direto nas tabelas (não RPC) — suficiente para MVP single-user.
- cancelJob faz update direto (status→cancelled); não usa RPC para MVP.
- JobProposal.fetchProposalById adicionado para suportar secção "confirmado" quando a tela é aberta diretamente (não só após aceitar na sessão atual).
- workerBasicInfoProvider usa sentinel string vazia → fetchWorkerBasicInfo devolve {} imediatamente — evita ref.watch condicional.
- Contacto WhatsApp: limpa espaços/hífens do telefone, abre wa.me/<número> em app externa; requer package android.name="com.whatsapp" em queries.
- _statusInfo duplicado em client_jobs_screen e client_job_detail_screen (funções top-level privadas) — sem abstração partilhada para MVP.
- url_launcher adicionado (já era dependência transitiva via supabase_flutter; promovido a dependência direta).

## 2026-06-11 — Fase 8C.2: Sistema de notificações
- Tabela `notifications` dedicada na BD (user_id, type, title, body, related_id, related_type, read).
- Triggers na BD para: novo job no raio (workers), proposta recebida (cliente),
  proposta aceite/recusada (worker).
- Realtime via Supabase stream — um canal por utilizador, subscrito em notificationsStreamProvider.
- NotificationType: constantes centralizadas para todos os tipos.
- NotificationHandler: routing centralizado ao toque na notificação.
- notificationSyncProvider: invalida providers relevantes quando chegam notificações novas.
- Badge de contagem não lidas no sino do AppBar (Material 3 Badge widget).
- Extensível: novos tipos requerem apenas nova constante + caso no NotificationHandler.

## 2026-06-11 — Fase 8C.1 bugfixes + geocoding + horas como intervalo
- Bug: fetchWorkerBasicInfo usava .single() → PGRST116 quando perfil não existe; corrigido para .maybeSingle() com retorno {} em null.
- Bug: ecrã de detalhe do cliente mostrava morada vazia; corrigido com addressText.isNotEmpty nos dois ecrãs de cliente (detalhe e lista).
- Bug: secção "confirmado" no detalhe do cliente mostrava loading infinito em caso de erro; corrigido com handler explícito "Não foi possível carregar o contacto." para erro e para map vazio quando workerId ainda não foi resolvido.
- Horas estimadas na proposta passaram de valor único para intervalo (min/max); DB precisa de colunas estimated_hours_min e estimated_hours_max em job_proposals e função RPC create_proposal atualizada (TODO marcado).
- Geocoding adicionado ao ecrã de criação de pedido: botão de pesquisa no campo de morada move o pino no mapa para o resultado (package geocoding 4.0.0).

## 2026-06-11 — Fase 8D: Worker "Os meus jobs"
- `fetchWorkerProposalsWithJobs` em ProposalRepository: join `job_proposals` + `job_requests` numa query (select('*, job_requests(*)')).
- `markJobCompleted` em ProposalRepository: update direto em `job_requests` (não RPC) — suficiente para MVP single-user, igual ao padrão de cancelJob.
- `fetchClientBasicInfo` em ClientRepository: busca `full_name` e `phone` da tabela `profiles` para o worker ver o contacto do cliente.
- `workerProposalsProvider`: FutureProvider que usa `currentUserProvider` (watch) + `proposalRepositoryProvider` (read) — consistente com outros providers da app.
- `clientBasicInfoProvider`: FutureProvider.family com sentinel string vazia (retorna imediatamente sem chamada à BD) — mesmo padrão que workerBasicInfoProvider.
- WorkerJobsScreen: DefaultTabController (Ativos / Histórico); parsing de List<Map> com records Dart 3 `(JobProposal, JobRequest)`; distância calculada no cliente com Geolocator.
- `_isActive`: proposta rejected ou superseded → histórico; job completed/cancelled → histórico; resto → ativo.
- WorkerMyJobDetailScreen: recebe proposal + job via GoRouter extra; secções distintas por ProposalStatus (accepted/rejected/pending); "Marcar como concluído" invalida workerProposalsProvider + jobsInRadiusProvider e navega para /worker/home.
- Rota `/worker/my-job/:id` dentro do worker ShellRoute — índice da tab bar não muda ao navegar para ela (startsWith('/worker/jobs') não corresponde a '/worker/my-job/').

## 2026-06-12 — Fase 8E.1: Agendamento
- Cliente escolhe date_mode: fixed / flexible / availability (texto dedicado).
- Proposta do worker inclui scheduled_date + scheduled_time (+ scheduled_flexible para horário flexível no dia).
- Ao aceitar, scheduled_* é copiado para confirmed_* no job (via RPC).
- Novo estado awaiting_confirmation adicionado ao enum JobStatus (para conclusão a dois lados, 8E.4).
- create_proposal e accept_proposal DB functions precisam de atualização (TODO marcado no repository).

## 2026-06-14 — Múltiplas propostas por pedido (remoção de proposal_received)
- Removido modelo "primeiro a chegar" — job mantém-se `open` com N propostas pending.
- Removido status `proposal_received` do enum JobStatus (compat: `fromValue` mapeia o valor legado de BD para `open`).
- Campo `proposal_count` adicionado a `job_requests` e ao modelo JobRequest (default 0).
- Cliente vê lista de propostas ordenável (preço / avaliação futura Phase 11).
- Aceitar uma proposta rejeita automaticamente as restantes (via `accept_proposal` RPC).
- Worker vê quantas propostas existem no job (`proposal_count` chip) e se já enviou uma (`workerProposalForJobProvider`).
- Retirar proposta via `withdraw_proposal` RPC (decrementa proposal_count + notifica cliente).
- `proposalWithdrawn` adicionado a NotificationType + notificationSyncProvider + notificationHandler.
- Rejeitadas passam a exibir "Não selecionada" em vez de "Recusada" na UI do worker.
- `proposalForJobProvider` substituído por `pendingProposalsForJobProvider` + `acceptedProposalForJobProvider`.
- `fetchWorkerName` adicionado a WorkerRepository; `workerNameProvider` adicionado a worker_providers.dart.

## 2026-06-15 — Fase 8E.2 + 8E.3: Cancelamento e Remarcação
- Dois botões separados: Remarcar e Cancelar (não um menu).
- 4 razões de cancelamento (cliente vê 4, worker vê 3 — sem "já não preciso").
- Auto-reabertura: cliente máx 1 reabertura, worker máx 2; cria novo job (id diferente) com reopened_from.
- cancelJob usa RPC `cancel_job`; retorna novo job ID se reaberto, null caso contrário.
- proposeReschedule/acceptReschedule/rejectReschedule via RPCs homónimas.
- Regra das 24h aplica-se a cancelamento E remarcação (validado na BD).
- Remarcação: campos no próprio job (uma pendente de cada vez); quem propõe não pode aceitar.
- Client detail: após reschedule propose/accept/reject, actualiza _job local via copyWith.
- Worker detail: após qualquer ação de reschedule/cancel, navega back (widget.job é estático).
- currentUserIdProvider adicionado a auth_providers.dart para comparação de rescheduleProposedBy.
- RadioGroup (Flutter 3.32+) substitui groupValue/onChanged no RadioListTile.
- Null-aware element `?expr` em collection literals (Dart 3.4+) usado em detailChildren.

## 2026-06-09 — Tab bar navigation (client + worker)
- 5-tab NavigationBar (Material 3) para client e worker.
- Tab central (+): client faz push /client/create-job sem alterar índice selecionado; worker mostra bottom sheet "Em breve" sem alterar índice.
- ShellRoute envolve rotas de client e worker — NavigationBar persiste entre screens.
- Índice selecionado derivado de GoRouterState.of(context).matchedLocation (sem estado local).
- /client/messages e /worker/messages e /worker/jobs são rotas placeholder (_PlaceholderScreen) dentro do ShellRoute.
- _PlaceholderScreen definido no app_router.dart (file-private) e referenciado pelas rotas; shell files mantêm cópia privada anotada com ignore:unused_element para facilitar futura migração para StatefulShellRoute.
- Client home mostra últimos 3 pedidos ativos com link "Ver todos"; cumprimento usa primeiro nome de clientProfileProvider.
- FAB e ícone de perfil no AppBar removidos das home screens — substituídos pela NavigationBar.
- flutter/foundation.dart removido do router (flutter/material.dart é superset).

## 2026-06-14 — Tabs internas (cliente) e 3 tabs (worker)
- Cliente: detalhe do job tem 2 tabs (Detalhes / Propostas) só quando status == open.
  Outros estados: vista única sem tabs.
- Worker: "Os meus jobs" tem 3 tabs (Por confirmar / Agendados / Concluídos).
- Excluídos dos workers: rejected, superseded, cancelled, no_response — são ruído.

## 2026-06-15 — Bug fixes pós-testes
- Removido trigger on_proposal_updated (duplicava notificações de aceite/rejeição
  com as RPCs accept_proposal e reject_proposal).
- markJobCompleted migrado para RPC mark_job_done.
- Jobs open cancelados excluídos do histórico do cliente.
- awaitingConfirmation movido para tab Ativos (era Histórico).
- Cancelar job open: dialog simples sem justificação.
- Mensagem de erro de proposta duplicada melhorada.
- cancel_job RPC actualizado: cancelled_worker_id e excluded_worker_ids
  para blacklist de workers após 2 cancelamentos.
- get_jobs_in_radius exclui workers em excluded_worker_ids.
- Storage RLS para avatars corrigida (Bug 1 — feito na BD).

## 2026-06-16 — Optimizações de performance e UX
- App mostrava login ao abrir: corrigido com rota /loading enquanto sessão resolve.
- Splash preso ao minimizar: corrigido com WidgetsBindingObserver em App que
  invalida sessionStatusProvider apenas no resume, não em cada build.
- Jobs onde worker já tem proposta pending removidos da lista home (filtro
  client-side em fetchJobsInRadius — futura melhoria: mover para RPC).
- N+1 queries nos chips da lista home eliminados: workerProposalForJobProvider
  removido de _JobCard; lista mostra apenas contagem total de propostas.

## 2026-06-18 — Fase 8E.4 — Conclusão a dois lados
- proposal_repository: confirmJobCompletion (confirm_job_completion RPC) e reportJobProblem (insert em job_reports).
- job_repository: fetchJobById; job_providers: jobByIdProvider (FutureProvider.family).
- client_job_detail_screen: secção awaiting_confirmation — card informativo + botão confirmar (AlertDialog → RPC → go('/client/jobs')) + botão reportar problema (ModalBottomSheet com StatefulBuilder → RPC → snackbar → follow-up dialog).
- worker_my_job_detail_screen: liveJobStatus via jobByIdProvider; awaiting_confirmation mostra card "Aguarda confirmação do cliente"; confirmed mostra botão "Marcar como concluído".
- notification_providers: jobMarkedDone invalida clientJobsProvider + jobByIdProvider; jobCompleted invalida workerProposalsProvider + jobByIdProvider.
- notification_handler: jobMarkedDone e jobCompleted navegam para /client/jobs ou /worker/home conforme role.

## 2026-06-18 — Performance: notificações e workerProposals
- notificationsStreamProvider filtra só não lidas: stream leve, não dispara ao marcar lidas.
- allNotificationsProvider: fetch estático para histórico completo no ecrã de notificações.
- Ecrã de notificações: secções "Novas" / "Anteriores", botão "Limpar" manual.
- workerProposalsProvider dividido em 3 providers por tab (pending/scheduled/completed).
- Tab Concluídos paginada (20 items por página, "Carregar mais").
- Filtragem movida para a BD (queries focadas por estado).

## 2026-06-18 — Performance review fixes
- fetchScheduledWorkerProposals e fetchCompletedWorkerProposals: filtro client-side em vez de joined column filter (comportamento Supabase Dart não verificado para embedded resources).
- invalidateAllWorkerProposalProviders helper criado para invalidar os 3 providers em conjunto.
- worker_my_job_detail_screen: todas as 6 invalidações corrigidas para os providers corretos por ação.
- Paginação: ref.listen em worker_jobs_screen.dart reseta estado quando provider é invalidado externamente.
- "Limpar" notificações: _optimisticClear elimina flash de lista vazia entre tap e resposta da BD.
- allNotificationsProvider invalidado no final de cada ciclo de notificationSyncProvider.

## 2026-06-19 — job_reports: política SELECT em falta corrigida
Durante a revisão do baseline de migrations detectou-se que a tabela `job_reports`
tinha política de INSERT mas nenhuma de SELECT para utilizadores autenticados.
Um reporter que submetesse um report não conseguia depois ler de volta os seus
próprios registos — o que bloquearia qualquer futura UI de "os meus reports".
Corrigido em `supabase/migrations/0002_job_reports_select_policy.sql`:
`CREATE POLICY "Utilizador vê os seus reports" ON job_reports FOR SELECT USING (auth.uid() = reporter_id);`
SELECT de reports de outros utilizadores continua restrito ao service_role
(acesso via Supabase Studio para moderação). Não há alteração ao código Dart.

## 2026-06-19 — Exclusão de workers em jobs reabertos
Implementado via dois campos em `job_requests`: `cancelled_worker_id` (uuid nullable)
e `excluded_worker_ids` (uuid[], default `'{}'`).
- `cancel_job` RPC guarda o worker cancelador em `cancelled_worker_id` e acrescenta-o
  a `excluded_worker_ids` no job reaberto.
- `get_jobs_in_radius` filtra jobs onde `auth.uid() = ANY(excluded_worker_ids)`.
- A generalização para array (`excluded_worker_ids`) em vez de campo único
  (`cancelled_worker_id` sozinho) permite futuramente excluir múltiplos workers
  (ex: após vários cancelamentos sucessivos no mesmo job reaberto). O campo
  `cancelled_worker_id` mantém-se para auditoria do cancelador específico.
- Dart model (`JobRequest`) mapeia ambos os campos; lógica de exclusão fica
  inteiramente no lado da BD, a app não filtra client-side.

## 2026-06-19 — Reporting de problemas (job_reports)
Implementado via tabela `job_reports` (job_id, reporter_id, description, created_at).
- `reportJobProblem` em `ProposalRepository` faz INSERT direto (não via RPC) com
  `reporter_id = auth.currentUser.id`.
- UI: botão "Reportar problema" no `client_job_detail_screen` quando job está em
  `awaiting_confirmation`; abre bottom sheet com campo de descrição (mín. 10 chars);
  após submit, snackbar + follow-up dialog a perguntar se quer confirmar conclusão
  na mesma.
- RLS: política de INSERT permite ao utilizador autenticado inserir registos onde
  `reporter_id = auth.uid()`. SELECT restrito (TODO: confirmar política exacta nas
  migrations — sem ficheiros SQL no repositório para verificar).
- A tabela foi nomeada `job_reports` (não `reports`) para ser específica ao domínio
  de jobs. O campo original em `improvements.md` referia uma tabela genérica `reports`
  — optámos por escopo mais restrito no MVP.

## 2026-06-19 — jobByIdProvider: invalidações em falta no notificationSyncProvider
`jobByIdProvider` não era invalidado para 5 tipos de notificação, descoberto
durante a code review da 8E.5 (timeline de estados). Efeito: ecrãs de detalhe
de job mantinham dados stale (confirmed_date, reschedule_status, job status)
enquanto o utilizador estava no ecrã e o outro lado efectuava uma acção.
Mais crítico: rescheduleAccepted — o campo confirmed_date muda e o badge
"Remarcação pendente" ficava exibido indefinidamente.
Corrigido adicionando `ref.invalidate(jobByIdProvider)` (forma broad, sem key
de família — consistente com jobMarkedDone/jobCompleted já existentes) aos
casos: `rescheduleProposed`, `rescheduleAccepted`, `rescheduleRejected`,
`proposalAccepted`, `jobCancelled`/`jobReopened` (case partilhado).
A tabela de providers em `docs/state_machine.md` foi também corrigida:
`workerProposalsProvider` (nome fictício) substituído pelos nomes reais
`pendingWorkerProposalsProvider`, `scheduledWorkerProposalsProvider`,
`completedWorkerProposalsProvider`.

## 2026-06-21 — Fase 9 data layer: help_acceptance_status expandido
- `help_acceptance_status` alargado de `accepted|cancelled` para
  `pending|accepted|rejected|cancelled` (migration 0004).
- `pending`: estado inicial quando worker se candidata (applyToHelpRequest).
  Necessário para o modelo lobby onde o principal escolhe entre candidatos.
- `rejected`: novo estado quando o principal recusa um candidato (não confundir
  com `cancelled` que é retirada pelo próprio candidato).
- Ordem deliberada espelha ProposalStatus: pending → accepted/rejected → cancelled.
- `accept_help_candidate` atualizado para verificar status = 'pending' antes
  de aceitar (idempotência — previne aceitar o mesmo candidato duas vezes).
- Nova RPC `reject_help_candidate`: verifica caller = principal worker, verifica
  status = 'pending', atualiza para 'rejected', insere notificação 'help_rejected'.
- Três novos notification types adicionados: `help_request_approved`,
  `help_accepted`, `help_rejected` (constantes em notification_types.dart).
- RLS em help_acceptances completado: INSERT só pelo próprio worker com
  status = 'pending'; SELECT por candidatos (próprias linhas) e pelo principal
  (todas as candidaturas dos seus help_requests via is_principal_worker_for_help_request).
- `applyToHelpRequest` em HelpRequestRepository: INSERT com agreed_rate = 0
  (placeholder; o valor real é definido pelo principal via accept_help_candidate).

## 2026-06-19 — Design da Fase 9 (Equipa e ajudantes)
Design de dados aprovado. Implementação aguarda sessão de design de UI/notificações.

1. **Sem tipo de conta "helper" separado.** Qualquer worker pode candidatar-se a
   ajudar noutro job. A diferença é por participação (brought_equipment), não por
   tipo de pessoa.

2. **Rate do ajudante determinado por equipamento.**
   - Se `equipment_required = true` no help_request: o candidato tem obrigatoriamente
     de trazer equipamento → rate cheio (igual ao do principal).
   - Se `equipment_required = false`: o candidato PROPÕE se leva equipamento ou não
     (com o rate correspondente) e o principal escolhe entre os candidatos — modelo
     "tipo um lobby" (terminologia do Henrique). O principal decide quem aceita, não
     é primeiro-a-chegar.

3. **Critérios mistos no mesmo job resolvidos com múltiplos help_requests.**
   Em vez de slots individuais dentro de um único help_request com critérios mistos,
   publicam-se múltiplos help_requests separados (um por critério). Mantém a estrutura
   simples e reutiliza o suporte já existente a múltiplas linhas por job_id.

4. **Aprovação do cliente depende do momento de criação.**
   - Criado como parte da proposta original aceite (`created_post_confirmation = false`)
     → aprovação implícita, começa diretamente em `open`.
   - Criado depois do job já `confirmed` (`created_post_confirmation = true`) → começa
     em `pending_approval`; só passa a `open` após o cliente aprovar explicitamente
     via RPC `approve_help_request`.

5. **Estimativa de custo extra na proposta inicial.** Quando `people_needed > 1`, a
   app destaca ao cliente: `(people_needed - 1) × hourly_rate × 0.7 × estimated_hours`
   (taxa padrão 70% por ajudante sem equipamento). Sempre como estimativa; o custo
   real fica registado em `help_acceptance.agreed_rate` no momento da aceitação.

6. **`agreed_rate` guardado no momento, nunca recalculado.** Protege o histórico de
   pagamentos contra alterações futuras à regra dos 70%. Mesmo que a percentagem
   default mude no futuro, aceitações passadas refletem o valor acordado na altura.

UI e fluxo de notificações ainda NÃO foram desenhados — ficam para uma sessão de
design futura antes de qualquer implementação.

## 2026-06-19 — Duas ideias de produto registadas em improvements.md
Carteira digital de cartões de benefícios (combustível/seguro): visão de
longo prazo, bloqueada por decisão de negócio (nenhuma parceria fechada),
sem integração NFC/pagamento — versão viável é foto do cartão + campos
texto, mostrado em full-screen para leitura manual. Não avançar antes de
parceria real.
Perfil de worker visitável em 3 camadas: Camada 1 (perfil read-only dentro
da app, RLS a partir de proposta pending, ecrã único com modo próprio/visitante,
sem expor base_lat/base_lng) pode iniciar a qualquer momento. Camadas 2
(portfólio) e 3 (feed na home) sequenciais. Relacionado com "Perfil público
partilhável" mas distinto: esse é partilha fora da app, este é visibilidade
dentro. Nenhuma implementação feita — só registo de visão e decisões de scope.

## 2026-06-24 — Fase 9: helpers_equipment_required + estimativa de custo de equipa

### Campo helpers_equipment_required em job_proposals
- Nova coluna `helpers_equipment_required boolean NOT NULL DEFAULT false` em
  `job_proposals` (migration 0005).
- Quando `true`, todos os ajudantes devem trazer equipamento → rate cheio (factor 1.0).
- Quando `false`, ajudantes podem ou não trazer equipamento → rate reduzido (factor 0.75).

### Factor de estimativa 0.75 vs pagamento real 0.70
- A estimativa exibida ao cliente usa factor **0.75** (75% do rate do principal).
- O pagamento real acordado com o ajudante sem equipamento é 70% (conforme
  decisions_log 2026-06-19 "Rate do ajudante determinado por equipamento").
- A diferença de 5 p.p. é intencional: serve de buffer para que a estimativa
  que o cliente vê nunca subestime o custo real. `agreed_rate` registado em
  `help_acceptances` é sempre a fonte de verdade do valor acordado.
- Fórmula de estimativa: `hourly_rate × estimated_hours × (1 + (people_needed - 1) × factor)`.
  Exibida como total arredondado ("≈ €120 - €160 (equipa incluída)") no card de
  proposta em `client_job_detail_screen.dart`.

### Overloads obsoletos de create_proposal eliminados (migration 0005)
Dois overloads anteriores ao split de estimated_hours em min/max (2026-06-11)
e à introdução de people_needed (2026-06-08) foram dropados:
- `create_proposal(uuid, uuid, numeric, numeric, integer, text)` — 6 params
- `create_proposal(uuid, uuid, numeric, numeric, numeric, integer, text)` — 7 params
Assinaturas confirmadas na live DB antes do drop.

### accept_proposal auto-cria help_request quando people_needed > 1
- Após confirmar o job, se a proposta aceite tem `people_needed > 1`, a RPC
  cria automaticamente um `help_request` com `slots_needed = people_needed - 1`,
  `equipment_required = helpers_equipment_required`, `created_post_confirmation = false`,
  `status = 'open'`.
- `created_post_confirmation = false` → aprovação implícita (não precisa de
  `approve_help_request`), começa diretamente visível a candidatos.
- Sem alteração ao código Dart de `acceptProposal()` — a criação é transparente
  para o cliente Flutter.

## 2026-06-16 — Polish e fixes pré-8E.4
- workerProposalForJobProvider: guard para userId vazio + watch reactivo via currentUserIdProvider.
- proposalWithdrawn invalida jobsInRadiusProvider (job volta à lista disponível) e workerProposalForJobProvider.
- Mensagens de erro: helper friendlyError centralizado em core/utils/error_utils.dart; substitui todos os 'Erro: $e' raw.
- Preço €0/null: substituído por "Preço a definir" em client_job_detail, worker_my_job_detail, worker_jobs list; perfil e proposta sheet ignoram rate ≤ 0.
- Datas verificadas: formato dd/MM/yyyy em todos os DateFormat; hora explicitamente HH:mm (padLeft) em reschedule_dialog.
- worker_jobs_screen pull-to-refresh invalida também jobsInRadiusProvider.

## 2026-06-24 — Overloads obsoletos descobertos durante deployment de 0002-0007

Descoberto durante a primeira aplicação manual das migrations 0002–0007 à live DB
(nunca tinham sido aplicadas antes desta sessão): o comportamento de
`CREATE OR REPLACE FUNCTION` em PostgreSQL cria um **novo overload** quando a lista
de parâmetros muda — não substitui a assinatura antiga. Dois overloads ficaram vivos:

### cancel_job(uuid)
- Criado interativamente na BD antes do tracking por migrations começar.
- Assinatura: `cancel_job(p_job_id uuid)` — sem razão, sem lógica de reabertura.
- Supersedido por `cancel_job(uuid, text, text DEFAULT NULL)` no `0001_baseline.sql`,
  mas como o baseline usou `CREATE OR REPLACE` com lista diferente, o overload antigo
  sobreviveu.

### create_proposal — versão 10 parâmetros
- Assinatura: `create_proposal(uuid, uuid, numeric, numeric, numeric, integer, text, date, text, boolean)`
- É a versão do `0001_baseline.sql` (com `p_scheduled_time text`).
- Supersedida quando a migration `0005` adicionou `p_helpers_equipment_required boolean`
  como 11.º parâmetro via `CREATE OR REPLACE` — o que criou um novo overload em vez de
  substituir o de 10 parâmetros.
- **Nota:** os overloads de 6 e 7 parâmetros foram corretamente dropados em 0005 com
  `DROP FUNCTION IF EXISTS` explícito — o de 10 parâmetros foi deixado por engano.

**Fix:** `supabase/migrations/0008_drop_obsolete_overloads.sql` dropa ambos com
`DROP FUNCTION IF EXISTS`. Após aplicação, cada função deve ter exactamente um overload.

**Lição aprendida:** ao adicionar um parâmetro a uma função existente via
`CREATE OR REPLACE`, sempre preceder com `DROP FUNCTION IF EXISTS <assinatura-antiga>`
para evitar acumulação silenciosa de overloads. Ver padrão correto em 0005
(drops explícitos dos overloads de 6 e 7 params) e 0006 (drop explícito antes de
mudar o return type).

## 2026-06-24 — Code review da Fase 9 completa + descoberta crítica de deployment

### Code review (22 itens, 7 categorias)

Code review completa de tudo construído na Fase 9 (schema, RPCs, RLS, modelos Dart,
e todos os 5 touchpoints de UI). 10 itens resolvidos imediatamente; 4 deixados em
backlog não bloqueante; restantes são informativos/confirmados corretos.

**Fixes aplicados via migration 0007:**
- **C2.2** — `cancel_job` agora faz cascade: cancela `help_requests` abertos e rejeita
  `help_acceptances` pending quando um job é cancelado. Previne órfãos visíveis no
  ecrã de descoberta e no lobby.
- **C2.3 + C7.4** — `get_help_requests_in_radius` agora exclui jobs com
  `status IN ('cancelled', 'completed')` E exclui help_requests onde o caller é o
  worker principal (`jp.worker_id <> auth.uid()`). Previne que candidatos vejam jobs
  cancelados ou se candidatem ao próprio help_request.
- **C3.1** — Removida política RLS "Worker aceita ajudar" (baseline) em
  `help_acceptances` FOR INSERT. Era mais permissiva que a política de 0004 e, como
  o PostgreSQL faz OR entre políticas permissivas, tornava a restrição de `status =
  'pending'` ineficaz. A política "Worker candidata-se a help_request" (0004) é agora
  a única INSERT policy e funciona como esperado.
- **C3.3** — Política RLS "Worker principal cria help_requests" em `help_requests` FOR
  INSERT restringida a propostas com `status = 'accepted'`. Antes permitia INSERT para
  qualquer proposta do worker independentemente do estado.
- **C3.4** — Política RLS "Worker cancela ajuda" em `help_acceptances` FOR UPDATE
  restringida com `WITH CHECK (status = 'cancelled')`. Antes permitia ao candidato
  atualizar qualquer coluna (incluindo `agreed_rate` e `status`) para qualquer valor.
- **C5.2 (BD)** — Adicionado `CHECK (status <> 'accepted' OR agreed_rate > 0)` em
  `help_acceptances`. Constraint condicional (não `> 0` incondicional) porque
  `applyToHelpRequest` insere `agreed_rate = 0` como placeholder para candidaturas
  pending — o valor real é definido pelo principal via `accept_help_candidate`. Pre-flight
  na migration aborta se existirem linhas accepted com rate ≤ 0.

**Fixes aplicados no Dart:**
- **C7.1** — `client_job_detail_screen.dart`: `onPressed: accepting ? () {} : onAccept`
  corrigido para `onPressed: accepting ? null : onAccept`. O `() {}` impedia o
  `FilledButton` de mostrar o estilo desativado durante a chamada de aceitação.
- **C5.2 (cliente)** — `worker_help_requests_lobby_screen.dart`: validação adicionada
  antes de chamar `acceptCandidate`. Se o campo de taxa é apagado ou inválido →
  fallback para o valor sugerido (comportamento anterior preservado). Se o utilizador
  escrever explicitamente um valor ≤ 0 → SnackBar "A taxa deve ser maior que zero.",
  sem chamar o RPC, sem fechar o sheet.

**Backlog (não bloqueante — nenhum ecrã de UI precisa deles ainda):**
- C3.2 — Sem política SELECT para o cliente ver `help_requests` em estado `open`/`filled`.
- C7.2 — Estado de erro no lobby substitui ecrã inteiro em vez de mostrar erro inline.
- C7.5 — `_iconForType` em `notifications_screen.dart` não é exaustivo para 9 tipos
  de notificação pré-Fase-9 (mostram ícone genérico de sino).
- C7.7 — `helpAccepted` navega para `/worker/jobs` mas os `help_acceptances` não
  aparecem nesse ecrã — gap de UX até ser criado um ecrã dedicado de "helper jobs".

### CRÍTICO: migrations 0002-0007 nunca tinham sido aplicadas à BD viva

Descoberto durante a verificação manual em 2026-06-24: **as migrations 0002 a 0007
nunca tinham sido aplicadas à base de dados de produção**, apesar de estarem marcadas
como "feitas" em sessões anteriores.

**Causa raiz:** o Claude Code consegue *ler* a BD via REST API do Supabase mas
**não consegue executar alterações de schema diretamente** — apenas cria ficheiros
`.sql` localmente. Em sessões anteriores, após criar os ficheiros de migration, o
assistente reportou o trabalho como "concluído" sem confirmar se tinham sido aplicados.

**Descoberto quando:** queries de verificação manual falharam a encontrar colunas e
constraints esperados (ex: `helpers_equipment_required`, `equipment_required`,
`created_post_confirmation`, políticas RLS da Fase 9).

**Resolução:** todas as migrations 0001 a 0007 foram aplicadas manualmente via o SQL
Editor do Supabase em 2026-06-24. Durante este processo, dois overloads obsoletos
adicionais foram encontrados (`cancel_job(uuid)` e `create_proposal` de 10 parâmetros)
e removidos via migration 0008 (ver entrada anterior neste log).

### Lição aprendida: confirmação de deployment obrigatória

> **Regra a seguir em todas as sessões futuras:** após qualquer prompt que crie um
> ficheiro de migration, confirmar explicitamente com o Claude Code se a migration foi
> aplicada à BD viva ou apenas escrita como ficheiro. Nunca assumir que "criado" =
> "aplicado". Em caso de dúvida, verificar diretamente via SQL Editor antes de
> considerar uma migration "feita".

O Claude Code deve terminar qualquer resposta que crie um ficheiro `.sql` com a frase
explícita: *"Este ficheiro foi criado mas NÃO aplicado à base de dados. Tens de o
aplicar manualmente."*

## 2026-06-24 — Fase 9: três gaps de cancelamento fechados (migration 0009)

### Problema

Após o code review da Fase 9, identificaram-se três situações não cobertas:

1. **Ajudantes aceites não eram notificados quando o job era cancelado.** O `cancel_job`
   (0007) fazia cascade de `help_requests` e rejeitava `help_acceptances` pending, mas
   não notificava os ajudantes com `status = 'accepted'`.

2. **Um ajudante aceite não tinha forma de se retirar.** Não existia nenhum RPC ou
   endpoint para cancelar a própria candidatura aceite.

3. **Quando um ajudante se retirava de um `help_request` preenchido, o slot ficava
   perdido.** Nenhuma lógica repunha o `help_request` a `open` nem notificava os
   candidatos rejeitados da nova vaga.

### Solução (migration 0009)

**cancel_job (atualização):**
- Após os cascade UPDATEs existentes (0007), insere notificações `help_job_cancelled`
  para todos os `help_acceptances` com `status = 'accepted'` no job cancelado.
- O filtro `ha.status = 'accepted'` é seguro após o cascade porque o cascade apenas
  rejeita `pending` — os `accepted` ficam inalterados até esta INSERT.
- `related_id = p_job_id`, `related_type = 'job_request'`.

**withdraw_help_acceptance (novo RPC SECURITY DEFINER):**
- Pré-condições: chamador = `worker_id` da candidatura; `status = 'accepted'`.
- Efeito 1: `help_acceptances.status → 'cancelled'`.
- Efeito 2: se `help_request.status = 'filled'`, reverte para `'open'` (slot libertado).
- Efeito 3: se houve reabertura, notifica todos os candidatos `rejected` com
  `help_request_reopened` (podem re-candidatar-se).
- Efeito 4 (sempre): notifica o worker principal com `help_withdrew`.
- `related_id = help_request_id` para ambas as notificações.
- Nota de race condition: dois ajudantes a retirar-se simultaneamente podem enviar
  notificações duplicadas de reabertura. Idempotente nos dados; aceitável para MVP.

**Três novos tipos de notificação (notification_types.dart):**
- `help_job_cancelled` — ajudante notificado de que o job que aceitou foi cancelado.
  Handler: `context.go('/worker/help-requests', extra: {'initialTabIndex': 1})`
  (tab "As minhas candidaturas"). Sync: invalida `helpRequestSummariesInRadiusProvider`
  + `helpRequestsInRadiusProvider` + `myHelpAcceptancesProvider`.
- `help_request_reopened` — candidato rejeitado notificado de vaga disponível.
  Handler: `context.push('/worker/help-requests')` (discovery screen). Sync: invalida
  `helpRequestSummariesInRadiusProvider` + `helpRequestsInRadiusProvider`.
- `help_withdrew` — principal notificado de que um ajudante desistiu.
  Handler: fetch help_request → job → proposal → `context.push` lobby (mesmo padrão
  que `helpRequestApproved`). Sync: invalida `helpRequestsForJobProvider`.
- `help_rejected` (pré-existente) — deixou de ser puramente informacional: sync passa
  a invalidar `myHelpAcceptancesProvider` para actualizar a tab "Histórico" do ajudante.
- `help_accepted` (pré-existente) — handler alterado de `context.go('/worker/jobs')`
  para `context.go('/worker/help-requests', extra: {'initialTabIndex': 1})`; sync passa
  a invalidar também `myHelpAcceptancesProvider`.

**Dart — HelpRequestRepository:**
- Adicionado `withdrawHelpAcceptance(String helpAcceptanceId)` que chama o novo RPC.

**Gap de UI resolvido (C7.7):**
- `withdrawHelpAcceptance` tem agora ponto de entrada na UI através da tab "As minhas
  candidaturas" em `WorkerHelpRequestsScreen` (ver entrada de 2026-06-24 abaixo).
  O gap C7.7 do code review está fechado.

**RLS:** ambas as funções são SECURITY DEFINER — contornam RLS. A política
"Worker cancela ajuda" (`WITH CHECK status = 'cancelled'`) é compatível com o que
`withdraw_help_acceptance` escreve, mas é irrelevante porque o SECURITY DEFINER
não a aplica.

**Estado:** migration 0009 aplicada à BD viva (confirmado via probe REST API
2026-06-24: `withdraw_help_acceptance` devolve HTTP 400 — função existe).

## 2026-06-24 — Fase 9: get_my_help_acceptances RPC (migration 0010)

### Problema

Para popular a tab "As minhas candidaturas" (ver entrada abaixo), é necessário
carregar todas as candidaturas do ajudante autenticado com contexto suficiente para
display (nome do serviço, nome do worker principal, estado do job pai). Um SELECT
direto via PostgREST em `help_acceptances` não consegue resolver o JOIN necessário.

### Decisão: SECURITY DEFINER RPC em vez de PostgREST embedded join

O join necessário é um two-hop FK:
`job_proposals.worker_id → worker_profiles.profile_id → profiles.id`

O PostgREST resolve JOINs simples (um salto de FK direta), mas esta cadeia
`worker_profiles.profile_id` como intermediário não tem uma FK direta de
`help_acceptances` para `profiles` — a linha do ajudante passa por
`help_requests → job_requests → service_types` E por
`help_requests → job_proposals → profiles`. O PostgREST embedded join falha
neste cenário de FK indireta.

Solução: `get_my_help_acceptances()` — função SECURITY DEFINER STABLE que:
- Filtra por `ha.worker_id = auth.uid()` (sem expor dados de outros workers)
- Faz os JOINs em SQL (sem limitações PostgREST)
- Devolve: `id`, `help_request_id`, `status`, `agreed_rate`, `brought_equipment`,
  `created_at`, `service_type_name`, `principal_name`, `job_status`
- Ordenado por `ha.created_at DESC`

**Padrão reutilizado:** idêntico à decisão da migration 0006 (`get_help_requests_in_radius`
com join de contexto), onde o mesmo problema de FK indireta levou à mesma solução.

**Dart:**
- `fetchMyHelpAcceptances()` em `HelpRequestRepository` (chama o RPC)
- `myHelpAcceptancesProvider` — `FutureProvider<List<HelpAcceptanceSummary>>`
- `HelpAcceptanceSummary` — classe de modelo distinta de `HelpAcceptance` (que é
  usada no lobby do principal e tem campos diferentes)

**Estado:** migration 0010 aplicada à BD viva (confirmado via probe REST API
2026-06-24: `get_my_help_acceptances` devolve HTTP 200 — função existe).

## 2026-06-24 — Fase 9: tab "As minhas candidaturas" em WorkerHelpRequestsScreen

### Problema

Após fechar os gaps de cancelamento (0009 + `withdrawHelpAcceptance`), o RPC existia
mas não havia nenhum ponto de entrada na UI para o ajudante ver ou gerir as suas
candidaturas — o gap C7.7 do code review.

### Solução

`WorkerHelpRequestsScreen` convertida de ecrã único para ecrã com 2 tabs:

**Estrutura:**
- `DefaultTabController(length: 2, initialIndex: widget.initialTabIndex)` com:
  - Tab 0 "Descobrir" — conteúdo original (`_buildDiscoverTab()`, inalterado)
  - Tab 1 "As minhas candidaturas" — novo `_MyApplicationsTab`
- `initialTabIndex` passado como parâmetro de construtor (default 0)

**`_MyApplicationsTab` (ConsumerStatefulWidget):**
- Consome `myHelpAcceptancesProvider`
- Três secções: Pendentes / Aceites / Histórico (rejected + cancelled)
- Pull-to-refresh: `ref.invalidate(myHelpAcceptancesProvider)`
- Botão "Desistir" nas candidaturas aceites: AlertDialog de confirmação →
  `withdrawHelpAcceptance()` → `ref.invalidate(myHelpAcceptancesProvider)`
- Estado vazio único quando todas as secções estão vazias

### Deep-linking via go_router state.extra

Para que notificações possam navegar diretamente para a tab correcta, a rota
`/worker/help-requests` foi actualizada para ler `initialTabIndex` de `state.extra`:

```dart
GoRoute(
  path: '/worker/help-requests',
  builder: (_, state) {
    final extra = state.extra as Map<String, dynamic>?;
    return WorkerHelpRequestsScreen(
      initialTabIndex: extra?['initialTabIndex'] as int? ?? 0,
    );
  },
)
```

Chamadores sem `extra` recebem tab 0 (Descobrir) por omissão — sem regressão.
`DefaultTabController` suporta `initialIndex` nativamente; sem necessidade de
`TickerProviderStateMixin` ou estado externo.

## 2026-06-24 — Fase 9: TODO comments em notification_handler.dart fechados

### Contexto

Dois casos no switch de `NotificationHandler.handle()` tinham TODOs a marcar
que a navegação era um fallback incorreto enquanto não existisse um ecrã dedicado
de "helper jobs":

- `helpAccepted` — navegava para `context.go('/worker/jobs')` com TODO
- `helpJobCancelled` — navegava para `context.go('/worker/jobs')` com TODO

`/worker/jobs` é o ecrã "Os meus jobs" do worker **principal** (propostas aceites),
que não mostra candidaturas de ajudante — o utilizador ficava no ecrã errado.

### Resolução

Com a tab "As minhas candidaturas" disponível em `/worker/help-requests`, ambos os
casos foram actualizados para:

```dart
context.go('/worker/help-requests', extra: {'initialTabIndex': 1});
```

Os comentários TODO foram removidos. O switch em `NotificationHandler` é agora
exaustivo para todos os 19 tipos em `NotificationType` sem comentários de débito.

## 2026-06-25 — Crosscheck BD viva vs docs vs Dart + migrations 0011–0012

### Crosscheck três vias (snapshot DB 2026-06-25)

Comparação sistemática entre o snapshot da BD viva (`docs/_db_snapshot_2026-06-25/`,
4 CSV files) e todos os ficheiros de docs + código Dart (repositórios, modelos, enums).

**Achado 1 — `get_jobs_in_radius` overload obsoleto ainda vivo (migration 0011)**
O overload sem `p_worker_id` (`get_jobs_in_radius(numeric, numeric, integer)`) nunca
foi dropado em 0008. Confirmado em `02_functions.csv`. O Dart sempre passa `p_worker_id`
via named params, pelo que o overload obsoleto nunca é chamado pelo código da app —
mas era invocável diretamente via SQL, retornando todos os jobs no raio sem filtrar o
próprio worker. Corrigido em `0011_drop_obsolete_get_jobs_in_radius.sql`.

**Achado 2 — CRITICAL 2 era falso alarme (get_help_requests_in_radius)**
O relatório do crosscheck assinalou como CRÍTICO que a função em `0003_help_requests_team.sql`
retornava `SETOF help_requests` (apenas colunas da própria tabela), mas `HelpRequestSummary`
necessita de `location_lat`, `location_lng`, `service_type_id`, `principal_name`.
Verificação via `pg_get_functiondef` na BD viva mostrou que a migration 0006 já tinha
atualizado a função com `RETURNS TABLE(...)` e todos os JOINs necessários — incluindo
a exclusão de jobs `cancelled`/`completed` e de help_requests onde o caller é o principal
(fixes C2.3 + C7.4 do code review de 2026-06-24). O ficheiro `0003_help_requests_team.sql`
tem o corpo desatualizado, mas é inofensivo: a BD viva tem a definição correcta de 0006.
Sem SQL fix necessário.

**Nota técnica:** `get_jobs_in_radius` usa `numeric` para lat/lng; `get_help_requests_in_radius`
usa `double precision`. Inconsistência cosmética entre as duas variantes da fórmula de
Haversine — ambas correctas. Uniformizar para `numeric` na próxima vez que uma das
funções for alterada.

**Achado 3 — Sem política SELECT para candidatos em `help_requests` (migration 0012, HIGH)**
Workers candidatos não tinham nenhuma política SELECT em `help_requests`. A descoberta
via RPC SECURITY DEFINER funcionava, mas qualquer fetch direto por um candidato
(`fetchHelpRequestById`, `fetchHelpRequestsForJob`) retornava null/vazio silenciosamente.
Adicionada política "Worker candidato vê help requests onde se candidatou" em 0012.

**Achado 4 — Políticas duplicadas em `job_proposals` (migration 0012, MEDIUM)**
Dois pares de políticas funcionalmente idênticas encontrados em `03_policies.csv`:
- INSERT: "Worker envia proposta" e "Worker cria propostas"
- SELECT: "Worker vê as suas propostas" (com acento) e "Worker ve as suas propostas" (sem acento)
Criados por migrations separadas que não verificaram políticas pre-existentes.
Duplicados dropados em 0012; variantes com nomes correctos mantidas.

**Outros achados não bloqueantes (nenhuma alteração ao código):**
- `help_acceptances.status` tem default `'accepted'` na BD mas a RLS de INSERT força
  `status = 'pending'` — default nunca é usado via app. Cosmético.
- `job_proposals.estimated_hours` (coluna legacy nullable) existe na BD mas não é mapeada
  no `JobProposal.fromJson` — ignorada silenciosamente, sem risco.
- `job_requests.confirmed_flexible`: nullable na BD; Dart usa `bool? ?? false`. Cosmético.
- Todos os enums Dart estão em perfeito alinhamento com os CHECK constraints da BD.
- Todas as assinaturas de RPC correspondem exactamente aos chamadores no Dart.

### Docs actualizados

- `database_schema.md`: corrigido `size_estimate` (sem CHECK na BD, só enum Dart);
  corrigida secção RLS de `notifications` (sem política INSERT; inserts via SECURITY
  DEFINER); adicionada nota sobre política de candidatos em `help_requests`.

### Estado das migrations

**0011** — escrita localmente, **NÃO aplicada** à BD. Aplicar via SQL Editor.
**0012** — escrita localmente, **NÃO aplicada** à BD. Aplicar via SQL Editor após 0011.

---

## 2026-06-25 — Bug de loading infinito no arranque a frio — causa raiz e correção

### Contexto

Em arranques a frio sem sessão cacheada (utilizador desligado / primeira instalação),
a app ficava indefinidamente no ecrã `/loading` sem crash, sem exceção, sem redirect.
Utilizadores com sessão cacheada (fast path em `SessionNotifier.build()`) não eram
afectados — o bug nunca foi capturado em testes manuais durante o desenvolvimento
porque os developers têm sempre sessão persistida.

### Diagnóstico

Adicionados `debugPrint` temporários a `SessionNotifier` e `RouterNotifier` para
rastrear o fluxo de estado. Os logs confirmaram:

1. `SessionNotifier.build()` resolvia correctamente e depressa: `currentSession=NULL`
   → slow path → stream emitiu `session=NULL` → retornou `SessionStatus.unauthenticated`.
2. `ref.listen(sessionStatusProvider, ...)` disparava (Riverpod 3.x notifica na
   transição `AsyncLoading → AsyncData`, incluindo a primeira resolução do `build()`).
3. `notifyListeners()` era chamado → GoRouter re-avaliava `redirect()`.
4. `redirect()` era chamado com `loc=/loading`, `isAuthenticated=false` →
   entrava no branch `!isAuthenticated` → `publicRoutes.contains('/loading') == true`
   → **retornava `null` (ficar)**.

### Causa raiz

`'/loading'` estava incorrectamente incluído em `publicRoutes` no branch
`!isAuthenticated` de `RouterNotifier.redirect()`:

```dart
// ANTES (buggy):
const publicRoutes = ['/', '/login', '/signup', '/loading'];
return publicRoutes.contains(loc) ? null : '/';
```

O branch `isLoading` acima já trata a espera inicial (enquanto `build()` está a correr,
fica em `/loading`). Uma vez que a sessão resolve — mesmo para `unauthenticated` —
`/loading` nunca deve ser um destino válido. Ao incluí-lo em `publicRoutes`, o router
interpretava-o como "ecrã público seguro para não-autenticados" e nunca redirecionava
o utilizador.

### Correção

Removido `'/loading'` de `publicRoutes`:

```dart
// DEPOIS (correcto):
const publicRoutes = ['/', '/login', '/signup'];
return publicRoutes.contains(loc) ? null : '/';
```

Um utilizador não-autenticado em `/loading` (sessão resolvida) é agora redirecionado
para `'/'` (LandingScreen).

### Ficheiros alterados

- `lib/core/router/app_router.dart` — removido `'/loading'` de `publicRoutes`
- `lib/features/auth/application/session_provider.dart` — removidos prints de diagnóstico
- `lib/core/router/app_router.dart` — removidos prints de diagnóstico

## 2026-06-25 — Dois bugs de redirect no RouterNotifier (signup flow)

### Bug 1 — Utilizadores com `role=null` saltavam o ecrã `/choose-role`

**Causa raiz:** o branch `!isAuthenticated` de `redirect()` tratava `/choose-role` como
rota pública (estava na lista de `publicRoutes`). Quando a sessão resolvia para
`isAuthenticated=true, role=null` (utilizador acabou de se registar, ainda sem perfil),
nenhum branch tratava o caso — o código chegava ao bloco:

```dart
if (loc == '/' || loc == '/loading' || ... || loc == '/choose-role') {
  return role?.value == 'worker' ? '/worker/setup' : '/client/home';
}
```

`role == null`, por isso `role?.value == 'worker'` é `false` → redirecionava para
`/client/home` sem o utilizador ter escolhido a sua role ou criado perfil.

**Correção:** adicionado guard explícito antes do bloco de "landing pages":

```dart
// Authenticated but no profile yet (fresh signup, role not chosen)
if (role == null) {
  return loc == '/choose-role' ? null : '/choose-role';
}
```

---

### Bug 2 — A correção do Bug 1 introduziu uma regressão: `fullName`/`phone` chegavam vazios à BD

**Sintoma:** contas criadas depois do Bug 1 ter sido corrigido tinham `full_name = ''`
e `phone = ''` na tabela `profiles` (strings vazias, não null).

**Causa raiz — sequência exata de eventos:**

1. `signup_screen._submit()` chama `context.go('/choose-role', extra: {'fullName': 'João', 'phone': '912...'})`
2. GoRouter constrói `ChooseRoleScreen(fullName: 'João', phone: '912...')` ✓
3. O stream `onAuthStateChange` do Supabase dispara (na próxima iteração do event loop, após `signUp()` regressar)
4. `authStateProvider` atualiza → `sessionStatusProvider.build()` re-executa → estado vai para `AsyncValue.loading()`
5. `RouterNotifier.notifyListeners()` dispara → GoRouter avalia `redirect()`:
   `sessionAsync.isLoading == true` → `loc == '/loading' ? null : '/loading'`
   `loc = '/choose-role'` → **redireciona para `/loading`**, descartando a rota com `state.extra`
6. `_fetchProfile()` resolve → `role == null` (ainda sem perfil na BD) → `sessionStatusProvider` resolve
7. `redirect()` avalia de novo: `role == null`, `loc == '/loading'` → retorna `'/choose-role'`
8. GoRouter navega para `/choose-role` — mas **este é um redirect iniciado pelo router, sem `extra`**
9. Builder chamado com `state.extra = null` → `ChooseRoleScreen(fullName: '', phone: '')` ✗
10. Utilizador escolhe role → `createProfile(fullName: '', phone: '', role: worker)` → strings vazias na BD

O problema é a viagem de ida e volta `/choose-role` → `/loading` → `/choose-role`: na
segunda chegada, o `state.extra` original já não existe porque o redirect é iniciado
pelo router (um path string), não por `context.go` com `extra`.

**Correção:** isentar `/choose-role` do redirect de loading, tal como `/loading` já era isento:

```dart
// ANTES (buggy após Bug 1 fix):
if (sessionAsync.isLoading) {
  return loc == '/loading' ? null : '/loading';
}

// DEPOIS (correcto):
if (sessionAsync.isLoading) {
  // Don't bounce /choose-role through /loading — the auth stream fires
  // immediately after signUp() while the user is transitioning to role
  // selection; the loading state is transient and /choose-role handles it
  // visually fine on its own. Bouncing through /loading would discard the
  // fullName/phone passed via navigation extra.
  const loadingExempt = ['/loading', '/choose-role'];
  return loadingExempt.contains(loc) ? null : '/loading';
}
```

**Porquê é seguro:** `/choose-role` só é acessível a utilizadores autenticados sem
perfil (o guard `role == null` logo abaixo trata qualquer caso onde alguém chegue aqui
sem a sessão resolver para `role == null`). Manter o utilizador em `/choose-role`
durante o estado loading transiente não cria nenhum gap de segurança.

### Estado final dos branches `isLoading` e `role == null` em `redirect()`

```dart
if (sessionAsync.isLoading) {
  const loadingExempt = ['/loading', '/choose-role'];
  return loadingExempt.contains(loc) ? null : '/loading';
}

// ...

if (role == null) {
  return loc == '/choose-role' ? null : '/choose-role';
}
```

**Ficheiro alterado:** `lib/core/router/app_router.dart` — branch `isLoading`

## 2026-06-25 — Fase 10: regra das 24h adicionada ao cancelamento

### Gap encontrado

A regra das 24h existia em `propose_reschedule` (enforcement na BD) desde a Fase 8E.2,
e estava documentada em `state_machine.md` sob "Regras de cancelamento" como especificação.
No entanto, `cancel_job` nunca implementou esta restrição — o RPC e as UIs aceitavam
cancelamentos com qualquer antecedência, mesmo a minutos do serviço.

Descoberto na verificação da Fase 10 (2026-06-25).

### Solução

**Migration 0013 (`0013_cancel_24h_rule.sql`):**
A verificação é inserida em `cancel_job` imediatamente após `v_is_worker` ser definido,
antes de qualquer outra lógica:

```sql
IF v_job.status = 'confirmed'
   AND v_job.confirmed_date IS NOT NULL
   AND (v_job.confirmed_date - CURRENT_DATE) < 1 THEN
  RAISE EXCEPTION 'O cancelamento requer pelo menos 24h de antecedência.';
END IF;
```

- Aplica-se a cliente e worker simetricamente (antes do branch `IF v_is_worker THEN`)
- Jobs com `confirmed_date IS NULL` (data flexível) estão isentos — igual ao comportamento de `propose_reschedule`
- Jobs `open` nunca têm `confirmed_date`, por isso o check não os afeta

**UI client-side:**
Ambos os ecrãs de detalhe desativam o botão "Cancelar" e mostram uma mensagem
explicativa quando `confirmedDate != null && confirmedDate.difference(DateTime.now()).inHours < 24`:

- `lib/features/jobs/presentation/client_job_detail_screen.dart`
- `lib/features/worker/presentation/worker_my_job_detail_screen.dart`

Mensagem: `'Cancelamento disponível até 24h antes da data confirmada.'`

O UI gate é redundante com o enforcement da BD mas melhora a UX — o utilizador
percebe porque o botão está desativado em vez de receber um erro genérico.

**Estado:** migration 0013 escrita localmente, **NÃO aplicada** à BD. Aplicar via SQL Editor.

## 2026-06-25 — Fase 10: contacto do worker visível em awaiting_confirmation e completed

O contacto do worker (nome + botão WhatsApp) só era mostrado ao cliente no estado
`confirmed`. Nos estados `awaiting_confirmation` e `completed` o card desaparecia,
deixando o cliente sem forma de contactar o prestador exactamente quando mais precisaria
(para questões sobre o trabalho entregue ou para acompanhamento pós-conclusão).

**Causa:** gap de UI — a condição `if (displayJob.status == JobStatus.confirmed)`
limitava o card a um único estado.

**RLS:** já suportava os três estados. A função `client_has_confirmed_job_with_worker`
(usada pela política SELECT de `worker_profiles`) já incluía
`('confirmed', 'awaiting_confirmation', 'completed')` — confirmado via `pg_get_functiondef`
em 2026-06-25. Nenhuma alteração à BD necessária.

**Fix:** `lib/features/jobs/presentation/client_job_detail_screen.dart`
- Extraído `_workerContactCard(workerInfoAsync, theme)` — método privado que envolve
  `workerInfoAsync.when(...)` e devolve o Card de contacto (loading / erro / dados)
- Bloco `confirmed`: refatorado para chamar `_workerContactCard` em vez do Card inline;
  os botões de cancelar/remarcar movidos para fora do `workerInfoAsync.when()` (não
  dependem da info do worker)
- Bloco `awaitingConfirmation`: `_workerContactCard` adicionado no topo da Column,
  acima do card "O prestador marcou como concluído" e botões de confirmação
- Novo bloco `completed`: `_workerContactCard` adicionado como item standalone

**Worker screen (`worker_my_job_detail_screen.dart`):** sem alteração necessária — o
card de contacto do cliente já estava gated em `liveStatus == ProposalStatus.accepted`,
que cobre `confirmed`, `awaiting_confirmation` e `completed` (a proposta mantém-se
`accepted` através de todos estes estados).

## 2026-06-25 — Fase 10: auto-confirmação após 3 dias via pg_cron

A extensão `pg_cron` foi activada manualmente neste projecto em 2026-06-25.

**Nova função `auto_confirm_completed_jobs()`** — SECURITY DEFINER, sem verificação
de `auth.uid()` (actua como o sistema). Segue o padrão estabelecido de "funções batch
internas": a superfície pública `confirm_job_completion` fica intocada; a nova função
é estritamente interna e não deve ser chamada pelo cliente Flutter.

**Cron:** `0 */3 * * *` (cada 3 horas). Registo em `cron.job` via `cron.schedule()`
na migration 0014 — este registo é diferente de DDL normal: só existe após a migration
ser aplicada E o `cron.schedule()` ter corrido com sucesso. Verificar com:
```sql
SELECT * FROM cron.job WHERE jobname = 'auto-confirm-completed-jobs';
```

**Estado:** migration 0014 escrita localmente, **NÃO aplicada** à BD. Aplicar via
SQL Editor. Após aplicar, confirmar via query acima que o job aparece em `cron.job`.