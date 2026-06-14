# LocalServices — Estratégia de Negócio

> Documento vivo. Atualizar à medida que se valida e pivota.
> Complementa a documentação técnica em `/docs`.

---

## 1. O problema nº1: desintermediação

Após o primeiro trabalho, cliente e jardineiro têm o contacto um do outro e podem
ignorar a app. A app só sobrevive se oferecer valor contínuo que o WhatsApp não oferece.

**Para o jardineiro:** agenda, rotas, histórico de trabalhos, reputação acumulada,
faturação simplificada, benefícios (seguro, combustível, material). Se a vida
profissional dele vive na app, ele quer os trabalhos registados lá.

**Para o cliente:** histórico da casa, garantia só em trabalhos via app, repetir
pedido com um toque, lembretes sazonais.

**Métrica crítica:** taxa de segundo pedido do mesmo cliente via app. Medir desde o dia 1.

---

## 2. Programa de benefícios para jardineiros

A lógica: benefícios escalam com atividade na app → atividade gera dados e retenção
→ mais tarde, monetização. Acesso aos benefícios ligado a X trabalhos concluídos/mês.

| Benefício | Como | Estado |
|---|---|---|
| Cartão de combustível | Parceria Prio/BP/Galp (programas de frota PME) | Ideia |
| Seguro RC / acidentes | MDS, Fidelidade — cobre trabalhos marcados via app | Ideia |
| Descontos em material | Leroy Merlin, AKI, viveiros, dealers Husqvarna/Stihl | Ideia |
| Faturação simplificada | Parceria InvoiceXpress ou guias recibos verdes | Ideia |
| Formação/certificação | Cursos poda, fitofármacos (obrigatório por lei em PT) | Ideia |

---

## 3. Cold start — como lançar

Marketplaces locais vivem de densidade. Não lançar "em Portugal" — lançar numa zona.

**Zona piloto sugerida:** subúrbios de Lisboa (Cascais/Sintra/Oeiras) ou zona conhecida
da equipa. Só expandir quando a zona tiver pulso (pedidos respondidos em <24h).

**Sequência:**
1. Recrutar 10-15 jardineiros à mão antes de qualquer cliente
   (OLX/CustoJusto, grupos Facebook, lojas de material agrícola)
2. Garantir primeiros pedidos manualmente (amigos, família, grupos de moradores,
   juntas de freguesia)
3. Só expandir para zona seguinte quando a primeira tiver tração

---

## 4. Marketing

**Conteúdo:**
- Antes/depois de cada trabalho (com consentimento) → Instagram/TikTok/Facebook
- Transformações de jardins têm engagement orgânico altíssimo
- Feature "partilhar resultado" no fim do trabalho

**Canais:**
- Grupos de Facebook locais ("Moradores de X", "Compra e venda Y")
- Google My Business + SEO local ("jardineiro em [concelho]")
- Sazonalidade como calendário: primavera, verão, outono, inverno

**Parcerias de aquisição:**
- Imobiliárias (casa nova = jardim abandonado)
- Administradores de condomínios
- Viveiros

**Referral:**
- Clientes que referem → pedidos destacados aos jardineiros
- Jardineiros que trazem colegas → benefícios antecipados

---

## 5. Features prioritárias pós-MVP

| # | Feature | Porquê |
|---|---|---|
| 1 | Avaliações bilaterais | Sem confiança não há marketplace |
| 2 | Push notifications (FCM) | Jardineiros perdem pedidos sem isto |
| 3 | Pedidos recorrentes | Feature de retenção mais valiosa |
| 4 | Perfil público partilhável | Aquisição grátis via partilha |
| 5 | Agenda + trabalhos externos | Retenção do jardineiro |
| 6 | Programa de benefícios (1 parceria piloto) | Diferenciação |
| 7 | Dashboard do jardineiro (ganhos, km, trabalhos) | Sentido de negócio próprio |
| 8 | Orçamento por projeto (não só preço/hora) | Abre trabalhos maiores |

---

## 6. Monetização faseada

**Fase atual (validação):** tudo grátis, sem comissão.

**Caminhos futuros por ordem de fricção:**

1. **Freemium para jardineiros** — grátis até X propostas/mês; Pro (€10-20/mês)
   com propostas ilimitadas, destaque, agenda, rotas, benefícios completos
2. **Margem nos benefícios** — comissões de parcerias (seguros, combustível, material)
3. **Destaque pago** — perfil ou proposta em destaque
4. **Comissão por trabalho** — só se trouxerem pagamentos para a app (complexo)

O modelo mais compatível com pagamentos fora da app é o **freemium**.

---

## 7. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Sazonalidade (inverno) | Expansão para limpeza/reparações quando jardinagem tiver tração |
| No-shows e má qualidade | Avaliações bilaterais + verificação + remoção de maus atores |
| Informalidade fiscal | Ajudar a formalizar (faturação fácil, guias) como valor, não fricção |
| Segurança (estranhos em casas) | Verificação + avaliações + contactos só após confirmação + denúncia |
| Limites Supabase Free | Upgrade (~$25/mês) quando houver tração — não ser apanhado de surpresa |
| Marca genérica "LocalServices" | Considerar nome memorável em português antes do lançamento público |

---

## 8. Verificação e confiança

- **Nível 1:** telefone confirmado (já implementado via Supabase Auth)
- **Nível 2:** documento de identidade (pós-MVP)
- Selo de verificação visível no perfil
- Botão de denúncia
- Avaliações bilaterais com resposta pública

---

## 9. Expansão de categorias

O código usa nomes genéricos (worker, job, service_category) exatamente para isto.
Só expandir depois de jardinagem ter tração numa zona.

Candidatos naturais (mesmos clientes, workers compatíveis):
- Limpeza doméstica / condomínios
- Pequenas reparações (canalizador, eletricista)
- Manutenção (pintura, caiação)

---

## 10. Visão do jardineiro como micro-empresário

O produto mais diferenciador a médio prazo não é a plataforma de pedidos —
é tornar a app a **ferramenta de gestão do negócio** do jardineiro:

- Agenda visual com slots ocupados e livres
- Organizador de rotas diárias (otimização de deslocações)
- Registo de trabalhos externos (não só os da app)
- Dashboard de ganhos e quilómetros
- Faturação integrada
- Benefícios ligados à atividade

Um jardineiro que gere o seu negócio na app não sai da app.
