# LocalServices — Improvements & Future Ideas

> Lista viva de ideias, melhorias e features que NÃO entram na fase atual mas
> ficam registadas para não se perderem. Sempre que aparecer uma ideia boa que
> não cabe no momento, adicionar aqui em vez de esquecer.
>
> Cada item: descrição curta, contexto/porquê, e prioridade subjetiva.

---

## UX e fluxo

### Comparação lado-a-lado de propostas
**Contexto:** Quando o cliente tem 3+ propostas, comparar é difícil scrollando entre cards.
**Ideia:** Vista alternativa em tabela com colunas (worker, preço, horas, data). Toggle entre vista de cards e vista de tabela.
**Prioridade:** Média — só faz sentido após validação do uso real com utilizadores.

### Aceitar 1ª proposta antes de receber mais
**Contexto:** Cliente pode aceitar a primeira proposta que chega sem ver outras melhores.
**Ideia:** Mensagem orientativa "Recomendamos aguardar até 24h para ver mais opções" — orienta sem bloquear.
**Prioridade:** Baixa.

### Badge de "novas propostas" na tab Propostas
**Contexto:** Cliente não sabe se há propostas novas desde a última visualização.
**Ideia:** Badge colorido na tab "Propostas (3)" laranja se houver propostas não vistas, neutro depois de abrir.
**Prioridade:** Média.

### Agrupamento visual de jobs reabertos
**Contexto:** Job cancelado + job novo são entradas separadas no histórico — pode ficar confuso.
**Ideia:** Agrupar visualmente "Cancelado → Reaberto como #..." numa linha.
**Prioridade:** Baixa — só relevante quando o histórico ficar denso.

### Vista de agenda do worker
**Contexto:** Worker com vários jobs agendados precisa de hierarquia temporal.
**Ideia:** Vista alternativa em calendário (semana/mês) com slots ocupados. Divisores "Hoje" / "Esta semana" / "Mais tarde" na lista.
**Prioridade:** Alta — vai ser essencial assim que os workers tiverem 5+ jobs simultâneos.

### Idade visual das propostas pendentes
**Contexto:** Worker não sabe se a proposta foi vista ou ignorada.
**Ideia:** Cor por idade — <24h normal, 24-48h amarelo, >48h cinzento (a expirar). "Há 6h", "Há 2 dias".
**Prioridade:** Média.

---

## Confiança e segurança

### Verificação de identidade nível 2
**Contexto:** Hoje só temos email confirmado. Para serviços em casa de pessoas, confiança é tudo.
**Ideia:** Upload de documento de identidade, verificação manual no início, selo visível no perfil.
**Prioridade:** Alta — pós-MVP imediato.

### Contador de cancelamentos tardios
**Contexto:** Quando alguém cancela com <24h, é registado mas não bloqueado.
**Ideia:** Mostrar "Cumpre compromissos: 95%" no perfil público como sinal de confiança.
**Prioridade:** Média — depende das avaliações estarem prontas.

### Botão de denúncia
**Contexto:** Não há forma de reportar comportamento abusivo.
**Ideia:** Botão "Reportar" no perfil e no detalhe do job. Cria entrada em tabela `reports` para revisão manual.
**Prioridade:** Alta — necessário antes de lançamento público.

### Restrição de "marcar concluído" antes da data
**Contexto:** Hoje o worker pode marcar como concluído mesmo no dia em que enviou a proposta.
**Ideia:** Bloquear ou avisar "Tens a certeza? O trabalho está marcado para o dia X."
**Prioridade:** Média.

---

## Produto

### Pedidos recorrentes
**Contexto:** "Corte de relva quinzenal" é o santo graal — receita previsível para o jardineiro, conveniência para o cliente, uso recorrente da app.
**Ideia:** Ao criar pedido, opção "Repetir" com frequência (semanal, quinzenal, mensal). Cria jobs automaticamente.
**Prioridade:** Muito alta — feature de retenção mais valiosa.

### Perfil público partilhável
**Contexto:** Worker pode usar como cartão de visita fora da app.
**Ideia:** URL público `/p/<worker-slug>` com perfil, fotos, avaliações, serviços, zona. Cada partilha é aquisição grátis.
**Prioridade:** Alta — pós-MVP.

### Orçamento por projeto
**Contexto:** Hoje só temos preço/hora. Trabalhos grandes (relvado novo, sistema de rega) precisam de orçamento fechado.
**Ideia:** Novo tipo de pedido "Orçamento", worker envia proposta com valor total + descrição.
**Prioridade:** Média — abre mercado de trabalhos maiores.

### Dashboard do jardineiro
**Contexto:** "Quanto fiz este mês? Quantos km? Quantos trabalhos?"
**Ideia:** Ecrã com estatísticas mensais — ganhos, km, jobs feitos, % avaliação. Alimenta sentido de "isto é o meu negócio".
**Prioridade:** Alta.

### Trabalhos externos (agenda)
**Contexto:** Botão `+` do worker já está reservado para isto.
**Ideia:** Worker adiciona trabalhos que não vieram pela app à sua agenda. Permite organizar rotas e ter visão completa do dia.
**Prioridade:** Alta.

