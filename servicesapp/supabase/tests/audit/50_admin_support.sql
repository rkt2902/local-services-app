-- Painel de admin para suporte, fase A (migration 0078), 13/11/2026.
-- Corre depois do 10_flows.sql, na mesma BD (bash run.sh keep), porque usa
-- as pessoas e os pedidos que ele cria. Só para a BD local de teste.
--
-- Cada RPC nova tem 3 recusas (sem sessão, utilizador normal, admin sem
-- segundo fator) e pelo menos um caso que funciona com aal2.

\set W1 '00000000-0000-0000-0000-0000000000a1'
\set C2 '00000000-0000-0000-0000-0000000000c2'
\set AD '00000000-0000-0000-0000-0000000000ad'

reset role;
select id as jdone from job_requests where status = 'completed' order by created_at limit 1 \gset
select id as jopen from job_requests where status = 'open' order by created_at limit 1 \gset
select count(*) as acts0 from admin_actions \gset

-- Pedido antigo: tira os eventos de um pedido e volta a correr a migration.
-- O pedido recebe os eventos dos carimbos e os outros não se duplicam.
select count(*) as ev_total0 from job_events where job_id <> :'jdone' \gset
delete from job_events where job_id = :'jdone';
\set QUIET on
\ir ../../migrations/0078_admin_support_tracking.sql
\set QUIET off
select audit.eq('T-SUP-01 migration volta a correr e preenche o pedido antigo pelos carimbos',
  format($q$select (count(*) > 0 and bool_and((data->>'backfill')::boolean))::text from job_events where job_id=%L$q$, :'jdone'), 'true');
select audit.eq('T-SUP-02 correr outra vez não duplica eventos dos outros pedidos',
  format($q$select count(*)::text from job_events where job_id<>%L$q$, :'jdone'), :'ev_total0');
select audit.eq('T-SUP-03 o pedido antigo tem criado, proposta, aceite e concluído pelo jardineiro',
  format($q$select (count(distinct event_type) filter (where event_type in ('created','proposal_sent','accepted','marked_done')))::text from job_events where job_id=%L$q$, :'jdone'), '4');

-- Eventos novos: um pedido criado e cancelado pela cliente C2.
set role authenticated;
select t_as(:'C2');
select audit.val('T-SUP-04 cliente cria pedido (preparação)',
  format($q$insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
     select %L, id, 'Rua Suporte 1', 38.72, -9.14, 'suporte', 'open', 'flexible' from service_types order by sort_order limit 1 returning id$q$, :'C2')) as jsup \gset
select audit.ok('T-SUP-05 cliente cancela',
  format($q$select cancel_job(%L, 'other', 'teste do suporte')$q$, :'jsup'));
reset role;
select audit.eq('T-SUP-06 linha do tempo: criado e cancelado, ambos pela cliente',
  format($q$select string_agg(event_type || ':' || actor_kind, ',' order by created_at) from job_events where job_id=%L$q$, :'jsup'),
  'created:client,cancelled:client');
select audit.eq('T-SUP-07 cancelamento guarda o motivo',
  format($q$select data->>'reason' from job_events where job_id=%L and event_type='cancelled'$q$, :'jsup'), 'other');
select t_as('');
update job_requests set status='no_response' where id=:'jopen' and status='open';
select audit.eq('T-SUP-08 mudança feita sem sessão (cron) fica como sistema',
  format($q$select actor_kind from job_events where job_id=%L and event_type='expired'$q$, :'jopen'), 'system');

-- job_events é só do servidor.
set role authenticated;
select t_as(:'C2');
select audit.err('T-SUP-09 utilizador não lê job_events diretamente',
  $q$select count(*) from job_events$q$, 'permission denied');
select audit.err('T-SUP-10 utilizador não escreve eventos à mão',
  format($q$select log_job_event(%L, 'fake')$q$, :'jsup'), 'permission denied');
reset role;

-- ── Recusas: sem sessão, utilizador normal, admin sem aal2 ──
create temp table sup_calls(name text, sql text);
insert into sup_calls values
  ('admin_search',         $q$select * from admin_search('Cliente')$q$),
  ('admin_list_jobs',      $q$select * from admin_list_jobs()$q$),
  ('admin_get_job',        format($q$select admin_get_job(%L)$q$, :'jdone')),
  ('admin_get_job_photos', format($q$select * from admin_get_job_photos(%L)$q$, :'jdone')),
  ('admin_list_clients',   $q$select * from admin_list_clients()$q$),
  ('admin_get_client',     format($q$select admin_get_client(%L)$q$, :'C2')),
  ('admin_reveal_contact', format($q$select admin_reveal_contact(%L, 'phone')$q$, :'C2'));
grant select on sup_calls to anon, authenticated;

