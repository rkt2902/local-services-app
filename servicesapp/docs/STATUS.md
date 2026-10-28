# ProJardim (LocalServices): estado do projeto

> Retrato honesto do que funciona, do que falta e do que depende de configuração.
> **Reescrito a 2026-10-27** contra o `main` (depois do PR #37: Agenda, A11 e avisos).
> A versão anterior deste ficheiro (auditorias de 2026-09-08 a 2026-10-26, com o
> histórico dos itens resolvidos) fica no git; as decisões estão em `decisions_log.md`.
> Referência técnica: `ARCHITECTURE.md`. Dívida e ideias: `improvements.md`.

---

## Resumo

- **Todas as migrations do repo estão aplicadas na BD viva**, da `0001` à `0065`
  (confirmado pelo Henrique a 2026-10-27; a `0050` não existe). Próxima: `0066`.
- Os fluxos principais funcionam de ponta a ponta nos dois papéis. O que falta para ter
  utilizadores reais é sobretudo **configuração** (push, email, domínio, login social,
  Play Store) e alguns pontos de **RGPD** antes de publicar.
- `flutter analyze` a 0 issues e cerca de 560 testes sem rede; o CI corre os dois em
  cada PR.
- Corre em Android, na web (Netlify, deploy à mão) e no iPhone como PWA. iOS nativo
  está preparado mas não publicado (sem Mac nem conta Apple).

---

## O que funciona hoje

### Conta e entrada
- Onboarding de 3 slides (sem splash próprio, só o nativo), login, registo com política
  de senha (8+, maiúscula, número), escolha de papel, setup do jardineiro.
- Recuperação de senha por código de 6 dígitos (bypass só em `kDebugMode`).
- Confirmação de email por código pronta no código; liga-se no Supabase depois do SMTP.
- Login com Google e Facebook pelo OAuth do Supabase (código feito; falta configurar;
  o botão do Facebook está escondido por `--dart-define`).
- Eliminar conta (anonimiza e bloqueia o login, 0049). Ver gaps de RGPD abaixo.
- Termos e Política de Privacidade ligados no registo, no login social e no Perfil.

### Cliente
- Shell com **Início · Pedidos · Alertas · Perfil** (A11). Início com "Precisa de ti",
  pedidos ativos e "Os teus jardineiros".
- Criar pedido em 4 passos (serviço; data, dimensão e morada com sugestões ao escrever
  e GPS; descrição e até 2 fotos; revisão). Editar um pedido aberto (avisa quem já
  propôs).
- Propostas recebidas com hora ou valor total lado a lado, "Recomendada" (melhor média
  com 3+ avaliações), detalhe com "Aceitar por X"; propostas expiradas no fim e
  recusadas pelo servidor.
- Pedido sem propostas: cartão "Ainda sem propostas" com alargar a data, ajustar a
  descrição e mostrar a jardineiros mais longe (até 30 km).
- "Pedir de novo a {nome}" (24h só para esse jardineiro) e pedido pelo cartão público
  `/w/:id`, com o interruptor "Se não puder, mostrar a outros jardineiros".
- Detalhe do pedido num scroll único com a timeline horizontal, equipa visível,
  "Em curso" com o tempo e as fotos de antes e depois, remarcação, cancelamento com
  reabertura, confirmar conclusão (automática em 48h), reportar problema, avaliar.
- Dicas da época por push, com interruptor em Definições.

### Jardineiro
- Shell com **Início · Pedidos · Trabalhos · Perfil** e o sino com o número de não
  lidas nos cabeçalhos (A11).
- Pedidos disponíveis no raio, com filtro de categorias; pedidos diretos fixos no topo
  ("Pedido só para ti · faltam X h", "Não posso desta vez").
- Enviar proposta por hora ou valor total, o que inclui, duração em horas ou dias,
  validade, ajudantes; nota da Agenda ("livre", "apertado", "coincide") com "Ver o dia".
- **Trabalhos** com as tabs **Agenda · Propostas · Histórico**. A Agenda tem Hoje,
  Semana e Mês com trabalhos da app, propostas pendentes a tracejado, remarcações,
  trabalhos de fora da app e indisponibilidades (com repetição e "Só este dia" / "Este
  e os seguintes" / "Todos"); avisa sobreposições e nunca bloqueia. Propostas que
  chocam com a Agenda sobem para o topo.
- No dia: "Iniciar" a partir de 1h antes, fotos de antes, tempo em curso, trabalhos em
  vários dias ("Terminar o dia" / "Começar o dia"), concluir com fotos de depois.
- Ajudantes: pedir equipa, lobby de candidatos com mensagem, aceitar com taxa, mudar
  vagas, retirar ajudante, aprovação do cliente (automática em 24h), fecho no dia do
  trabalho. Do lado do ajudante: descoberta, candidatura com pagamento e horário,
  ecrã do trabalho com WhatsApp do responsável.
- Perfil com cartão comum (A11), números (concluídos, desde quando), plano e uso do mês,
  cartão partilhável com QR, destaques e redes sociais, cartão frota (demo).

### Comum
- Notificações (38 tipos) com navegação por tipo, "Limpar tudo" com "Desfazer" de 6 s
  (0065) e aviso no topo quando chegam com a app aberta (corrigido no PR #37: os avisos
  já não se repetem e voltam a aparecer).
- "As minhas avaliações" (recebidas e dadas) nos dois papéis.
- Erros centralizados em `friendlyError()`; avisos sempre por `AppToast`.
- Design system fechado (tokens, motion, cabeçalhos e tabs comuns) e layout largo em
  tablet e PC.

### Administração
- `/admin` só para contas em `admin_users`, com segundo fator (TOTP). Visão geral,
  jardineiros com pesquisa e filtro por plano, ficha com números e "Mudar plano"
  (Grátis, Pro, Pro+). Funciona desde 23/10.
- Plano Grátis com limite de 5 trabalhos aceites por mês (a BD recusa propostas novas
  depois disso). Contrato e pagamento fora da app; a app não mostra preços.
- **O que cada plano dá (decidido a 2026-10-28):** Grátis tem 5 trabalhos por mês,
  Agenda e o cartão como imagem e link. Pro tem trabalhos sem limite, selo Pro nas
  propostas, no cartão público e no Perfil, o cartão em PDF e o painel de ganhos. Pro+
  tem tudo isso, selo Pro+ e os Benefícios (cartão frota e parceiros). Regras num só
  sítio: `worker_plan_features.dart`. A folha "Plano" mostra a comparação.
- **Cartão partilhável** (`/worker/card`): cartão desenhado com QR, partilhar como
  imagem, guardar em PDF (Pro), enviar ou copiar o link.
- **Painel de ganhos** (`/worker/earnings`, Pro): total do mês, horas registadas, o que
  está por confirmar, barras dos últimos 6 meses e a lista dos trabalhos (responsável e
  ajudante). Precisa da `0067` (NÃO aplicada).
- Visitas ao cartão e clientes trazidos por cada jardineiro: só no SQL Editor
  (`worker_card_funnel`).

---

## Falta configurar (só o Henrique, passos em `SETUP.md`)

| O quê | Onde | Efeito enquanto não está |
|---|---|---|
| Firebase e push FCM | `SETUP.md` passo 4, `push_notifications.md` | Avisos só com a app aberta. **É o bloqueador nº 1 para jardineiros reais** |
| SMTP (Brevo), template de recuperação com `{{ .Token }}`, confirmação de email | passo 3 | Emails pelo SMTP de teste do Supabase, com limite baixo |
| Login com Google e Facebook | passo 7 | Os botões dão erro |
| Domínio real e `APP_PUBLIC_URL` | passo 5 | Nas apps o link do cartão aponta para `projardim.pt` (placeholder); na web usa o próprio site |
| App links (abrir `/w/...` na app instalada) | fim do `SETUP.md` | Só depois do domínio |
| Play Store (conta, upload key, ficha, Data safety) | `projardim/play-store/checklist-lancamento.md` nas notas do projeto | Sem publicação |
| Deploy da web | GitHub Actions > Deploy web (à mão desde 26/10) | O site fica na última versão publicada |

---

## Gaps conhecidos (sem spin)

### Antes de publicar
- **RGPD: eliminar conta não apaga tudo.** `delete_my_account` (0049) não limpa
  destaques e redes sociais, visitas ao cartão, preferências, plano, entradas da Agenda
  (com nomes e telefones de terceiros), moradas e fotos de pedidos antigos, nem os
  ficheiros do Storage. A Política de Privacidade não menciona o registo de visitas ao
  cartão, as dicas da época, Photon/OSM e o geocoder nativo. Detalhe em
  `improvements.md` (revisão de 2026-10-27).
- **Política de Privacidade da Agenda:** as secções 3.7 e 8 foram atualizadas no
  rascunho, para publicar no Google Doc quando a Agenda saísse. A Agenda já está no
  `main`; falta publicar essa versão e atualizar o `.docx`.
- Termos e Política são rascunhos sem dados da empresa e sem revisão jurídica.

### Produto por fazer
- Restos do A11: cartão "Agora" com Iniciar e Mapa no Início do jardineiro, cartões
  J4/C5, linha "Serviço · data" nas notificações.
- A12 (fluxo do pedido em 3 vistas e stepper Pedido · Proposta · Equipa · No dia ·
  Feito): recebido a 27/10, por integrar.
- Painel `/admin` fases 2 e 3 (mapa, pedidos, moderação, funil, CSV, avisos a grupos).
- "Ver o local primeiro" (visita paga antes do orçamento): fase 2.
- Cartão frota é uma demo para o pitch: dados fictícios, ativação manual por SQL, sem
  parceiro.

### Técnico
- Código de compatibilidade com migrations por aplicar ainda está no código (inofensivo,
  ver `ARCHITECTURE.md` secção 16, ponto 9).
- Ecrãs ligados ao Supabase não têm testes (só as vistas puras e a lógica).
- Na web não há OCR do cartão frota nem push.
- Botões de remover foto (26 px) e de contar ajudantes (36 px) abaixo dos 48 px.
- Seed antigo de `service_types` por confirmar com um dump `--data-only` (pouco
  relevante desde o catálogo da 0045) e o nome do trigger `on_job_created` diferente do
  ficheiro (cosmético). Ver `ARCHITECTURE.md` secção 16.

---

## Segurança

- Identidade sempre por `auth.uid()` dentro das RPCs (classe corrigida na 0032 e na
  0044); escritas de negócio só por RPC (0042); cada função nova faz `REVOKE ... FROM
  PUBLIC, anon`.
- Review de 2026-10-16 (0042): `cancel_job` e `reject_proposal` sem autorização,
  `create_user_profile` aberta a anon, propostas e avaliações forjadas por INSERT
  direto, cartão frota auto-ativável. Tudo fechado e aplicado.
- Morada exata do pedido só depois da proposta aceite (0043); antes, a localidade e
  coordenadas arredondadas a cerca de 1 km.
- Painel `/admin`: `admin_users` + aal2 verificados dentro de cada RPC `admin_*`; registo
  das ações em `admin_actions`.
- A app só mostra fotos de perfil do Storage do próprio projeto.
- Tabelas de tracking (`worker_card_visits`, `client_referrals`), planos e admin com RLS
  ligado e sem policies: só RPCs e SQL Editor.

---

## O que testar agora que tudo está aplicado

As últimas migrations (0058 a 0065) entraram juntas, por isso vale uma volta completa:

1. Jardineiro: enviar uma proposta por hora e outra a valor total com validade; o
   cliente vê as duas lado a lado e aceita uma.
2. Trabalho em vários dias: Iniciar, "Terminar o dia", "Começar o dia", concluir com
   fotos; o cliente confirma.
3. "Pedir de novo" a um jardineiro de um trabalho feito a valor fechado: o jardineiro
   vê "Já trabalhaste com..." com o total (0063).
4. Pedido pelo cartão `/w/:id` sem sessão: registo, pedido com o interruptor desligado,
   recusa, pedido parado, "Mostrar a todos".
5. Agenda: adicionar um trabalho de fora da app semanal, "Só este dia", "Este e os
   seguintes", marcar feito e desfazer, cancelar e repor, indisponibilidade e "Já estou
   livre"; uma proposta que choca sobe na tab Propostas.
6. Notificações: "Limpar tudo" e "Desfazer" nos dois papéis; o sino do jardineiro
   desce para 0; uma notificação nova com a app aberta aparece uma vez no topo.
7. Perfil do jardineiro: números de concluídos e "Na ProJardim" preenchidos (0065).
8. Plano Grátis: com 5 trabalhos aceites no mês, a 6.ª proposta dá o aviso do limite.
9. Pedido sem propostas, sem esperar 24h (entre as 8h e as 21h):
   `update job_requests set visible_to_all_at = now() - interval '25 hours' where id = '<id>';`
   e `select process_open_job_followups();`. O cliente vê o cartão "Ainda sem
   propostas".
