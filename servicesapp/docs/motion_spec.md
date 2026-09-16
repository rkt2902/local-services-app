# ProJardim · Especificação de Motion

v1 · Setembro 2026 · Base: Material 3 Motion
Referência visual: ProJardim Motion e ProJardim Flows

Princípio constante: **movimento com propósito** — cada animação explica uma mudança de estado ou de ecrã. Nada é decorativo. Se uma animação não ajuda a compreender o que aconteceu, não deve existir.

---

## 1 · Tokens de duração

| Token | Valor | Onde se usa |
|---|---|---|
| `duration.instant` | 100 ms | Feedback de toque: press-scale de botões, chips, itens de lista |
| `duration.fast` | 200 ms | Mudança de estado: badge a trocar de cor, chip a selecionar, toggle, expandir secção |
| `duration.screen` | 300 ms | Transição entre ecrãs (todas as rotas) |
| `duration.sheet` | 450 ms | Bottom sheets e diálogos modais (abrir e fechar) |
| `duration.stagger` | 120 ms | Intervalo entre itens numa entrada em cascata (delay incremental, não uma duração) |

## 2 · Tokens de curva

| Token | cubic-bezier | Quando |
|---|---|---|
| `easing.standard` | (0.2, 0, 0, 1) | Mudanças de estado dentro do mesmo ecrã |
| `easing.emphasized` | (0.2, 0.7, 0.3, 1) | Entradas e saídas de ecrã; sheets |
| `easing.enter` | ease-out | Elemento a aparecer (rápido no início, assenta suave) |
| `easing.exit` | ease-in | Elemento a desaparecer |
| `easing.reward` | (0.2, 0.8, 0.3, 1.2) | Único caso com overshoot: check de sucesso e estrelas de avaliação |

## 3 · Regras por componente

| Componente | Comportamento | Tokens |
|---|---|---|
| Botão primário | Ripple M3 a partir do ponto de toque + scale(0.96) enquanto premido | instant · standard |
| FAB "+" | scale(0.88) ao premir, volta com bounce mínimo | instant · standard |
| Chip / filtro | Cor de fundo e borda cruzam para o estado selecionado; sem movimento de posição | fast · standard |
| Toggle | Bolinha desliza e o track muda de cor em simultâneo | fast · standard |
| Secção colapsável (perfil worker) | Altura anima de 0 ao conteúdo; chevron roda 180°. Conteúdo faz fade-in com 60 ms de atraso para não "esticar" visualmente | fast · emphasized |
| Badge de estado | Ao mudar de estado: cross-fade da cor de fundo e do texto. Nunca aparece/desaparece abruptamente | fast · standard |
| Lista de cards (propostas, pedidos, candidaturas) | Entrada em cascata: cada card sobe 18 px e faz fade-in, com atraso incremental. Máximo 6 itens animados — do 7.º em diante entram sem atraso, senão a lista parece lenta | fast · emphasized + stagger |
| Timeline · nó atual | **Animação-assinatura.** Anel verde pulsa em loop infinito (1.8 s, ease-out): box-shadow expande de 0 a 12 px e desvanece. É o único loop infinito permitido na app | 1.8s loop · ease-out |
| Timeline · avanço | Quando o estado avança: o trilho preenche-se da posição antiga para a nova (1 s), e só depois o novo nó aparece com pop | 1s · ease-out |
| Check de sucesso | Círculo faz pop com overshoot; o ícone de check entra 150 ms depois. Texto abaixo sobe com fade (+200 ms) | sheet · reward |
| Estrelas de avaliação | Ao submeter, as 5 estrelas surgem uma a uma (100 ms de intervalo) com pop. Ao tocar para escolher: pop individual só na estrela tocada | fast · reward |
| Skeleton de loading | Shimmer horizontal em loop (1.3 s, linear). Usar sempre em vez de spinner em listas e formulários — o spinner fica reservado para ações dentro de um botão | 1.3s loop · linear |
| Bottom nav | Ícone do item ativo cruza de outline para preenchido; cor e peso do label animam em simultâneo | fast · standard |
| Notificação não-lida | Ponto verde entra com fade. Ao ser lida, o fundo tonal desvanece para branco ao longo de 200 ms — a mudança é perceptível mas não brusca | fast · standard |

## 4 · Transições entre ecrãs

Três tipos, escolhidos pela relação entre origem e destino — nunca por gosto. Todos a `duration.screen` com `easing.emphasized`.

| Tipo | Usar quando | Exemplos concretos nas rotas |
|---|---|---|
| **Shared-axis (X)** — desliza lateral | Passos de um mesmo fluxo, com sentido de "avançar / recuar" | Wizard de criar pedido (serviço → data → descrição); passos de registo; setup de perfil worker; notificação → ecrã de destino |
| **Container transform** — o card cresce | Abrir um item de uma lista, mantendo o contexto de onde veio | Card de pedido → detalhe do pedido; card de proposta → detalhe da proposta; oportunidade → detalhe; candidato → sheet de aceitar |
| **Fade-through** — fade + escala leve | Destinos sem relação direta — não há direção a comunicar | Trocar de tab na bottom nav; trocar entre "Ativos"/"Histórico"; "Descobrir"/"As minhas candidaturas" |

### Deep-link de notificação — caso especial

Ao tocar numa notificação: shared-axis para o ecrã de destino, e o item específico que originou o alerta realça durante 1,3 s (fundo âmbar claro que desvanece para branco). É o "cheguei aqui" — sem isto o utilizador aterra num ecrã e não sabe qual dos itens era o da notificação.

## 5 · Regras de exceção

| Animar sempre | Nunca animar |
|---|---|
| Mudanças de estado de um pedido ou trabalho | Parallax ou movimento ligado ao scroll |
| Feedback de toque em qualquer elemento acionável | Confetti, partículas, celebrações grandes |
| Transições entre ecrãs | Ilustrações em movimento contínuo |
| Entrada de listas carregadas de rede | Loops infinitos — exceto o nó atual da timeline e o shimmer |
| Momentos de confirmação (aceitar, concluir, avaliar) | Qualquer coisa acima de 500 ms fora de sheets |
| | Reordenar listas sozinhas enquanto o utilizador lê |

### Acessibilidade — `prefers-reduced-motion`

Quando o utilizador ativa a redução de movimento no sistema:

- **Desligar por completo**: pulse da timeline, shimmer, staggers, pops de recompensa.
- **Substituir por cross-fade de 100 ms**: todas as transições de ecrã.
- **Manter**: mudanças de cor de estado (são informação, não decoração) e o realce do deep-link — mas estáticos, sem fade progressivo.

> **Nota importante para a app:** uma parte do público-alvo são jardineiros com menos destreza no telemóvel. Nenhuma informação pode existir apenas em movimento — se algo pulsa para chamar atenção, tem de ter também cor e texto que digam o mesmo.

## 6 · Checklist de implementação

Ao construir um ecrã novo, verificar por esta ordem:

1. As durações e curvas vêm de constantes partilhadas, não de números soltos no widget.
2. O ecrã tem estado de loading em skeleton, não spinner a ocupar o ecrã todo.
3. A transição de entrada corresponde à relação com o ecrã anterior (§4).
4. Todo o elemento acionável tem feedback de toque.
5. Se há lista de rede, tem entrada em cascata limitada a 6 itens.
6. Se há mudança de estado, o badge cruza a cor em vez de trocar de repente.
7. `prefers-reduced-motion` está tratado.
8. Nenhuma informação depende só de movimento.