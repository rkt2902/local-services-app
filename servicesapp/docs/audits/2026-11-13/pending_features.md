# Funcionalidades pendentes, adiadas ou esquecidas (13/11/2026)

Pesquisa em `lib/` e `supabase/` por TODO, FIXME, HACK, TEMP, STUB, mock, placeholder, "Em breve", `UnimplementedError`, botões com `onPressed: null` e rotas sem entrada; comparação com `STATUS.md`, `improvements.md`, `decisions_log.md`, a memória do projeto e as 13 funcionalidades futuras da lista do pedido.

## O que a pesquisa encontrou no código

| Achado | Onde | Leitura |
|---|---|---|
| 1 TODO | `job_location_picker.dart:371` `TODO(mapa-estilizado)` | Decisão tomada (mapa sem API paga); o resto do bloco tem o User-Agent de exemplo (AUD-12) |
| Domínio placeholder | `app_links.dart:17` `https://projardim.pt` | AUD-10 |
| "Em breve" | `worker_edit_profile_screen.dart:327` | Destaques e redes sociais bloqueados por plano; texto enganador se o plano nunca o der (P3) |
| `onPressed: null` | `client_job_detail_screen.dart:1071` | Só durante o carregamento de "Pedir de novo" (correto) |
| Cartão frota | `features/fleet_card` | Demo sem parceiro (AUD-28) |
| Compatibilidade com migrations antigas | `ARCHITECTURE.md` secção 16, ponto 9 | Código morto inofensivo (`PGRST202`, `WorkerPlan.unavailable`) |
| `features/proposals/presentation/` vazia | | Convenção, não falta nada |
| Nenhum `UnimplementedError`, mock de dados ou flag temporária escondida | | |

Rotas: as 52 do `app_router.dart` têm entrada na app ou são de propósito (admin, `/w/:id`, OAuth). As de Mensagens foram apagadas a 18/10.

## As 13 funcionalidades futuras da lista

| # | Funcionalidade | Estado real | Alinhada com o produto | Antes do lançamento? | Depende de | Esforço | Risco de adiar |
|---|---|---|---|---|---|---|---|
| 1 | Perfil público visitável do jardineiro | **Implementada**: `/w/:workerId`, sem sessão, nome, foto, zona, serviços, destaques, redes, nota | Sim | Já existe | Domínio (AUD-10) para os links nas apps | 0 | Nenhum |
| 2 | Avaliações visíveis no perfil | **Parcial**: média e a última avaliação de 4 ou 5 estrelas no cartão; lista completa só em fluxos com sessão (`get_ratings_with_rater_identity`) | Sim | Não | 1 | S | Baixo |
| 3 | Feed de descoberta de profissionais | **Só documentação** (removido "Profissionais perto de si" da home a 16/10) | Duvidoso: o modelo é o cliente publicar e os jardineiros proporem | Não | 1, 2, volume de jardineiros | L | Nenhum no lançamento |
| 4 | Links públicos partilháveis | **Implementada** (link, QR, imagem, PDF no Pro), com o domínio por resolver | Sim | Sim, o domínio (AUD-10) | Domínio, app links | S | Alto se os QR forem impressos com o domínio errado |
| 5 | Mini-chat por proposta | **Não existe** (rotas apagadas a 18/10) | **Não**: regra "contacto só por WhatsApp" | Não | Moderação, RGPD, push | XL | Nenhum |
| 6 | Trabalhos recorrentes | **Não existe** para o cliente; a Agenda do jardineiro tem séries para trabalhos de fora da app; "Pedir de novo" cobre a repetição manual | Sim, mais tarde | Não | Pedido direto (feito) | L | Baixo |
| 7 | Área pessoal / configurações | **Implementada**: Perfil nos dois papéis, editar perfil, Definições do cliente (dicas da época), eliminar conta, sobre | Sim | Já existe | | 0 | Nenhum |
| 8 | Os meus cartões | **Implementada**: cartão partilhável e cartão frota (demo) | Sim | Esconder o cartão frota se não houver parceiro (AUD-28) | Parceiro | S | Médio (prometer um benefício que não existe) |
| 9 | Suporte / contacto | **Implementada**: "Contacto e suporte" com email (Gmail) | Sim | Sim, email com domínio próprio é recomendado | Domínio | S | Baixo |
| 10 | Redesign da timeline | **Implementada**: `StatusTimelineHorizontal` e, desde o A12, `JobFlowStepper` em 4 ecrãs. O `STATUS.md` ainda diz "por integrar" (AUD-19) | Sim | Já existe | | 0 | Nenhum |
| 11 | Melhorias de navegação | **Feito em boa parte**: A11 (shells, sino), fallback de voltar, transições. Por fazer: cartão "Agora" no Início do jardineiro, cartões J4/C5 | Sim | Não | | M | Baixo |
| 12 | Refinamento Material 3 | **Feito em boa parte**: tema M3, tokens, 0 cores soltas fora de `core/theme`. Por fazer: botões abaixo de 48 px (AUD-26) | Sim | Só a acessibilidade | | S | Baixo |
| 13 | Outras integrações a meio | Push FCM (código feito, configuração por confirmar), Login Google e Facebook (código feito, configuração por fazer), painel de ganhos (feito, Pro), visita paga (fase 2), admin fases 2 e 3 | | Push e Google, sim | Firebase, Google Cloud | M | Alto (push) |

## Classificação para o lançamento

### Obrigatórias para lançamento
- Push FCM configurado e testado (AUD-01).
- Email real: SMTP, recuperação e confirmação (AUD-02).
- Login Google configurado **ou** escondido (AUD-06).
- Domínio para links e QR (AUD-10).
- Termos e Política finais com responsável (AUD-09).
- Monitorização de erros (AUD-07).

### Recomendadas antes do lançamento
- Esconder o cartão frota enquanto não houver parceiro (AUD-28).
- Fonte empacotada (AUD-17).
- Testes da BD no CI (AUD-16).
- Email de suporte com domínio próprio.

### Podem entrar na versão 1.1
- Lista completa de avaliações no cartão público.
- Cartão "Agora" no Início do jardineiro, cartões J4/C5, linha "Serviço · data" nas notificações.
- Fotos de pedidos privadas com URLs assinadas (AUD-14), se for essa a decisão.
- iOS na App Store (AUD-15) com Sign in with Apple.
- Painel admin fase 2 (pedidos, moderação de relatos).

### Podem entrar mais tarde
- "Ver o local primeiro" (visita paga).
- Trabalhos recorrentes do cliente.
- Feed de descoberta, se houver jardineiros suficientes.
- Verificação de identidade ligada ao Pro.
- Outras categorias (ProLimpeza, ProReparações): o schema e o código já são genéricos (`service_categories`/`service_types`, nomes `worker`/`client`/`job`), o que falta é a marca por app (nome, cores, textos "jardineiro" na UI) e um `--dart-define` de marca.

### Não recomendadas / obsoletas
- Mini-chat dentro da app (contraria a regra do WhatsApp e traz moderação e RGPD).
- Filtros "prazo" e "tamanho" nos pedidos disponíveis (já removidos).
- Código de compatibilidade com migrations antigas (limpar numa manutenção).
