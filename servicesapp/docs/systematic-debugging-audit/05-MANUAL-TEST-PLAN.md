# 05. Plano de testes manuais

Total: **56 testes manuais** (P0: 7, P1: 26, P2: 17, P3: 6). Todos estão pendentes: nenhum foi executado nesta auditoria. Os P0 são obrigatórios antes de publicar.

Antes de começar:

1. Usar contas de teste (nunca contas de clientes reais). Sugestão: 2 clientes, 3 jardineiros, 1 admin.
2. Aplicar primeiro as migrations 0067 a 0073 (por ordem) se o teste usar uma funcionalidade nova; o teste diz quando.
3. Para cada teste, guardar a evidência pedida numa pasta com o número do teste (TM-0xx).
4. Se o resultado for diferente do esperado, anotar o que apareceu, a hora e o telemóvel usado.

## Índice por prioridade

| Teste | Prioridade | Fluxos |
|---|---|---|
| [TM-012](#tm-012) | P0 | FLOW-011 |
| [TM-016](#tm-016) | P0 | FLOW-020 |
| [TM-021](#tm-021) | P0 | FLOW-025, FLOW-026, FLOW-043 |
| [TM-034](#tm-034) | P0 | FLOW-042 |
| [TM-036](#tm-036) | P0 | FLOW-046, FLOW-048 |
| [TM-046](#tm-046) | P0 | FLOW-073, FLOW-099 |
| [TM-054](#tm-054) | P0 | FLOW-090, FLOW-091, FLOW-096 |
| [TM-002](#tm-002) | P1 | FLOW-002 |
| [TM-003](#tm-003) | P1 | FLOW-002, FLOW-003 |
| [TM-004](#tm-004) | P1 | FLOW-004 |
| [TM-006](#tm-006) | P1 | FLOW-005 |
| [TM-008](#tm-008) | P1 | FLOW-007 |
| [TM-009](#tm-009) | P1 | FLOW-008 |
| [TM-010](#tm-010) | P1 | FLOW-009 |
| [TM-022](#tm-022) | P1 | FLOW-027, FLOW-038 |
| [TM-023](#tm-023) | P1 | FLOW-028 |
| [TM-025](#tm-025) | P1 | FLOW-030, FLOW-049, FLOW-074 |
| [TM-026](#tm-026) | P1 | FLOW-031 |
| [TM-028](#tm-028) | P1 | FLOW-033, FLOW-035, FLOW-044, FLOW-093 |
| [TM-029](#tm-029) | P1 | FLOW-034 |
| [TM-030](#tm-030) | P1 | FLOW-036 |
| [TM-031](#tm-031) | P1 | FLOW-037, FLOW-050..052, FLOW-095 |
| [TM-033](#tm-033) | P1 | FLOW-040, FLOW-041 |
| [TM-035](#tm-035) | P1 | FLOW-045, FLOW-060 |
| [TM-037](#tm-037) | P1 | FLOW-047 |
| [TM-040](#tm-040) | P1 | FLOW-056, FLOW-057 |
| [TM-042](#tm-042) | P1 | FLOW-059, FLOW-092, FLOW-098 |
| [TM-044](#tm-044) | P1 | FLOW-071, FLOW-075 |
| [TM-051](#tm-051) | P1 | FLOW-078 |
| [TM-052](#tm-052) | P1 | FLOW-079 |
| [TM-053](#tm-053) | P1 | FLOW-080..082 |
| [TM-055](#tm-055) | P1 | FLOW-100 |
| [TM-056](#tm-056) | P1 | FLOW-101 |
| [TM-005](#tm-005) | P2 | FLOW-004, FLOW-011 |
| [TM-007](#tm-007) | P2 | FLOW-006 |
| [TM-011](#tm-011) | P2 | FLOW-010, FLOW-073 |
| [TM-013](#tm-013) | P2 | FLOW-012, FLOW-077 |
| [TM-014](#tm-014) | P2 | FLOW-013 |
| [TM-015](#tm-015) | P2 | FLOW-014 |
| [TM-017](#tm-017) | P2 | FLOW-020, FLOW-021 |
| [TM-018](#tm-018) | P2 | FLOW-022 |
| [TM-020](#tm-020) | P2 | FLOW-024 |
| [TM-024](#tm-024) | P2 | FLOW-029 |
| [TM-027](#tm-027) | P2 | FLOW-032 |
| [TM-038](#tm-038) | P2 | FLOW-053, FLOW-054 |
| [TM-039](#tm-039) | P2 | FLOW-055 |
| [TM-043](#tm-043) | P2 | FLOW-070 |
| [TM-047](#tm-047) | P2 | FLOW-073 |
| [TM-048](#tm-048) | P2 | FLOW-075 |
| [TM-050](#tm-050) | P2 | FLOW-077 |
| [TM-001](#tm-001) | P3 | FLOW-001 |
| [TM-019](#tm-019) | P3 | FLOW-023, FLOW-094 |
| [TM-032](#tm-032) | P3 | FLOW-039, FLOW-097 |
| [TM-041](#tm-041) | P3 | FLOW-058 |
| [TM-045](#tm-045) | P3 | FLOW-072 |
| [TM-049](#tm-049) | P3 | FLOW-076 |

## TM-001

- **Fluxo relacionado:** FLOW-001
- **Prioridade:** P3
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada e browser
- **Pré-condições:** App acabada de instalar
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Instalar e abrir a app. 2. Ver os 3 slides, passando com o dedo. 3. Tocar no botão final. 4. Fechar a app e voltar a abrir.
- **Resultado esperado:** Os slides aparecem só da primeira vez; depois abre no ecrã de entrada.
- **Evidência a recolher:** Captura de ecrã de cada slide e do arranque seguinte
- **Porque não foi automatizado:** Precisa da app real a arrancar a frio
- **Impacto de não executar:** Primeira impressão errada; ficar preso no onboarding

## TM-002

- **Fluxo relacionado:** FLOW-002
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Sem sessão
- **Dados de teste:** Email novo de teste; senha 'Teste123'
- **Passos exatos:** 1. Tocar em Criar conta. 2. Preencher nome, telemóvel e email. 3. Escrever a senha 'teste' e ver o aviso. 4. Escrever 'Teste123'. 5. Aceitar os termos. 6. Criar conta. 7. Repetir com o mesmo email.
- **Resultado esperado:** Senha fraca é recusada com texto claro; conta nova segue em frente; email repetido dá 'Este email já está registado'.
- **Evidência a recolher:** Capturas de cada mensagem
- **Porque não foi automatizado:** O Supabase Auth não corre localmente
- **Impacto de não executar:** Ninguém consegue registar-se

## TM-003

- **Fluxo relacionado:** FLOW-002, FLOW-003
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes) com 'Confirm email' ligado
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** SMTP configurado
- **Dados de teste:** Email real de teste
- **Passos exatos:** 1. Criar conta. 2. Abrir o email e copiar o código de 6 dígitos. 3. Escrever o código. 4. Testar também um código errado e o botão de reenviar.
- **Resultado esperado:** Código certo entra; errado mostra erro; reenvio chega em menos de 1 minuto e não vai para spam.
- **Evidência a recolher:** Captura do email recebido e dos ecrãs
- **Porque não foi automatizado:** Depende de email real
- **Impacto de não executar:** Contas presas por confirmar

## TM-004

- **Fluxo relacionado:** FLOW-004
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada e browser
- **Pré-condições:** Conta de teste
- **Dados de teste:** Conta cliente e conta jardineiro
- **Passos exatos:** 1. Entrar com a senha errada. 2. Entrar com a certa. 3. Confirmar que abre o Início do papel certo. 4. Fechar e abrir a app: continua com sessão.
- **Resultado esperado:** Erro claro com a senha errada; sessão mantida ao reabrir.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Auth real
- **Impacto de não executar:** Login partido bloqueia tudo

## TM-005

- **Fluxo relacionado:** FLOW-004, FLOW-011
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Conta eliminada no TM-012
- **Dados de teste:** Email da conta eliminada
- **Passos exatos:** 1. Tentar entrar com a conta eliminada. 2. Tentar registar de novo com o mesmo email.
- **Resultado esperado:** Login recusado; registo recusado durante 90 dias.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Auth real e trigger em auth.users
- **Impacto de não executar:** Conta eliminada volta a entrar

## TM-006

- **Fluxo relacionado:** FLOW-005
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes) com Google e Facebook configurados
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada e iPhone (se houver app iOS)
- **Pré-condições:** Contas Google e Facebook de teste
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Tocar em Continuar com Google. 2. Escolher a conta. 3. Confirmar que volta à app (não fica no browser). 4. Escolher papel e telemóvel. 5. Ver a foto no perfil. 6. Repetir com Facebook. 7. Repetir na web.
- **Resultado esperado:** Volta à app com sessão; pede telemóvel; foto copiada.
- **Evidência a recolher:** Vídeo curto do fluxo
- **Porque não foi automatizado:** OAuth e deep links só em dispositivo real
- **Impacto de não executar:** Login social partido nas lojas

## TM-007

- **Fluxo relacionado:** FLOW-006
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Conta nova sem papel
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Escolher Cliente. 2. Fechar e abrir: deve ir para o Início do cliente, sem perguntar outra vez.
- **Resultado esperado:** Papel gravado uma vez.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Navegação real
- **Impacto de não executar:** Utilizador preso na escolha

## TM-008

- **Fluxo relacionado:** FLOW-007
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada com GPS ligado
- **Pré-condições:** Jardineiro novo
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Negar a permissão de localização e ver o que acontece. 2. Dar a permissão. 3. Usar a localização atual. 4. Mover o raio de 1 a 50 km. 5. Escolher serviços. 6. Guardar.
- **Resultado esperado:** Sem permissão: dá para escrever a morada; com permissão: rua mais próxima; guarda e abre o Início.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Permissões do SO e GPS real
- **Impacto de não executar:** Jardineiros não conseguem acabar o registo

## TM-009

- **Fluxo relacionado:** FLOW-008
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes) (build release)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** SMTP configurado
- **Dados de teste:** Conta de teste
- **Passos exatos:** 1. Esqueci-me da senha. 2. Email. 3. Código do email. 4. Senha nova. 5. Entrar com a senha nova. 6. Entrar com a antiga (deve falhar).
- **Resultado esperado:** Senha muda de verdade (em release não há atalho de debug).
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Email real; o atalho só existe em debug
- **Impacto de não executar:** Pessoas sem acesso à conta

## TM-010

- **Fluxo relacionado:** FLOW-009
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Sessão aberta
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Ligar o modo de avião. 2. Abrir a app. 3. Ver o ecrã de 'tentar novamente'. 4. Desligar o modo de avião e tocar em tentar novamente.
- **Resultado esperado:** Nunca vai para escolher papel; recupera ao voltar a rede.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Rede real
- **Impacto de não executar:** Perfil reescrito ou app parada sem rede

## TM-011

- **Fluxo relacionado:** FLOW-010, FLOW-073
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Push a funcionar
- **Dados de teste:** Duas contas
- **Passos exatos:** 1. Entrar com a conta A. 2. Terminar sessão. 3. Fazer algo que gere aviso para A (com outra conta). 4. Ver que o telemóvel não recebe push de A.
- **Resultado esperado:** Sem push depois de sair.
- **Evidência a recolher:** Captura
- **Porque não foi automatizado:** Push real
- **Impacto de não executar:** Avisos de outra pessoa no aparelho errado

## TM-012

- **Fluxo relacionado:** FLOW-011
- **Prioridade:** P0
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Conta de teste com 1 pedido aberto
- **Dados de teste:** Conta cliente descartável
- **Passos exatos:** 1. Conta > Eliminar conta. 2. Confirmar. 3. Ver que sai da app. 4. Pedir ao admin para ver que o pedido ficou fechado e o nome anonimizado.
- **Resultado esperado:** Conta anonimizada; pedido fechado; login bloqueado.
- **Evidência a recolher:** Capturas e confirmação no SQL Editor (só leitura)
- **Porque não foi automatizado:** Requisito das lojas; precisa de Auth real
- **Impacto de não executar:** Rejeição na Play Store/App Store e RGPD

## TM-013

- **Fluxo relacionado:** FLOW-012, FLOW-077
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Sessão de cliente
- **Dados de teste:** Foto grande (>5 MB)
- **Passos exatos:** 1. Editar perfil. 2. Mudar nome e telemóvel. 3. Mudar foto com a câmara e com a galeria. 4. Guardar.
- **Resultado esperado:** Foto aparece; dados guardados; câmara pede permissão.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Câmara e galeria reais
- **Impacto de não executar:** Perfis sem foto ou com dados errados

## TM-014

- **Fluxo relacionado:** FLOW-013
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Jardineiro
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Editar as 3 secções. 2. Pôr 5 destaques. 3. Pôr um link http (passa a https ao guardar) e um javascript: (deve recusar). 4. Abrir o cartão público e ver as mudanças.
- **Resultado esperado:** Cartão reflete os dados; o link http fica guardado como https; o javascript: é recusado.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Cartão público errado

## TM-015

- **Fluxo relacionado:** FLOW-014
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Browser
- **Pré-condições:** Conta cliente
- **Dados de teste:** URL /worker/home
- **Passos exatos:** 1. Com sessão de cliente, escrever o endereço /worker/home no browser.
- **Resultado esperado:** Volta para o Início do cliente.
- **Evidência a recolher:** Captura
- **Porque não foi automatizado:** Navegação real na web
- **Impacto de não executar:** Ecrãs do outro papel abertos

## TM-016

- **Fluxo relacionado:** FLOW-020
- **Prioridade:** P0
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada e browser
- **Pré-condições:** Cliente
- **Dados de teste:** 2 fotos
- **Passos exatos:** 1. Criar pedido com data fixa, morada por GPS, descrição e 2 fotos. 2. Publicar. 3. Ver o pedido no Início. 4. Com a conta de um jardineiro da zona, ver o pedido e a notificação.
- **Resultado esperado:** Pedido publicado com as 2 fotos; jardineiro avisado; morada exata escondida ao jardineiro.
- **Evidência a recolher:** Capturas dos dois lados
- **Porque não foi automatizado:** Fotos, GPS e notificações reais
- **Impacto de não executar:** Fluxo principal partido

## TM-017

- **Fluxo relacionado:** FLOW-020, FLOW-021
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Cliente
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Começar a criar um pedido. 2. Sair a meio e voltar (rascunho). 3. No passo das fotos, ligar o modo de avião e publicar. 4. Publicar 6 pedidos numa hora.
- **Resultado esperado:** Rascunho mantido; erro claro sem rede sem duplicar; 6.º pedido recusado com mensagem compreensível.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Rede real e rascunho local
- **Impacto de não executar:** Pedidos duplicados ou mensagem técnica

## TM-018

- **Fluxo relacionado:** FLOW-022
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Pedido aberto com 1 proposta
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Editar a descrição e a data. 2. Com a conta do jardineiro, ver o aviso 'pedido atualizado'.
- **Resultado esperado:** Edição guardada; aviso chega.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Jardineiro propõe sobre dados velhos

## TM-019

- **Fluxo relacionado:** FLOW-023, FLOW-094
- **Prioridade:** P3
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Pedido sem propostas há 24h
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Ver o cartão 'Ainda sem propostas'. 2. Alargar a pesquisa até 30 km.
- **Resultado esperado:** Botão some aos 30 km; jardineiros do anel avisados.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Depende do tempo real e do cron
- **Impacto de não executar:** Pedidos esquecidos

## TM-020

- **Fluxo relacionado:** FLOW-024
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Pedido com 3 propostas
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Abrir propostas. 2. Ver nomes, fotos, preços e a recomendada.
- **Resultado esperado:** Lista certa e legível.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Visual
- **Impacto de não executar:** Escolha mal informada

## TM-021

- **Fluxo relacionado:** FLOW-025, FLOW-026, FLOW-043
- **Prioridade:** P0
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Dois telemóveis
- **Pré-condições:** Pedido com 2 propostas
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Aceitar uma proposta. 2. Ver o ecrã de confirmado e o botão WhatsApp. 3. Com o jardineiro escolhido, ver o aviso e o trabalho em Agenda. 4. Com o outro, ver 'O cliente escolheu outra proposta'. 5. Noutro pedido, o jardineiro carrega em Retirar e a cliente em Aceitar no mesmo segundo (BUG-001).
- **Resultado esperado:** Passos 1 a 4 certos. Passo 5: hoje pode ficar incoerente (ver BUG-001).
- **Evidência a recolher:** Capturas e vídeo do passo 5
- **Porque não foi automatizado:** Precisa de dois aparelhos reais e coordenação
- **Impacto de não executar:** Contratações erradas

## TM-022

- **Fluxo relacionado:** FLOW-027, FLOW-038
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Pedidos em todos os estados
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Abrir um pedido em cada estado (aberto, confirmado, em curso, à espera de confirmação, concluído, cancelado, sem resposta). 2. Ver o stepper e o próximo passo.
- **Resultado esperado:** Texto e botões certos em cada estado.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Visual
- **Impacto de não executar:** Clientes confusos

## TM-023

- **Fluxo relacionado:** FLOW-028
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Trabalho marcado concluído
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Confirmar. 2. Tocar duas vezes rápido no botão.
- **Resultado esperado:** Uma confirmação; pede avaliação.
- **Evidência a recolher:** Captura
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Trabalhos por fechar

## TM-024

- **Fluxo relacionado:** FLOW-029
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Trabalho marcado concluído
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Reportar um problema. 2. Ver a confirmação automática a dizer 7 dias.
- **Resultado esperado:** Relato enviado e o jardineiro avisado.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Disputas sem registo

## TM-025

- **Fluxo relacionado:** FLOW-030, FLOW-049, FLOW-074
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Trabalho concluído
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Avaliar o jardineiro com 4 estrelas. 2. Voltar ao ecrã e confirmar que já não deixa avaliar outra vez. 3. Ver em 'As minhas avaliações' dos dois lados.
- **Resultado esperado:** Uma avaliação por pessoa; aparece nas listas.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Reputação errada

## TM-026

- **Fluxo relacionado:** FLOW-031
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Pedido aberto e trabalho confirmado
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Cancelar um pedido aberto. 2. Cancelar um trabalho confirmado e escolher voltar a publicar. 3. Tentar cancelar um trabalho já iniciado.
- **Resultado esperado:** Cancelamentos certos; reabre; iniciado não deixa.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Cancelamentos indevidos

## TM-027

- **Fluxo relacionado:** FLOW-032
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Dois telemóveis
- **Pré-condições:** Trabalho confirmado
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Jardineiro propõe nova data. 2. Cliente aceita. 3. Ver a data nova nos dois lados e na Agenda.
- **Resultado esperado:** Data atualizada em todo o lado.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Dois aparelhos
- **Impacto de não executar:** Pessoas aparecem no dia errado

## TM-028

- **Fluxo relacionado:** FLOW-033, FLOW-035, FLOW-044, FLOW-093
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Dois telemóveis
- **Pré-condições:** Trabalho concluído
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Pedir de novo ao mesmo jardineiro. 2. Com o jardineiro, responder 'Não posso desta vez'. 3. Noutro pedido, deixar passar 24h sem resposta.
- **Resultado esperado:** Avisos certos; abre a todos ou fica parado conforme o interruptor.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Tempo real (24h) e dois aparelhos
- **Impacto de não executar:** Clientes à espera para sempre

## TM-029

- **Fluxo relacionado:** FLOW-034
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada e outro telemóvel para ler o QR
- **Pré-condições:** Jardineiro com cartão
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Ler o QR do cartão com outro telemóvel sem a app. 2. Abrir no browser. 3. Pedir orçamento, registar e enviar. 4. Ver o pedido no jardineiro.
- **Resultado esperado:** Pedido chega reservado a esse jardineiro.
- **Evidência a recolher:** Vídeo
- **Porque não foi automatizado:** Câmara, QR e links reais
- **Impacto de não executar:** Perde-se o canal de angariação

## TM-030

- **Fluxo relacionado:** FLOW-036
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada com WhatsApp e outro sem WhatsApp
- **Pré-condições:** Trabalho confirmado
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Tocar em WhatsApp. 2. Repetir num telemóvel sem WhatsApp.
- **Resultado esperado:** Abre a conversa com o número certo; sem WhatsApp mostra aviso.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** App externa
- **Impacto de não executar:** Sem forma de contacto

## TM-031

- **Fluxo relacionado:** FLOW-037, FLOW-050..052, FLOW-095
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Três telemóveis (cliente, responsável, ajudante)
- **Pré-condições:** Proposta com 2 pessoas aceite
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Cliente aprova o pedido de ajudantes. 2. Ajudante candidata-se com mensagem. 3. Responsável aceita com taxa. 4. Ajudante vê o trabalho e o WhatsApp do responsável. 5. Ajudante desiste na véspera e no dia.
- **Resultado esperado:** Equipa certa; desistência só até à véspera.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Três contas e tempo real
- **Impacto de não executar:** Equipas erradas no dia

## TM-032

- **Fluxo relacionado:** FLOW-039, FLOW-097
- **Prioridade:** P3
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Cliente
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Desligar 'Dicas da época'. 2. Confirmar com o admin que não recebe a campanha seguinte.
- **Resultado esperado:** Preferência respeitada.
- **Evidência a recolher:** Captura
- **Porque não foi automatizado:** Depende da data da campanha
- **Impacto de não executar:** Avisos indesejados (RGPD)

## TM-033

- **Fluxo relacionado:** FLOW-040, FLOW-041
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Jardineiro
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Abrir Pedidos. 2. Filtrar categorias. 3. Abrir um pedido e ver só a zona aproximada no mapa.
- **Resultado esperado:** Só pedidos da zona; morada exata escondida.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Mapa e GPS reais
- **Impacto de não executar:** Privacidade da cliente

## TM-034

- **Fluxo relacionado:** FLOW-042
- **Prioridade:** P0
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Jardineiro e pedido aberto
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Proposta à hora com data. 2. Proposta a valor total em dias. 3. 'A combinar'. 4. Com ajudantes. 5. Tocar duas vezes em Enviar.
- **Resultado esperado:** Uma proposta por envio; textos de preço certos.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Sem propostas não há negócio

## TM-035

- **Fluxo relacionado:** FLOW-045, FLOW-060
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Jardineiro com trabalhos em vários estados
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Ver Início e Trabalhos (Agenda, Propostas, Histórico). 2. Confirmar contagens.
- **Resultado esperado:** Cada trabalho no sítio certo.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Visual
- **Impacto de não executar:** Trabalhos esquecidos

## TM-036

- **Fluxo relacionado:** FLOW-046, FLOW-048
- **Prioridade:** P0
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada com câmara
- **Pré-condições:** Trabalho hoje
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Iniciar com 2 fotos de antes (câmara). 2. Marcar concluído com 2 fotos de depois. 3. Ver na cliente as fotos e o estado.
- **Resultado esperado:** Fotos visíveis; estados certos.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Câmara real
- **Impacto de não executar:** Fluxo central partido

## TM-037

- **Fluxo relacionado:** FLOW-047
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Proposta de 3 dias aceite
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Iniciar. 2. Ver 'Dia 1 de 3'. 3. Nos dias seguintes, ver o dia certo. 4. Passar do prazo e ver o aviso a amarelo. 5. Concluir.
- **Resultado esperado:** Dias e avisos certos.
- **Evidência a recolher:** Capturas por dia
- **Porque não foi automatizado:** Depende de dias reais
- **Impacto de não executar:** Avisos errados

## TM-038

- **Fluxo relacionado:** FLOW-053, FLOW-054
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Jardineiro
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Adicionar trabalho de fora da app semanal. 2. Mudar só um dia. 3. Mudar este e os seguintes. 4. Marcar feito e repor. 5. Adicionar folga e ver o aviso de sobreposição.
- **Resultado esperado:** Agenda certa em Hoje, Semana e Mês.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Visual
- **Impacto de não executar:** Agenda errada

## TM-039

- **Fluxo relacionado:** FLOW-055
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Jardineiro Grátis e Pro
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Abrir o cartão. 2. Partilhar o link por WhatsApp. 3. Gerar PDF (Pro) e ver que no Grátis não aparece.
- **Resultado esperado:** Link abre /w/:id; PDF só no Pro.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Partilha do SO
- **Impacto de não executar:** Divulgação partida

## TM-040

- **Fluxo relacionado:** FLOW-056, FLOW-057
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes) com a 0067 aplicada
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Jardineiro Grátis com 5 trabalhos e outro Pro
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Grátis: enviar a 6.ª proposta do mês. 2. Pro: abrir o painel de ganhos.
- **Resultado esperado:** Grátis recusado com texto claro; Pro vê ganhos.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Depende das migrations aplicadas
- **Impacto de não executar:** Planos sem valor

## TM-041

- **Fluxo relacionado:** FLOW-058
- **Prioridade:** P3
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada com câmara
- **Pré-condições:** nenhum
- **Dados de teste:** Cartão de exemplo
- **Passos exatos:** 1. Fotografar um cartão. 2. Ver os 3 campos lidos. 3. Confirmar.
- **Resultado esperado:** Dados certos; pedido pendente.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** OCR só no dispositivo
- **Impacto de não executar:** Demo falha no pitch

## TM-042

- **Fluxo relacionado:** FLOW-059, FLOW-092, FLOW-098
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes) com a 0072 aplicada
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Trabalho com hora marcada daqui a 70 min
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Esperar o aviso 1h antes. 2. Não iniciar e esperar 30 min depois da hora. 3. No dia seguinte de manhã, ver o lembrete diário.
- **Resultado esperado:** Um aviso de cada, à hora certa.
- **Evidência a recolher:** Capturas com hora
- **Porque não foi automatizado:** Tempo real e cron
- **Impacto de não executar:** Jardineiros faltam

## TM-043

- **Fluxo relacionado:** FLOW-070
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Várias notificações
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Filtrar Todas/Trabalhos. 2. Abrir uma (fica lida). 3. Limpar tudo e escolher "Não apagar". 4. Limpar tudo, "Apagar para sempre" e recarregar. 5. Ver o número por ler no separador Alertas (cliente) ou no sino (jardineiro).
- **Resultado esperado:** Lista e contador certos.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** UI real
- **Impacto de não executar:** Avisos perdidos

## TM-044

- **Fluxo relacionado:** FLOW-071, FLOW-075
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Um aviso de cada tipo principal
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Tocar em cada tipo (proposta recebida, aceite, recusada, trabalho iniciado, concluído, ajudante aceite, remarcação). 2. Em cada destino, carregar em voltar.
- **Resultado esperado:** Abre o ecrã certo; voltar vai para trás ou para o Início.
- **Evidência a recolher:** Lista tipo → ecrã com capturas
- **Porque não foi automatizado:** 38 tipos com dados reais
- **Impacto de não executar:** Pessoas perdidas na app

## TM-045

- **Fluxo relacionado:** FLOW-072
- **Prioridade:** P3
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Dois telemóveis
- **Pré-condições:** App aberta
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Com a app aberta num ecrã qualquer, gerar um aviso com a outra conta. 2. Ver o aviso no topo e tocar.
- **Resultado esperado:** Aparece uma vez e abre o destino.
- **Evidência a recolher:** Vídeo
- **Porque não foi automatizado:** Realtime real
- **Impacto de não executar:** Avisos repetidos ou invisíveis

## TM-046

- **Fluxo relacionado:** FLOW-073, FLOW-099
- **Prioridade:** P0
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes) com Firebase e send-push
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada e iPhone (se houver app iOS)
- **Pré-condições:** Permissão de notificações
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Dar permissão. 2. Fechar a app. 3. Com outra conta, criar um pedido na zona. 4. Ver o push. 5. Tocar e ver o destino. 6. Recusar a permissão noutra instalação.
- **Resultado esperado:** Push chega com a app fechada e abre o destino.
- **Evidência a recolher:** Capturas do push
- **Porque não foi automatizado:** FCM, APNs e Edge Function reais
- **Impacto de não executar:** Ninguém volta à app

## TM-047

- **Fluxo relacionado:** FLOW-073
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** Push a funcionar
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Desinstalar e instalar a app. 2. Entrar. 3. Ver que continua a receber push e que o token antigo foi apagado (logs da Edge Function).
- **Resultado esperado:** Tokens antigos limpos.
- **Evidência a recolher:** Logs da Edge Function
- **Porque não foi automatizado:** Precisa da infraestrutura real
- **Impacto de não executar:** Push duplicado ou perdido

## TM-048

- **Fluxo relacionado:** FLOW-075
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Android e browser
- **Pré-condições:** nenhum
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Abrir por notificação e usar o voltar do Android. 2. Na web, usar o voltar do browser em cada fluxo de 4 passos.
- **Resultado esperado:** Nunca fica preso nem sai da app sem querer.
- **Evidência a recolher:** Vídeo
- **Porque não foi automatizado:** Gestos reais
- **Impacto de não executar:** Pessoas presas

## TM-049

- **Fluxo relacionado:** FLOW-076
- **Prioridade:** P3
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** nenhum
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Abrir Termos, Política e Contacto. 2. Testar sem browser predefinido.
- **Resultado esperado:** Abre as páginas; aviso se não conseguir.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Apps externas
- **Impacto de não executar:** Requisito legal

## TM-050

- **Fluxo relacionado:** FLOW-077
- **Prioridade:** P2
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Browser em janela privada
- **Pré-condições:** Uma foto de pedido
- **Dados de teste:** URL da foto
- **Passos exatos:** 1. Copiar o URL de uma foto de pedido. 2. Abrir numa janela privada sem sessão.
- **Resultado esperado:** Hoje abre (buckets públicos). Decidir se é aceitável.
- **Evidência a recolher:** Captura
- **Porque não foi automatizado:** Decisão de privacidade
- **Impacto de não executar:** Fotos de casas acessíveis por link

## TM-051

- **Fluxo relacionado:** FLOW-078
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada na rua e em casa
- **Pré-condições:** nenhum
- **Dados de teste:** Moradas reais de aldeia e cidade
- **Passos exatos:** 1. Escrever uma morada de aldeia. 2. Usar o GPS. 3. Repetir sem rede.
- **Resultado esperado:** Sugestões úteis; GPS dá a rua mais próxima; sem rede mostra erro claro.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** APIs externas e GPS
- **Impacto de não executar:** Pedidos com morada errada

## TM-052

- **Fluxo relacionado:** FLOW-079
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** nenhum
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Modo de avião a meio de enviar proposta, aceitar e concluir. 2. Rede lenta (3G).
- **Resultado esperado:** Mensagens em português; sem ações duplicadas.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Rede real
- **Impacto de não executar:** Ações duplicadas ou perdidas

## TM-053

- **Fluxo relacionado:** FLOW-080..082
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Browser
- **Pré-condições:** Admin com TOTP
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Entrar em /admin sem segundo fator. 2. Com TOTP. 3. Ver números e ficha. 4. Dar Pro a um jardineiro de teste.
- **Resultado esperado:** Nada abre sem TOTP; plano aplicado e registado.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** MFA real
- **Impacto de não executar:** Acesso indevido ao painel

## TM-054

- **Fluxo relacionado:** FLOW-090, FLOW-091, FLOW-096
- **Prioridade:** P0
- **Ambiente necessário:** SQL Editor do Supabase (só leitura)
- **Dispositivo necessário:** Computador
- **Pré-condições:** Acesso ao projeto
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Correr: select jobname, schedule, active from cron.job order by 1; 2. Comparar com os 11 jobs da lista em 06-REGRESSION-AND-DEPENDENCIES.md. 3. Ver cron.job_run_details das últimas 24h.
- **Resultado esperado:** Os 11 jobs existem, ativos e sem erros.
- **Evidência a recolher:** Resultado das 2 queries
- **Porque não foi automatizado:** Só na BD viva
- **Impacto de não executar:** Trabalhos e pedidos ficam presos para sempre

## TM-055

- **Fluxo relacionado:** FLOW-100
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Chrome, Safari, browser de telemóvel
- **Pré-condições:** Deploy web
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Abrir o site. 2. Registar, criar pedido e propor. 3. Recarregar a página a meio de um fluxo. 4. Abrir um link /w/:id direto.
- **Resultado esperado:** Funciona e recupera ao recarregar.
- **Evidência a recolher:** Capturas
- **Porque não foi automatizado:** Browsers reais
- **Impacto de não executar:** Web partida

## TM-056

- **Fluxo relacionado:** FLOW-101
- **Prioridade:** P1
- **Ambiente necessário:** App ligada ao Supabase de produção com contas de teste (ou a um projeto de testes)
- **Dispositivo necessário:** Telemóvel Android com a app de teste instalada
- **Pré-condições:** nenhum
- **Dados de teste:** nenhum
- **Passos exatos:** 1. Em cada botão principal (publicar, enviar proposta, aceitar, iniciar, concluir, confirmar, avaliar), tocar duas vezes muito rápido.
- **Resultado esperado:** Uma só ação e o botão fica a carregar.
- **Evidência a recolher:** Vídeo
- **Porque não foi automatizado:** Toque real
- **Impacto de não executar:** Dados duplicados