set role anon;
select t_as('');
select audit.err('T-SUP-11 sem sessão: ' || name, sql, 'permission denied') from sup_calls;
reset role;
set role authenticated;
select t_as(:'W1');
select audit.err('T-SUP-12 utilizador normal: ' || name, sql, 'Sem acesso') from sup_calls;
select t_as(:'AD');
select audit.err('T-SUP-13 admin sem segundo fator: ' || name, sql, 'Sem acesso') from sup_calls;
reset role;
select audit.eq('T-SUP-14 recusas não deixam registo',
  $q$select count(*)::text from admin_actions$q$, :'acts0');

-- ── Admin com segundo fator ──
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-SUP-20 pesquisa por email encontra a cliente',
  $q$select count(*)::text from admin_search('c2@teste.local') where kind='client'$q$, '1');
select audit.eq('T-SUP-21 pesquisa pelo id curto (8 carateres) encontra o pedido',
  format($q$select target_id::text from admin_search(%L) where kind='job'$q$, left(:'jsup', 8)), :'jsup');
select audit.eq('T-SUP-22 pesquisa pelo telefone encontra o jardineiro',
  $q$select count(*)::text from admin_search('910 000 011') where target_id='00000000-0000-0000-0000-0000000000a1'$q$, '1');
select audit.eq('T-SUP-23 pesquisa com 1 caráter não devolve nada',
  $q$select count(*)::text from admin_search('a')$q$, '0');
select audit.eq('T-SUP-24 lista de pedidos filtra por estado',
  $q$select bool_and(status='cancelled')::text from admin_list_jobs(p_status=>'cancelled')$q$, 'true');
select audit.eq('T-SUP-25 lista de pedidos com ajudantes',
  $q$select (count(*) >= 1 and bool_and(has_helpers))::text from admin_list_jobs(p_with_helpers=>true)$q$, 'true');
select audit.eq('T-SUP-26 ficha do pedido traz linha do tempo, propostas e avisos',
  format($q$select (jsonb_array_length(j->'timeline') > 0 and jsonb_array_length(j->'proposals') > 0 and j ? 'notifications' and j ? 'team')::text from admin_get_job(%L) j$q$, :'jdone'), 'true');
select audit.eq('T-SUP-27 ficha do pedido não traz a morada exata',
  format($q$select (admin_get_job(%L)::text not like '%%Rua Suporte%%')::text$q$, :'jsup'), 'true');
select audit.eq('T-SUP-28 ficha da cliente traz email e telefone mascarado',
  format($q$select (j->>'email') || ' ' || (j->>'phone_masked') from admin_get_client(%L) j$q$, :'C2'), 'c2@teste.local ••• ••• 002');
select audit.eq('T-SUP-29 lista de clientes não traz o telefone inteiro',
  $q$select count(*)::text from admin_list_clients() where phone_masked like '%910%'$q$, '0');
select audit.eq('T-SUP-30 lista de jardineiros passa a trazer o telefone mascarado',
  $q$select count(*)::text from admin_list_workers() where phone like '%910%'$q$, '0');
select audit.eq('T-SUP-31 revelar telefone devolve o número',
  format($q$select admin_reveal_contact(%L, 'phone', 'confirmar identidade')->>'phone'$q$, :'C2'), '+351910000002');
select audit.eq('T-SUP-32 revelar morada devolve a morada',
  format($q$select admin_reveal_contact(%L, 'address')->>'address_text'$q$, :'jsup'), 'Rua Suporte 1');
select audit.err('T-SUP-33 tipo inválido é recusado',
  format($q$select admin_reveal_contact(%L, 'email')$q$, :'C2'), 'inválido');
select audit.ok('T-SUP-34 fotos do pedido',
  format($q$select * from admin_get_job_photos(%L)$q$, :'jdone'));
select audit.ok('T-SUP-35 ficha do jardineiro continua a abrir',
  format($q$select admin_get_worker(%L)$q$, :'W1'));
reset role;

select audit.eq('T-SUP-40 consultas e revelações ficam em admin_actions, com o admin certo',
  $q$select string_agg(distinct action, ',' order by action) from admin_actions
     where admin_id='00000000-0000-0000-0000-0000000000ad'
       and action in ('search','view_job','view_client','view_worker','view_job_photos','reveal_phone','reveal_address')$q$,
  'reveal_address,reveal_phone,search,view_client,view_job,view_job_photos,view_worker');
select audit.eq('T-SUP-41 o motivo de revelar fica registado',
  $q$select details->>'reason' from admin_actions where action='reveal_phone'$q$, 'confirmar identidade');
select audit.eq('T-SUP-42 nenhuma consulta lê a Agenda do jardineiro',
  $q$select count(*)::text from pg_proc where proname like 'admin\_%' and prosrc ilike '%worker_calendar%'$q$, '0');

select format('%s | %s | %s', case when ok then 'PASS' else 'FAIL' end, id, coalesce(detail, ''))
from audit.results where id like 'T-SUP-%' order by seq;
select format('TOTAL %s | PASS %s | FAIL %s', count(*), count(*) filter (where ok), count(*) filter (where not ok))
from audit.results where id like 'T-SUP-%';
