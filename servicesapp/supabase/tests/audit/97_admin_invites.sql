-- Convites por email (migration 0085), 28/11/2026: o painel regista cada
-- envio antes de a Edge Function o mandar ao Brevo, marca o resultado,
-- mostra o histórico e respeita quem pediu para não receber.
-- Corre depois do 10_flows.sql (bash run.sh keep), na mesma BD.

\set W1 '00000000-0000-0000-0000-0000000000a1'
\set AD '00000000-0000-0000-0000-0000000000ad'
\set A2 '00000000-0000-0000-0000-0000000000a9'

reset role;
select t_as('');
-- Segundo admin, para provar que só quem criou marca o resultado.
insert into auth.users(id, email, email_confirmed_at) values (:'A2', 'a2@teste.local', now());
insert into admin_users(user_id) values (:'A2');
select count(*) as acts0 from admin_actions \gset

\set BODY '''Bom dia, Rui. Estamos a lançar a ProJardim. Para não receber: https://projardim.pt/sem-convites'''

-- ── Acesso ──
set role anon;
select t_as('');
select audit.err('T-INV-01 sem sessão não cria', $q$select * from admin_invite_create('founder_invite', 'Rui', 'rui@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'permission denied');
select audit.err('T-INV-02 sem sessão não lista', $q$select * from admin_list_invites()$q$, 'permission denied');
select audit.err('T-INV-03 sem sessão não vê o estado', $q$select admin_invite_status('rui@example.com')$q$, 'permission denied');
select audit.err('T-INV-04 a tabela não se lê diretamente', $q$select count(*) from admin_invites$q$, 'permission denied');
select audit.eq('T-INV-05 token desconhecido devolve false sem erro', $q$select invite_optout('7c9e6679-7425-40de-944b-e07fc1f90ae7')::text$q$, 'false');
reset role;

set role authenticated;
select t_as(:'W1');
select audit.err('T-INV-06 utilizador normal não cria', $q$select * from admin_invite_create('founder_invite', 'Rui', 'rui@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'Sem acesso');
select audit.err('T-INV-07 utilizador normal não lista', $q$select * from admin_list_invites()$q$, 'Sem acesso');
select audit.err('T-INV-08 utilizador normal não marca', $q$select admin_invite_set_optout('rui@example.com')$q$, 'Sem acesso');
select audit.err('T-INV-09 tabela de quem não quer receber fechada', $q$select count(*) from email_optouts$q$, 'permission denied');
select t_as(:'AD');
select audit.err('T-INV-10 admin sem segundo fator não cria', $q$select * from admin_invite_create('founder_invite', 'Rui', 'rui@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'Sem acesso');
select audit.err('T-INV-11 admin sem segundo fator não vê o estado', $q$select admin_invite_status('rui@example.com')$q$, 'Sem acesso');

-- ── Validações ──
select t_aal2(:'AD');
select audit.err('T-INV-12 modelo inválido', $q$select * from admin_invite_create('promo', 'Rui', 'rui@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'Modelo de email inválido');
select audit.err('T-INV-13 nome curto', $q$select * from admin_invite_create('founder_invite', 'R', 'rui@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'nome tem de ter');
select audit.err('T-INV-14 email inválido', $q$select * from admin_invite_create('founder_invite', 'Rui', 'rui@example', 'Convite', 'texto com mais de vinte carateres')$q$, 'email não parece válido');
select audit.err('T-INV-15 assunto vazio', $q$select * from admin_invite_create('founder_invite', 'Rui', 'rui@example.com', ' ', 'texto com mais de vinte carateres')$q$, 'assunto tem de ter');
select audit.err('T-INV-16 texto vazio', $q$select * from admin_invite_create('founder_invite', 'Rui', 'rui@example.com', 'Convite', 'curto')$q$, 'texto do email');

-- ── Envio ──
select id as i1, optout_token as tok1 from admin_invite_create('founder_invite', '  Rui Costa ', ' Rui@Example.COM ', 'Convite para Profissional fundador da ProJardim', :BODY) \gset
reset role;
select audit.eq('T-INV-17 fica pendente, email em minúsculas e nome limpo',
  format($q$select status || '|' || recipient_email || '|' || recipient_name from admin_invites where id = %L$q$, :'i1'),
  'pending|rui@example.com|Rui Costa');
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-INV-18 duplo clique recusado enquanto está pendente', $q$select * from admin_invite_create('founder_invite', 'Rui', 'rui@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'últimas 24 horas');
select t_aal2(:'A2');
select audit.err('T-INV-19 outro admin não marca o envio de outro', format($q$select admin_invite_finish(%L, true, 'm1')$q$, :'i1'), 'já não está pendente');
select t_aal2(:'AD');
select audit.ok('T-INV-20 marca enviado', format($q$select admin_invite_finish(%L, true, '<abc@smtp-relay.brevo.com>')$q$, :'i1'));
reset role;
select audit.eq('T-INV-21 enviado com data e id do Brevo',
  format($q$select status || '|' || (sent_at is not null) || '|' || provider_message_id from admin_invites where id = %L$q$, :'i1'),
  'sent|true|<abc@smtp-relay.brevo.com>');
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-INV-22 não se marca duas vezes', format($q$select admin_invite_finish(%L, false, null, 'x')$q$, :'i1'), 'já não está pendente');
select audit.err('T-INV-23 mesmo modelo no mesmo dia recusado', $q$select * from admin_invite_create('founder_invite', 'Rui', 'RUI@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'últimas 24 horas');
select audit.ok('T-INV-24 outro modelo (lembrete) ao mesmo email passa',
  $q$select * from admin_invite_create('founder_reminder', 'Rui', 'rui@example.com', 'Lembrete', 'texto com mais de vinte carateres')$q$);
reset role;
select id as i2 from admin_invites where template = 'founder_reminder' and recipient_email = 'rui@example.com' \gset
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-INV-25 marca falhado com o erro', format($q$select admin_invite_finish(%L, false, null, 'Brevo 401: Key not found')$q$, :'i2'));
reset role;
select audit.eq('T-INV-26 falhado guarda o erro e não tem data de envio',
  format($q$select status || '|' || error || '|' || (sent_at is null) from admin_invites where id = %L$q$, :'i2'),
  'failed|Brevo 401: Key not found|true');
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-INV-27 depois de falhar pode tentar outra vez',
  $q$select * from admin_invite_create('founder_reminder', 'Rui', 'rui@example.com', 'Lembrete', 'texto com mais de vinte carateres')$q$);

-- Pendente esquecido há mais de 10 minutos já não bloqueia.
reset role;
insert into admin_invites(template, recipient_name, recipient_email, subject, body_text, created_by, created_at)
values ('founder_invite', 'Ana', 'ana@example.com', 'Convite', 'texto com mais de vinte carateres', :'AD', now() - interval '20 minutes');
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-INV-28 pendente antigo não bloqueia um novo envio',
  $q$select * from admin_invite_create('founder_invite', 'Ana', 'ana@example.com', 'Convite', 'texto com mais de vinte carateres')$q$);

-- ── Estado e histórico ──
select audit.eq('T-INV-29 estado de um email',
  $q$select (s->>'opted_out') || '|' || (s->>'sent_count') || '|' || (s->>'last_template') || '|' || (s->>'daily_limit')
     from admin_invite_status(' RUI@example.com ') s$q$,
  'false|1|founder_invite|40');
select audit.eq('T-INV-30 histórico do mais recente para o mais antigo, com total',
  $q$select string_agg(template || ':' || status, ',' order by created_at desc) || '|' || max(total_count)
     from admin_list_invites('rui@')$q$,
  'founder_reminder:pending,founder_reminder:failed,founder_invite:sent|3');
select audit.eq('T-INV-31 pesquisa por nome', $q$select count(*)::text from admin_list_invites('ana')$q$, '2');

-- ── Não quero receber ──
reset role;
set role anon;
select t_as('');
select audit.eq('T-INV-32 link do email regista sem sessão', format($q$select invite_optout(%L)::text$q$, :'tok1'), 'true');
select audit.eq('T-INV-33 pedir outra vez não faz mal', format($q$select invite_optout(%L)::text$q$, :'tok1'), 'true');
reset role;
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-INV-34 fica registado pelo link',
  $q$select (s->>'opted_out') from admin_invite_status('rui@example.com') s$q$, 'true');
select audit.err('T-INV-35 depois disso nenhum modelo passa', $q$select * from admin_invite_create('founder_invite_plain', 'Rui', 'Rui@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'pediu para não receber');
select audit.eq('T-INV-36 o histórico mostra quem não quer receber',
  $q$select count(*)::text from admin_list_invites('rui@') where opted_out_at is not null$q$, '3');
select audit.ok('T-INV-37 admin marca quem respondeu "não"', $q$select admin_invite_set_optout('Ana@Example.com', 'Respondeu não')$q$);
select audit.err('T-INV-38 marcado pelo admin também bloqueia', $q$select * from admin_invite_create('founder_reminder', 'Ana', 'ana@example.com', 'Lembrete', 'texto com mais de vinte carateres')$q$, 'pediu para não receber');
select audit.err('T-INV-39 marcar exige email válido', $q$select admin_invite_set_optout('ana')$q$, 'email não parece válido');

-- ── Limite diário ──
reset role;
insert into admin_invites(template, recipient_name, recipient_email, subject, body_text, status, created_by)
select 'founder_invite', 'Teste ' || g, 'teste' || g || '@example.com', 'Convite', 'texto com mais de vinte carateres', 'sent', :'AD'
from generate_series(1, 40) g;
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-INV-40 limite de convites em 24 horas', $q$select * from admin_invite_create('founder_invite', 'Zé', 'ze@example.com', 'Convite', 'texto com mais de vinte carateres')$q$, 'limite de 40');
select audit.eq('T-INV-41 o estado mostra o limite atingido',
  $q$select ((s->>'sent_today')::int >= (s->>'daily_limit')::int)::text from admin_invite_status('ze@example.com') s$q$, 'true');

-- ── Registo e limpeza ──
reset role;
select audit.eq('T-INV-42 envios e marcação ficam no registo do admin',
  format($q$select (count(*) filter (where action = 'invite_create'))::text || '|' || (count(*) filter (where action = 'invite_optout'))::text
     from admin_actions where action in ('invite_create', 'invite_optout')$q$),
  '4|1');
select audit.eq('T-INV-43 o registo não guarda o email de quem é convidado',
  $q$select count(*)::text from admin_actions where action in ('invite_create', 'invite_optout') and details::text like '%@%'$q$, '0');
update admin_invites set created_at = now() - interval '13 months' where recipient_email = 'rui@example.com';
select audit.eq('T-INV-44 limpeza apaga o histórico com mais de 12 meses', $q$select purge_old_admin_invites()::text$q$, '3');
select audit.eq('T-INV-45 quem não quer receber continua registado',
  $q$select count(*)::text from email_optouts where email in ('rui@example.com', 'ana@example.com')$q$, '2');
set role authenticated;
select t_as(:'AD');
select audit.err('T-INV-46 limpeza só pelo cron', $q$select purge_old_admin_invites()$q$, 'permission denied');
reset role;

select format('%s | %s | %s', case when ok then 'PASS' else 'FAIL' end, id, coalesce(detail, ''))
from audit.results where id like 'T-INV-%' order by seq;
select format('TOTAL %s | PASS %s | FAIL %s', count(*), count(*) filter (where ok), count(*) filter (where not ok))
from audit.results where id like 'T-INV-%';
