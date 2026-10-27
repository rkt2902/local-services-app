# LocalServices — Project Overview

> Visão de produto do projeto (revista a 2026-10-27). A referência técnica é
> `ARCHITECTURE.md`; o estado atual é `STATUS.md`. Marca na UI: ProJardim.

## O que é
App mobile (Flutter + Supabase, Material 3, Android primeiro) que funciona como
marketplace genérico de serviços locais. O MVP lança focado em jardinagem, mas
o código e a base de dados são genéricos para suportar futuras categorias
(limpeza, manutenção, reparações, etc.).

## Princípio central
- **UI** fala em jardineiros / jardinagem (português).
- **Código e base de dados** usam nomes genéricos: `client`, `worker`, `job`,
  `proposal`, `service_category`, `service_type`, `help_request`.
- Categorias e serviços vêm SEMPRE da base de dados, nunca hardcoded.

## Tipos de utilizador
- **Client**: cria pedidos, recebe propostas, aceita/recusa, vê contactos após
  confirmação, cancela até 24h antes, avalia o worker principal. Pode pedir de novo a
  um jardineiro anterior ou pedir diretamente pelo cartão público dele.
- **Worker** (prestador/jardineiro): cria perfil, define raio de atuação,
  recebe pedidos no raio, envia propostas, pode pedir ajudantes, avalia cliente e
  ajudantes, tem Agenda (trabalhos da app e de fora dela) e um plano (Grátis, Pro, Pro+).

## Fluxo principal
1. Client cria pedido (serviço, localização, data, descrição, fotos opcionais).
2. Pedido é mostrado a workers dentro do raio.
3. Vários workers enviam propostas (por hora ou valor total, com validade).
4. Client aceita uma (as outras são recusadas) ou recusa propostas individuais.
5. Sem propostas: lembretes aos jardineiros e, às 24h, o pedido chega mais longe; no
   fim do prazo → estado "sem resposta".
6. Se o trabalho for grande, o worker principal pede ajudantes; o client
   aprova a equipa ANTES da confirmação final.
7. Após confirmação aparecem contactos (WhatsApp/telefone).
8. O worker inicia o trabalho no dia, marca como concluído; o client confirma (ou é
   confirmado sozinho em 48h).
9. Avaliações: client avalia o worker principal; worker avalia cliente e ajudantes.

## Regras do MVP
- Sem pagamentos na app, sem comissões, sem chat. Contacto só por WhatsApp.
- Pagamento combinado diretamente entre client e worker, fora da app.
- O cliente não paga nada. A receita vem dos planos dos jardineiros (Grátis com 5
  trabalhos aceites por mês, Pro, Pro+ com benefícios de parceiros), contratados e pagos
  fora da app e ativados no painel `/admin`. A app não mostra preços dos planos.
- Valor exibido é SEMPRE estimado.
  Mensagem padrão: "Valor estimado. O pagamento é combinado diretamente entre
  cliente e jardineiro."
- Preço não está no perfil: o jardineiro escolhe em cada proposta entre preço por hora
  e valor total.
- Numa equipa, os ajudantes recebem a taxa acordada com o worker principal.
- Ajudantes veem o contacto do worker principal (WhatsApp), não o do client.
- Avaliações simples (estrelas + comentário opcional).
- Máximo 2 fotos por pedido. Fotos são comprimidas antes do upload (máx. 800px, qualidade 60%).


## Stack
- App: Flutter + Dart, Material 3, visual verde profissional.
- Backend: Supabase Free (Auth, PostgreSQL, Storage).
- Estado: Riverpod. Navegação: go_router.
- Plataforma: Android primeiro; web (Netlify) e PWA para iPhone; iOS nativo preparado.

## Workflow de equipa (resumo)
- **UI Playground**: experimentação visual (designer + Figma→Flutter AI), com
  mock data, sem Supabase.
- **Projeto Principal**: app real (Tech Lead/Developer), arquitetura, navegação,
  Supabase, regras de negócio. Só integra código revisto e refatorado.
- Detalhe completo do workflow e papéis dos AI: ver documentos originais do
  projeto (workflow + instruções AI).
  