### Otimização de rotas
**Contexto:** Worker com 5 jobs num dia em sítios diferentes — ordem ótima poupa horas.
**Ideia:** A partir da agenda, sugerir ordem ótima de visitas (algoritmo simples nearest-neighbor ou integração Google Maps).
**Prioridade:** Média.

### Faturação simplificada
**Contexto:** Recibos verdes em Portugal são fricção para o jardineiro.
**Ideia:** Parceria com InvoiceXpress ou similar, ou pelo menos guias práticos dentro da app.
**Prioridade:** Média.

### Categorias além de jardinagem
**Contexto:** O código já está preparado (nomes genéricos).
**Ideia:** Expandir para limpeza, pequenas reparações, manutenção. Só depois de jardinagem ter tração numa zona.
**Prioridade:** Baixa — não expandir antes de validar.


### Mini-chat por proposta (modelo Vinted)
**Contexto:** Negociação entre cliente e worker acontece fora da app (WhatsApp).
Trazer a negociação para dentro da app aumenta confiança e contexto.
**Ideia:** Cada job_proposal tem um chat associado — cliente e worker trocam
mensagens dentro dessa proposta específica. Chat visível no card da proposta
(cliente) e no detalhe do worker. Mensagens em tempo real via Supabase Realtime
(infraestrutura já existe). Após proposta rejeitada/retirada, chat fica em
modo leitura (histórico).
**Modelo de dados:**
- Tabela `proposal_messages`: id, proposal_id, sender_id, content, created_at
- RLS: só client e worker da proposta veem as mensagens
- Realtime: subscrição por proposal_id
**UI:** bottom sheet da proposta tem duas tabs — "Detalhes" e "Chat".
Chat simples com bolhas, campo de texto, enviar. Sem fotos no MVP do chat.
**Porque é relativamente simples:** Realtime já configurado, padrão de
bottom sheet já existe, tabela é simples.
**Prioridade:** Alta — diferenciador forte vs contacto por WhatsApp.
Implementar depois de MVP estável e testado.

### Relações persistentes Worker ↔ Cliente + Jobs recorrentes
**Contexto:** Após o primeiro trabalho concluído, cliente e worker têm uma
relação que vale a pena preservar dentro da app. Hoje perdem-se para o WhatsApp.
**Visão em camadas (implementar por ordem):**

**Camada 1 — Conversa persistente (pós mini-chat de proposta)**
Canal de mensagens direto entre worker e cliente, criado automaticamente após
o primeiro job completed entre os dois. Mantém-se para trabalhos futuros.
Substitui o WhatsApp para comunicação recorrente.

**Camada 2 — Jobs recorrentes**
Dentro da conversa, cliente ativa "repetir trabalho" com frequência
(semanal, quinzenal, mensal). Worker confirma. Jobs seguintes criam-se
automaticamente com proposta automática (mesmo worker, mesmo preço).
Sem passar pelo marketplace — relação direta.

**Camada 3 — Perfil de cliente para o worker**
Worker vê histórico com aquele cliente: trabalhos feitos, morada guardada,
notas pessoais ("tem cão", "portão azul"), ganhos totais.

**Modelo de dados:**
- `worker_client_relationships`: id, worker_id, client_id, status, created_at, notes
- `relationship_messages`: id, relationship_id, sender_id, content, created_at
- `recurring_jobs`: id, relationship_id, service_type_id, frequency, next_date, last_job_id, status

Relação criada automaticamente após primeiro job completed entre os dois.

**Porque é estratégico:**
- Resolve desintermediação (relação vive na app, WhatsApp perde valor)
- Receita recorrente previsível para o worker
- Retém ambos os lados a longo prazo
- Base para programa de benefícios (worker com X recorrentes → nível Pro)
- Dados de uso (frequência, sazonalidade, padrões)

**Dependências:** Mini-chat por proposta deve estar implementado primeiro.
**Prioridade:** Muito Alta — é a feature anti-desintermediação mais importante.

---

## Notificações e comunicação

### Push notifications (FCM)
**Contexto:** Realtime in-app funciona, mas não notifica fora da app.
**Ideia:** Firebase Cloud Messaging + Supabase Edge Function que dispara push quando entra notificação na tabela.
**Prioridade:** Muito alta — pós-MVP imediato. Workers vão perder pedidos sem isto.

### Chat in-app
**Contexto:** Hoje a comunicação é via WhatsApp depois de confirmar.
**Ideia:** Chat simples (Supabase Realtime, tabela `messages`) para negociar antes/durante o trabalho sem sair da app.
**Prioridade:** Média — pós-MVP.

### Lembretes sazonais
**Contexto:** Jardinagem é sazonal — clientes podem esquecer "está na altura de podar".
**Ideia:** Notificações por categoria/serviço em datas específicas. Ex: outubro → "Está na altura de preparar o jardim para o inverno."
**Prioridade:** Média.

### Resumo diário do worker
**Contexto:** Pode ter perdido propostas durante o dia se a app estava fechada.
**Ideia:** Notificação ao fim do dia: "Hoje recebeste 2 propostas, ganhaste €X."
**Prioridade:** Baixa.

