# LocalServices — Project Overview

> Fonte de verdade do projeto. O Claude Code deve ler este ficheiro antes de alterar código.

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
- **Client**: cria pedidos, recebe proposta, aceita/recusa, vê contactos após
  confirmação, cancela até 24h antes, avalia o worker principal.
- **Worker** (prestador/jardineiro): cria perfil, define raio de atuação,
  recebe pedidos no raio, envia proposta, pode pedir ajudantes, avalia ajudantes.

## Fluxo principal
1. Client cria pedido (serviço, localização, data, descrição, fotos opcionais).
2. Pedido é mostrado a workers dentro do raio.
3. Primeiro worker a enviar proposta válida fica associado ao pedido.
4. Client aceita ou recusa. Se recusar, o pedido volta a ficar disponível.
5. Se ninguém responder em 48h → estado "sem resposta".
6. Se o trabalho for grande, o worker principal pede ajudantes; o client
   aprova a equipa ANTES da confirmação final.
7. Após confirmação aparecem contactos (WhatsApp/telefone).
8. Serviço é feito; client avalia o worker principal; worker avalia ajudantes.

## Regras do MVP
- Sem pagamentos na app, sem comissões, sem subscrições, sem chat.
- Pagamento combinado diretamente entre client e worker, fora da app.
- Valor exibido é SEMPRE estimado.
  Mensagem padrão: "Valor estimado. O pagamento é combinado diretamente entre
  cliente e jardineiro."
- Preço/hora não é obrigatório no perfil; pode ser definido por proposta.
- Numa equipa, todos trabalham ao preço/hora definido pelo worker principal.
- Ajudantes veem o contacto do worker principal, não o do client (no MVP).
- Avaliações simples (estrelas + comentário opcional).

## Stack
- App: Flutter + Dart, Material 3, visual verde profissional.
- Backend: Supabase Free (Auth, PostgreSQL, Storage).
- Estado: Riverpod. Navegação: go_router.
- Plataforma: Android primeiro, iOS preparado para depois.

## Workflow de equipa (resumo)
- **UI Playground**: experimentação visual (designer + Figma→Flutter AI), com
  mock data, sem Supabase.
- **Projeto Principal**: app real (Tech Lead/Developer), arquitetura, navegação,
  Supabase, regras de negócio. Só integra código revisto e refatorado.
- Detalhe completo do workflow e papéis dos AI: ver documentos originais do
  projeto (workflow + instruções AI).