---

## Performance e técnico

### Otimizar N+1 query em propostas
**Contexto:** Cada `_ProposalCard` chama `workerNameProvider` separadamente — N round-trips para N propostas.
**Ideia:** Join `worker_profiles` em `fetchPendingProposalsForJob` para trazer nomes na mesma query.
**Prioridade:** Baixa — só relevante quando houver muitas propostas por job.

### Compressão e thumbnails de fotos
**Contexto:** Hoje comprimimos a 1280px no upload. Para thumbs na lista podia ser mais agressivo.
**Ideia:** Gerar thumb 400px no upload (segundo ficheiro) e usar nas listas. Original só no detalhe.
**Prioridade:** Baixa.

### Image transformations do Supabase
**Contexto:** Supabase tem CDN com transforms on-the-fly (resize, quality) — mas no Free Plan tem limites.
**Ideia:** Avaliar quando upgrade fizer sentido.
**Prioridade:** Baixa.

---

## Avaliações (Fase 11 já planeada, mas notas)

### Avaliações bilaterais
Cliente avalia worker, worker avalia cliente. Visíveis no perfil de ambos.

### Resposta a avaliações
Worker pode responder publicamente a uma avaliação ("Obrigado!", ou explicar contexto se for negativa).

### Avaliação só com transação concluída
Só permitir avaliar jobs `completed`. Evita avaliações falsas.

---

## Marca e produto

### Nome próprio em português
**Contexto:** "LocalServices" é genérico e mau para SEO.
**Ideia:** Considerar nome memorável em português antes do lançamento público. Mudar agora é barato, depois é caro.
**Prioridade:** Alta — decisão de marca.

### Logo e identidade visual
**Contexto:** Faltam ativos visuais para a app e marketing.
**Ideia:** Trabalhar com o designer no UI Playground em paralelo à app principal.
**Prioridade:** Alta.

---

## Performance técnica

### Optimizar get_jobs_in_radius para filtrar propostas do worker na BD (✅ implementado)
**Contexto:** Actualmente o Flutter faz 2 queries — uma para jobs no raio,
outra para proposals do worker — e filtra client-side. Pode ser uma query só.
**Solução:** Adicionar parâmetro `p_worker_id` ao RPC e fazer NOT EXISTS
na query SQL para excluir jobs onde o worker já tem proposta pending.
**Prioridade:** Média.

### fetchCompletedWorkerProposals: mover filtro para BD
**Contexto:** A query usa `.range(page * pageSize, ...)` antes de filtrar `job_requests.status == 'completed'` client-side. Páginas podem ter menos items que `pageSize` mesmo quando há mais páginas, levando o utilizador a não carregar mais quando ainda existem dados.
**Solução:** Criar RPC `get_completed_worker_proposals(p_worker_id, p_limit, p_offset)` que filtra por `status = 'accepted'` E `job_requests.status = 'completed'` antes de paginar — garantindo que o `LIMIT` se aplica após o filtro.
**Prioridade:** Média — afeta UX da paginação em workers com histórico longo.

### Paginação nas tabs Por confirmar e Agendados
**Contexto:** Actualmente sem limite. Para workers muito activos com muitas
propostas pendentes, pode ficar lento.
**Solução:** Adicionar paginação igual à tab Concluídos quando houver dados reais
que justifiquem (>50 items por tab).
**Prioridade:** Baixa — resolver quando houver utilizadores reais com volume alto.

---

## Bugs pendentes / melhorias técnicas

### Auto-confirmação de conclusão após 3 dias
**Contexto:** Decisão de planeamento (8E.4): se o cliente não confirmar a
conclusão em 3 dias, o job deve passar automaticamente a `completed` —
protege o worker de clientes que não respondem.
**Estado:** NÃO implementado. Requer scheduled job (Supabase pg_cron ou
Edge Function com cron trigger) que corre periodicamente e procura jobs
em `awaiting_confirmation` há mais de 3 dias, chamando `confirm_job_completion`
automaticamente (ou uma variante sem verificação de `auth.uid() = client_id`).
**Prioridade:** Alta — foi uma decisão de produto explícita para o MVP,
não é polish opcional.

### Worker que cancela não vê o job reaberto
**Contexto:** Quando um worker cancela um job confirmado e o job é reaberto,
o worker que cancelou não devia ver o novo job na sua lista nem conseguir propor.
**Solução:** O cancel_job RPC deve guardar o worker_id do cancelador no novo job
(campo `cancelled_worker_id`). A query fetchJobsInRadius deve excluir jobs onde
`cancelled_worker_id = auth.uid()`.
**Prioridade:** Alta.

---

## Como manter este ficheiro

- Sempre que aparecer uma ideia boa que **não cabe na fase atual**, adicionar aqui.
- Cada item: descrição curta + porquê + prioridade subjetiva.
- Quando uma ideia for implementada, remover daqui e mover para `decisions_log.md`.
- Rever esta lista no fim de cada fase para reavaliar prioridades.