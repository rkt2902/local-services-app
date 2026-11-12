-- Auditoria 2026-11-12: cenários com asserções, um bloco por fluxo (FLOW-xxx em
-- docs/systematic-debugging-audit/02-COMPLETE-FLOW-INVENTORY.md).
-- Correm como a app correria: papel `authenticated` (ou `anon`), RLS ligada e
-- auth.uid() de cada pessoa. O que é preparação de dados (mudar datas, simular
-- o passar do tempo) corre como postgres e está marcado "preparação".
-- Só para a BD local de teste. Nunca correr na BD viva.

\set C1 '00000000-0000-0000-0000-0000000000c1'
\set C2 '00000000-0000-0000-0000-0000000000c2'
\set W1 '00000000-0000-0000-0000-0000000000a1'
\set W2 '00000000-0000-0000-0000-0000000000a2'
\set W3 '00000000-0000-0000-0000-0000000000a3'
\set AD '00000000-0000-0000-0000-0000000000ad'

-- preparação: 2 clientes, 3 jardineiros (W3 no Porto), 1 admin
insert into auth.users(id, email) values
 (:'C1','c1@teste.local'),(:'C2','c2@teste.local'),(:'W1','w1@teste.local'),
 (:'W2','w2@teste.local'),(:'W3','w3@teste.local'),(:'AD','ad@teste.local');
insert into profiles(id, role, full_name, phone) values
 (:'C1','client','Cliente Um','+351910000001'),
 (:'C2','client','Cliente Dois','+351910000002'),
 (:'W1','worker','Jardineiro Um','+351910000011'),
 (:'W2','worker','Jardineiro Dois','+351910000012'),
 (:'W3','worker','Jardineiro Porto','+351910000013'),
 (:'AD','worker','Admin','+351910000099');
insert into worker_profiles(profile_id, radius_km, base_lat, base_lng) values
 (:'W1',30,38.72,-9.14),(:'W2',30,38.72,-9.14),(:'W3',10,41.15,-8.61),(:'AD',10,41.15,-8.61);
insert into worker_service_types select p, id
  from (values (:'W1'::uuid),(:'W2'::uuid),(:'W3'::uuid)) v(p), service_types;
insert into admin_users(user_id) values (:'AD');
select id as st from service_types order by sort_order limit 1 \gset

set role authenticated;

-------------------------------------------------------------------------------
-- FLOW-005 / FLOW-006: perfil e papel
-------------------------------------------------------------------------------
select t_as(:'C1');
select audit.err('T-PROF-01 cliente não muda o próprio papel',
  format($q$update profiles set role='worker' where id=%L$q$, :'C1'));
select audit.err('T-PROF-02 cliente não mexe em deleted_at',
  format($q$update profiles set deleted_at=now() where id=%L$q$, :'C1'), 'não se podem alterar');
select audit.eq('T-PROF-03 cliente não lê o perfil de um jardineiro sem trabalho confirmado',
  format($q$select count(*)::text from profiles where id=%L$q$, :'W1'), '0');
select audit.err('T-PROF-04 não cria perfil com id de outra pessoa',
  $q$insert into profiles(id, role, full_name) values ('00000000-0000-0000-0000-0000000000ff','client','X')$q$);
select audit.eq('T-PROF-05 UPDATE ao perfil de outra pessoa não muda nada',
  format($q$with u as (update profiles set full_name='hack' where id=%L returning 1) select count(*)::text from u$q$, :'C2'), '0');
reset role;
set role anon;
select audit.eq('T-PROF-06 anónimo não lê profiles',
  $q$select count(*)::text from profiles$q$, '0');
select audit.eq('T-CARD-01 anónimo lê o cartão público do jardineiro',
  format($q$select count(*)::text from worker_public_card where worker_id=%L$q$, :'W1'), '1');
select audit.eq('T-CARD-02 cartão público não expõe telefone',
  $q$select count(*)::text from information_schema.columns where table_name='worker_public_card' and column_name in ('phone','base_lat','base_lng','radius_km')$q$, '0');
reset role;
set role authenticated;

-------------------------------------------------------------------------------
-- FLOW-010: criar pedido
-------------------------------------------------------------------------------
select t_as(:'C1');
select audit.val('T-JOB-01 cliente cria pedido aberto',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_area,location_lat,location_lng,description,status,date_mode,preferred_date)
     values(%L,%L,'Rua Exata 1, Lisboa','Lisboa',38.7211,-9.1411,'Cortar relva','open','fixed',today_pt()+3) returning id$q$, :'C1', :'st')) as j1 \gset
select audit.err('T-JOB-02 cliente não cria pedido já confirmado',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'x',38.72,-9.14,'x','confirmed','flexible')$q$, :'C1', :'st'));
select audit.err('T-JOB-03 cliente não cria pedido em nome de outro cliente',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'x',38.72,-9.14,'x','open','flexible')$q$, :'C2', :'st'));
select audit.eq('T-JOB-04 UPDATE direto ao pedido não muda nada (só RPC)',
  format($q$with u as (update job_requests set status='completed' where id=%L returning 1) select count(*)::text from u$q$, :'j1'), '0');
select audit.eq('T-JOB-05 DELETE direto ao pedido não apaga nada',
  format($q$with d as (delete from job_requests where id=%L returning 1) select count(*)::text from d$q$, :'j1'), '0');
-- campos de execução no INSERT: started_at / marked_done_at vindos da app
select audit.eq('T-JOB-06 INSERT com started_at preenchido fica sem started_at',
  format($q$with i as (insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,started_at)
     values(%L,%L,'x',38.72,-9.14,'teste started_at','open','flexible',now()) returning started_at) select (started_at is null)::text from i$q$, :'C1', :'st'), 'true');
select audit.eq('T-JOB-07 INSERT com search_extra_km=500 não alarga a pesquisa',
  format($q$with i as (insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,search_extra_km)
     values(%L,%L,'x',38.72,-9.14,'teste extra','open','flexible',500) returning search_extra_km) select search_extra_km::text from i$q$, :'C1', :'st'), '0');
select audit.err('T-JOB-08 pedido com data fixa no passado é recusado',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,preferred_date)
     values(%L,%L,'x',38.72,-9.14,'passado','open','fixed',today_pt()-10)$q$, :'C1', :'st'));
-- fotos
select audit.ok('T-JOB-09 cliente junta 1.ª foto ao pedido',
  format($q$insert into job_photos(job_id, storage_path) values(%L, %L)$q$, :'j1', :'C1' || '/a.jpg'));
select audit.ok('T-JOB-10 cliente junta 2.ª foto',
  format($q$insert into job_photos(job_id, storage_path) values(%L, %L)$q$, :'j1', :'C1' || '/b.jpg'));
select audit.err('T-JOB-11 3.ª foto é recusada',
  format($q$insert into job_photos(job_id, storage_path) values(%L, %L)$q$, :'j1', :'C1' || '/c.jpg'), 'máximo 2');
select t_as(:'C2');
select audit.err('T-JOB-12 outro cliente não junta fotos ao pedido',
  format($q$insert into job_photos(job_id, storage_path) values(%L, %L)$q$, :'j1', :'C2' || '/x.jpg'));
select audit.eq('T-JOB-13 outro cliente não vê o pedido',
  format($q$select count(*)::text from job_requests where id=%L$q$, :'j1'), '0');
-- limite de pedidos por hora (5)
select t_as(:'C2');
select audit.ok('T-JOB-14 preparação: 5 pedidos seguidos',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     select %L,%L,'x',38.72,-9.14,'lote '||g,'open','flexible' from generate_series(1,5) g$q$, :'C2', :'st'));
select audit.err('T-JOB-15 6.º pedido na mesma hora é recusado',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'x',38.72,-9.14,'sexto','open','flexible')$q$, :'C2', :'st'));
select t_as(:'W1');
select audit.err('T-JOB-16 jardineiro não cria pedidos',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'x',38.72,-9.14,'x','open','flexible')$q$, :'W1', :'st'));

-------------------------------------------------------------------------------
-- FLOW-020: descobrir pedidos (privacidade da morada)
-------------------------------------------------------------------------------
select t_as(:'W1');
select audit.eq('T-DISC-01 jardineiro vê o pedido no raio',
  format($q$select count(*)::text from get_jobs_in_radius(38.72,-9.14,30) where id=%L$q$, :'j1'), '1');
select audit.eq('T-DISC-02 morada exata escondida antes da proposta aceite (só a zona)',
  format($q$select (address_text is distinct from 'Rua Exata 1, Lisboa')::text from get_jobs_in_radius(38.72,-9.14,30) where id=%L$q$, :'j1'), 'true');
select audit.eq('T-DISC-03 coordenadas arredondadas antes da proposta aceite',
  format($q$select (location_lat = round(location_lat::numeric,2))::text from get_job_by_id(%L)$q$, :'j1'), 'true');
select audit.eq('T-DISC-04 jardineiro não lê job_requests diretamente',
  format($q$select count(*)::text from job_requests where id=%L$q$, :'j1'), '0');
select audit.eq('T-DISC-05 jardineiro vê as 2 fotos do pedido aberto (resumo, por desenho)',
  format($q$select count(*)::text from job_photos where job_id=%L$q$, :'j1'), '2');
select t_as(:'W3');
select audit.eq('T-DISC-06 jardineiro do Porto não vê o pedido com a base dele',
  format($q$select count(*)::text from get_jobs_in_radius(41.15,-8.61,10) where id=%L$q$, :'j1'), '0');
-- Achado: as coordenadas vêm da app, não da base gravada no perfil.
select audit.eq('T-DISC-07 [ACHADO] jardineiro do Porto vê o pedido de Lisboa se mandar coordenadas de Lisboa',
  format($q$select count(*)::text from get_jobs_in_radius(38.72,-9.14,50) where id=%L$q$, :'j1'), '0');
select t_as(:'C2');
select audit.eq('T-DISC-08 [ACHADO] conta de cliente consegue listar pedidos abertos de outros clientes',
  format($q$select count(*)::text from get_jobs_in_radius(38.72,-9.14,50) where id=%L$q$, :'j1'), '0');

-------------------------------------------------------------------------------
-- FLOW-021 / FLOW-022: propostas
-------------------------------------------------------------------------------
select t_as(:'W1');
select audit.val('T-PROP-01 jardineiro envia proposta à hora',
  format($q$select create_proposal(%L, 15, 2, 4, 1, 'nota', today_pt()+3, '09:00')$q$, :'j1')) as p1 \gset
select audit.err('T-PROP-02 segunda proposta pendente do mesmo jardineiro é recusada',
  format($q$select create_proposal(%L, 16, 2, 4, 1, null, today_pt()+3, '09:00')$q$, :'j1'));
select audit.err('T-PROP-04 INSERT direto em job_proposals é recusado',
  format($q$insert into job_proposals(job_id, worker_id, hourly_rate, status) values(%L,%L,10,'pending')$q$, :'j1', :'W1'));
select t_as(:'W2');
select audit.err('T-PROP-03 proposta com data no passado é recusada',
  format($q$select create_proposal(%L, 15, 2, 4, 1, null, today_pt()-1, '09:00')$q$, :'j1'), 'passou');
select audit.err('T-PROP-05 preço por hora negativo é recusado',
  format($q$select create_proposal(%L, -5, 2, 4, 1, null, today_pt()+3, '09:00')$q$, :'j1'));
select audit.err('T-PROP-06 preço por hora zero é recusado',
  format($q$select create_proposal(%L, 0, 2, 4, 1, null, today_pt()+3, '09:00')$q$, :'j1'));
select audit.err('T-PROP-07 horas mínimas maiores do que as máximas são recusadas',
  format($q$select create_proposal(%L, 15, 6, 2, 1, null, today_pt()+3, '09:00')$q$, :'j1'));
select audit.err('T-PROP-08 valor total sem total_price é recusado',
  format($q$select create_proposal(%L, null, 2, 4, 1, null, today_pt()+3, '09:00', false, false, 'fixed_total', null)$q$, :'j1'));
select audit.err('T-PROP-09 validade no passado é recusada',
  format($q$select create_proposal(p_job_id=>%L, p_hourly_rate=>15, p_scheduled_date=>today_pt()+3, p_valid_until=>today_pt()-1)$q$, :'j1'));
select audit.val('T-PROP-10 segundo jardineiro envia proposta a valor total',
  format($q$select create_proposal(p_job_id=>%L, p_estimated_hours_min=>2, p_estimated_hours_max=>4, p_people_needed=>2, p_scheduled_date=>today_pt()+3, p_scheduled_time=>'14:00', p_pricing_mode=>'fixed_total', p_total_price=>120)$q$, :'j1')) as p2 \gset
select t_as(:'C1');
select audit.err('T-PROP-11 cliente não envia propostas',
  format($q$select create_proposal(%L, 15, 2, 4, 1, null, today_pt()+3, '09:00')$q$, :'j1'));
select audit.eq('T-PROP-12 cliente vê as 2 propostas pendentes com nome do jardineiro',
  format($q$select count(*)::text from get_pending_proposals_for_job(%L) where worker_name is not null$q$, :'j1'), '2');
select t_as(:'C2');
select audit.err('T-PROP-13 outro cliente não aceita a proposta',
  format($q$select accept_proposal(%L, %L)$q$, :'p1', :'j1'));
select audit.eq('T-PROP-14 outro cliente não lê as propostas',
  format($q$select count(*)::text from get_pending_proposals_for_job(%L)$q$, :'j1'), '0');
select t_as(:'W1');
select audit.err('T-PROP-15 jardineiro não aceita a própria proposta',
  format($q$select accept_proposal(%L, %L)$q$, :'p1', :'j1'));
select audit.err('T-PROP-16 proposta não pode ser aceite com o id de outro pedido',
  format($q$select accept_proposal(%L, %L)$q$, :'p1', (select id from job_requests where client_id=:'C2' limit 1)));
select t_as(:'C1');
select audit.ok('T-PROP-17 cliente aceita a proposta do W2 (valor total, 2 pessoas)',
  format($q$select accept_proposal(%L, %L)$q$, :'p2', :'j1'));
reset role;
select audit.eq('T-PROP-18 pedido fica confirmado com a proposta certa',
  format($q$select status || '/' || (accepted_proposal_id = %L)::text from job_requests where id=%L$q$, :'p2', :'j1'), 'confirmed/true');
select audit.eq('T-PROP-19 a outra proposta fica recusada',
  format($q$select status from job_proposals where id=%L$q$, :'p1'), 'rejected');
select audit.eq('T-PROP-20 W1 é avisado (proposal_rejected) e W2 (proposal_accepted)',
  format($q$select string_agg(type, ',' order by type) from notifications where related_id=%L and type in ('proposal_rejected','proposal_accepted')$q$, :'j1'), 'proposal_accepted,proposal_rejected');
select audit.eq('T-PROP-21 pedido de ajudante criado automaticamente (2 pessoas)',
  format($q$select count(*)::text from help_requests where job_id=%L$q$, :'j1'), '1');
set role authenticated;
select t_as(:'C1');
select audit.err('T-PROP-22 aceitar outra vez (duplo toque) é recusado',
  format($q$select accept_proposal(%L, %L)$q$, :'p1', :'j1'));
select t_as(:'W2');
select audit.err('T-PROP-23 retirar proposta já aceite é recusado',
  format($q$select withdraw_proposal(%L, %L)$q$, :'p2', :'j1'));
-- morada e perfis depois de aceite
select audit.eq('T-PROP-24 jardineiro aceite vê a morada exata',
  format($q$select address_text from get_job_by_id(%L)$q$, :'j1'), 'Rua Exata 1, Lisboa');
select audit.eq('T-PROP-25 jardineiro aceite lê o telefone da cliente',
  format($q$select phone from profiles where id=%L$q$, :'C1'), '+351910000001');
select t_as(:'W1');
select audit.eq('T-PROP-26 jardineiro recusado volta a ver só a zona',
  format($q$select (address_text is distinct from 'Rua Exata 1, Lisboa')::text from get_job_by_id(%L)$q$, :'j1'), 'true');
select audit.eq('T-PROP-27 jardineiro recusado não lê o telefone da cliente',
  format($q$select count(*)::text from profiles where id=%L$q$, :'C1'), '0');
select t_as(:'C1');
select audit.eq('T-PROP-28 cliente lê o telefone do jardineiro aceite',
  format($q$select phone from profiles where id=%L$q$, :'W2'), '+351910000012');

-------------------------------------------------------------------------------
-- FLOW-040: ajudantes
-------------------------------------------------------------------------------
reset role;
select id as hr from help_requests where job_id = :'j1' \gset
select status as hr_status from help_requests where id = :'hr' \gset
set role authenticated;
select t_as(:'C1');
select audit.err('T-HELP-01 cliente não se candidata a ajudante',
  format($q$select apply_to_help_request(%L, true, 'x')$q$, :'hr'));
select t_as(:'W2');
select audit.err('T-HELP-02 o responsável não se candidata ao próprio pedido',
  format($q$select apply_to_help_request(%L, true, 'x')$q$, :'hr'));
select t_as(:'W1');
select audit.val('T-HELP-03 outro jardineiro candidata-se',
  format($q$select apply_to_help_request(%L, true, 'posso ajudar')$q$, :'hr')) as acc \gset
select audit.err('T-HELP-04 candidatura repetida é recusada',
  format($q$select apply_to_help_request(%L, true, 'outra vez')$q$, :'hr'));
select audit.err('T-HELP-05 candidato não se aceita a si próprio',
  format($q$select accept_help_candidate(%L, 10)$q$, :'acc'));
select t_as(:'W2');
select audit.err('T-HELP-06 taxa negativa para o ajudante é recusada',
  format($q$select accept_help_candidate(%L, -1)$q$, :'acc'));
select audit.ok('T-HELP-07 responsável aceita o ajudante',
  format($q$select accept_help_candidate(%L, 10)$q$, :'acc'));
reset role;
select audit.eq('T-HELP-08 pedido de ajuda fica preenchido',
  format($q$select status from help_requests where id=%L$q$, :'hr'), 'filled');
set role authenticated;
select t_as(:'W1');
select audit.eq('T-HELP-09 ajudante não lê o telefone da cliente',
  format($q$select count(*)::text from profiles where id=%L$q$, :'C1'), '0');

-------------------------------------------------------------------------------
-- FLOW-030: remarcar
-------------------------------------------------------------------------------
select t_as(:'C2');
select audit.err('T-RESCH-01 outro cliente não propõe remarcação',
  format($q$select propose_reschedule(%L, today_pt()+4)$q$, :'j1'));
select t_as(:'W2');
select audit.err('T-RESCH-02 remarcação para o passado é recusada',
  format($q$select propose_reschedule(%L, today_pt()-1)$q$, :'j1'));
select audit.ok('T-RESCH-03 responsável propõe nova data',
  format($q$select propose_reschedule(%L, today_pt()+4, '10:00')$q$, :'j1'));
select audit.err('T-RESCH-04 quem propôs não aceita a própria remarcação',
  format($q$select accept_reschedule(%L)$q$, :'j1'));
select t_as(:'C1');
select audit.ok('T-RESCH-05 cliente aceita a remarcação',
  format($q$select accept_reschedule(%L)$q$, :'j1'));
reset role;
select audit.eq('T-RESCH-06 nova data gravada',
  format($q$select (confirmed_date = today_pt()+4)::text from job_requests where id=%L$q$, :'j1'), 'true');

-------------------------------------------------------------------------------
-- FLOW-031 / FLOW-032: iniciar, concluir, confirmar
-------------------------------------------------------------------------------
set role authenticated;
select t_as(:'W2');
select audit.err('T-EXEC-01 não inicia 4 dias antes',
  format($q$select start_job(%L, '{}')$q$, :'j1'));
reset role;
update job_requests set confirmed_date = today_pt(), confirmed_time = '00:00' where id = :'j1'; -- preparação: o dia chegou
set role authenticated;
select t_as(:'C1');
select audit.err('T-EXEC-02 cliente não inicia o trabalho',
  format($q$select start_job(%L, '{}')$q$, :'j1'));
select t_as(:'W1');
select audit.err('T-EXEC-03 ajudante não inicia o trabalho',
  format($q$select start_job(%L, '{}')$q$, :'j1'));
select t_as(:'W2');
select audit.err('T-EXEC-04 fotos de antes com caminho de outra pessoa são recusadas',
  format($q$select start_job(%L, array[%L])$q$, :'j1', :'C2' || '/x.jpg'));
select audit.err('T-EXEC-05 não marca concluído antes de iniciar',
  format($q$select mark_job_done(%L, '{}')$q$, :'j1'));
select audit.ok('T-EXEC-06 responsável inicia',
  format($q$select start_job(%L, '{}')$q$, :'j1'));
select audit.err('T-EXEC-07 iniciar duas vezes é recusado',
  format($q$select start_job(%L, '{}')$q$, :'j1'));
select t_as(:'C1');
select audit.err('T-EXEC-08 cliente não cancela trabalho já iniciado',
  format($q$select cancel_job(%L, 'other')$q$, :'j1'));
select audit.err('T-EXEC-09 cliente não confirma antes de estar marcado concluído',
  format($q$select confirm_job_completion(%L)$q$, :'j1'));
select t_as(:'W1');
select audit.err('T-EXEC-10 ajudante não marca concluído',
  format($q$select mark_job_done(%L, '{}')$q$, :'j1'));
select t_as(:'W2');
select audit.ok('T-EXEC-11 responsável marca concluído',
  format($q$select mark_job_done(%L, '{}')$q$, :'j1'));
select audit.err('T-EXEC-12 marcar concluído duas vezes é recusado',
  format($q$select mark_job_done(%L, '{}')$q$, :'j1'));
select audit.err('T-EXEC-13 jardineiro não confirma em nome da cliente',
  format($q$select confirm_job_completion(%L)$q$, :'j1'));
select t_as(:'C2');
select audit.err('T-EXEC-14 outra cliente não confirma',
  format($q$select confirm_job_completion(%L)$q$, :'j1'));
select t_as(:'C1');
select audit.ok('T-EXEC-15 cliente confirma',
  format($q$select confirm_job_completion(%L)$q$, :'j1'));
select audit.err('T-EXEC-16 confirmar duas vezes é recusado',
  format($q$select confirm_job_completion(%L)$q$, :'j1'));
reset role;
select audit.eq('T-EXEC-17 pedido concluído',
  format($q$select status from job_requests where id=%L$q$, :'j1'), 'completed');

-------------------------------------------------------------------------------
-- FLOW-033: avaliações
-------------------------------------------------------------------------------
set role authenticated;
select t_as(:'C1');
select audit.err('T-RATE-01 6 estrelas é recusado',
  format($q$select submit_client_rating(%L, 6)$q$, :'j1'));
select audit.err('T-RATE-02 0 estrelas é recusado',
  format($q$select submit_client_rating(%L, 0)$q$, :'j1'));
select audit.ok('T-RATE-03 cliente avalia o jardineiro',
  format($q$select submit_client_rating(%L, 5, 'muito bom')$q$, :'j1'));
select audit.err('T-RATE-04a avaliar duas vezes dá erro claro (0074)',
  format($q$select submit_client_rating(%L, 1)$q$, :'j1'), 'Já avaliaste');
select audit.eq('T-RATE-04b a segunda avaliação é ignorada (fica a primeira)',
  format($q$select string_agg(stars::text, ',') from ratings where job_id=%L and rater_id=%L$q$, :'j1', :'C1'), '5');
select audit.err('T-RATE-05 INSERT direto em ratings é recusado',
  format($q$insert into ratings(job_id, rater_id, ratee_id, stars) values(%L,%L,%L,1)$q$, :'j1', :'C1', :'W1'));
select t_as(:'C2');
select audit.err('T-RATE-06 quem não participou não avalia',
  format($q$select submit_client_rating(%L, 1, 'falso')$q$, :'j1'));
select t_as(:'W2');
select audit.ok('T-RATE-07 responsável avalia a cliente',
  format($q$select submit_principal_rating(%L, %L, 5)$q$, :'j1', :'C1'));
select audit.ok('T-RATE-08 responsável avalia o ajudante',
  format($q$select submit_principal_rating(%L, %L, 4)$q$, :'j1', :'W1'));
select audit.err('T-RATE-09 responsável não avalia quem não participou',
  format($q$select submit_principal_rating(%L, %L, 1)$q$, :'j1', :'C2'));
select t_as(:'W1');
select audit.ok('T-RATE-10 ajudante avalia o responsável',
  format($q$select submit_helper_rating(%L, 5)$q$, :'j1'));
reset role;
set role anon;
select audit.eq('T-RATE-11 [ACHADO] anónimo lê todas as avaliações (com ids de quem avalia)',
  $q$select count(*)::text from ratings$q$, '0');
reset role;
set role authenticated;

-------------------------------------------------------------------------------
-- FLOW-034: cancelar
-------------------------------------------------------------------------------
select t_as(:'C1');
select audit.val('T-CANC-00 preparação: pedido novo',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'Rua B',38.72,-9.14,'para cancelar','open','flexible') returning id$q$, :'C1', :'st')) as j2 \gset
select t_as(:'W1');
select audit.val('T-CANC-01 preparação: proposta pendente',
  format($q$select create_proposal(%L, 12, 1, 2, 1, null, null, null, true)$q$, :'j2')) as p3 \gset
select t_as(:'C2');
select audit.err('T-CANC-02 outra cliente não cancela',
  format($q$select cancel_job(%L, 'other')$q$, :'j2'));
select t_as(:'W2');
select audit.err('T-CANC-03 jardineiro sem proposta aceite não cancela',
  format($q$select cancel_job(%L, 'other')$q$, :'j2'));
select t_as(:'C1');
select audit.ok('T-CANC-04 cliente cancela pedido aberto',
  format($q$select cancel_job(%L, 'other', 'mudei de ideias')$q$, :'j2'));
reset role;
select audit.eq('T-CANC-05 proposta pendente fica recusada',
  format($q$select status from job_proposals where id=%L$q$, :'p3'), 'rejected');
set role authenticated;
select t_as(:'C1');
select audit.err('T-CANC-06 cancelar duas vezes é recusado',
  format($q$select cancel_job(%L, 'other')$q$, :'j2'));
select audit.err('T-CANC-07 editar pedido cancelado é recusado',
  format($q$select update_job_request(%L, 'nova', 'flexible', null, null, 'Rua B', 38.72, -9.14, 'Lisboa')$q$, :'j2'));

-------------------------------------------------------------------------------
-- FLOW-012: editar pedido aberto
-------------------------------------------------------------------------------
select audit.val('T-EDIT-00 preparação: pedido novo',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'Rua C',38.72,-9.14,'para editar','open','flexible') returning id$q$, :'C1', :'st')) as j3 \gset
select audit.ok('T-EDIT-01 dono edita o pedido aberto',
  format($q$select update_job_request(%L, 'descrição nova', 'flexible', null, null, 'Rua C 2', 38.72, -9.14, 'Lisboa')$q$, :'j3'));
select t_as(:'C2');
select audit.err('T-EDIT-02 outra cliente não edita',
  format($q$select update_job_request(%L, 'hack', 'flexible', null, null, 'x', 38.72, -9.14, 'x')$q$, :'j3'));
select t_as(:'C1');
select audit.err('T-EDIT-03 editar com data fixa no passado é recusado',
  format($q$select update_job_request(%L, 'descrição com tamanho certo', 'fixed', today_pt()-2, null, 'Rua C', 38.72, -9.14, 'Lisboa')$q$, :'j3'));
select audit.ok('T-EDIT-04 alargar pesquisa (+10 km)',
  format($q$select widen_job_search(%L)$q$, :'j3'));
select t_as(:'C2');
select audit.err('T-EDIT-05 outra cliente não alarga a pesquisa',
  format($q$select widen_job_search(%L)$q$, :'j3'));

-------------------------------------------------------------------------------
-- FLOW-060: plano Grátis (5 trabalhos aceites por mês)
-------------------------------------------------------------------------------
reset role;
-- preparação: W3 já tem 5 propostas aceites este mês
insert into job_requests(id, client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
 select gen_random_uuid(), :'C2', :'st', 'x', 41.15, -8.61, 'plano '||g, 'open','flexible' from generate_series(1,6) g;
insert into job_proposals(job_id, worker_id, hourly_rate, status, accepted_at)
 select id, :'W3', 10, 'accepted', now() from job_requests where description like 'plano %' order by description limit 5;
select id as j6 from job_requests where description = 'plano 6' \gset
set role authenticated;
select t_as(:'W3');
select audit.err('T-PLAN-01 jardineiro Grátis com 5 aceites no mês não envia proposta nova',
  format($q$select create_proposal(%L, 10, 1, 2, 1, null, null, null, true)$q$, :'j6'));
select audit.eq('T-PLAN-02 get_my_plan mostra 5 de 5',
  $q$select tier || ':' || jobs_this_month || '/' || monthly_job_limit from get_my_plan()$q$, 'free:5/5');
select audit.err('T-PLAN-03 painel de ganhos recusado no Grátis',
  $q$select * from get_my_earnings(today_pt()-30, today_pt())$q$);

-------------------------------------------------------------------------------
-- FLOW-070: admin
-------------------------------------------------------------------------------
select t_as(:'W1');
select audit.eq('T-ADM-01 admin_whoami de não-admin diz que não é admin',
  $q$select is_admin::text from admin_whoami()$q$, 'false');
select audit.err('T-ADM-02 não-admin não lê o painel',
  $q$select admin_overview(30)$q$);
select audit.err('T-ADM-03 não-admin não muda planos',
  format($q$select admin_set_worker_plan(%L, 'pro')$q$, :'W1'));
select t_as(:'AD');
select audit.err('T-ADM-04 admin sem segundo fator (aal1) não lê o painel',
  $q$select admin_overview(30)$q$);
select t_aal2(:'AD');
select audit.ok('T-ADM-05 admin com segundo fator lê o painel',
  $q$select admin_overview(30)$q$);
select audit.ok('T-ADM-06 admin com segundo fator dá Pro ao W3',
  format($q$select admin_set_worker_plan(%L, 'pro', today_pt(), today_pt()+30)$q$, :'W3'));
select audit.err('T-ADM-07 plano inválido é recusado',
  format($q$select admin_set_worker_plan(%L, 'gold')$q$, :'W3'));
select t_as(:'W3');
select audit.ok('T-PLAN-04 com Pro, o W3 já envia proposta',
  format($q$select create_proposal(%L, 10, 1, 2, 1, null, null, null, true)$q$, :'j6'));
reset role;
select audit.eq('T-ADM-08 mudança de plano registada em admin_actions',
  $q$select count(*)::text from admin_actions$q$, '1');
set role authenticated;

-------------------------------------------------------------------------------
-- FLOW-080: notificações e push
-------------------------------------------------------------------------------
select t_as(:'C1');
select audit.err('T-NOTIF-01 utilizador não cria notificações',
  format($q$insert into notifications(user_id, type, title, body) values(%L,'job_completed','x','y')$q$, :'C2'));
select audit.eq('T-NOTIF-02 utilizador só lê as suas',
  format($q$select count(*)::text from notifications where user_id <> %L$q$, :'C1'), '0');
select audit.err('T-NOTIF-03 não consegue passar uma notificação sua para outra pessoa',
  format($q$update notifications set user_id=%L where user_id=%L$q$, :'C2', :'C1'), 'permission denied');
select audit.ok('T-NOTIF-03b marca as suas como lidas',
  format($q$update notifications set read=true where user_id=%L$q$, :'C1'));
select audit.ok('T-NOTIF-04 Limpar tudo',
  $q$select clear_my_notifications()$q$);
select audit.ok('T-PUSH-01 regista token do aparelho',
  $q$select register_device_token('token-teste-c1', 'android')$q$);
select audit.err('T-PUSH-02 plataforma inválida é recusada',
  $q$select register_device_token('token-teste-x', 'symbian')$q$);
select t_as(:'C2');
select audit.eq('T-PUSH-03 outro utilizador não vê o token',
  $q$select count(*)::text from device_tokens$q$, '0');

-------------------------------------------------------------------------------
-- FLOW-050: Agenda
-------------------------------------------------------------------------------
select t_as(:'W1');
select audit.val('T-AG-01 jardineiro cria trabalho de fora da app',
  $q$insert into worker_calendar_entries(kind, title, starts_on, start_time, duration_minutes) values('job','Sr. Silva', today_pt()+1, '09:00', 120) returning id$q$) as ag1 \gset
select audit.eq('T-AG-02 aparece na agenda do dia',
  $q$select count(*)::text from get_worker_agenda(today_pt(), today_pt()+2) where entry_kind='external'$q$, '1');
select audit.err('T-AG-03 agenda com mais de 62 dias é recusada',
  $q$select * from get_worker_agenda(today_pt(), today_pt()+100)$q$);
select t_as(:'W2');
select audit.eq('T-AG-04 outro jardineiro não vê a entrada',
  $q$select count(*)::text from worker_calendar_entries$q$, '0');
select audit.eq('T-AG-05 outro jardineiro não apaga a entrada',
  format($q$with d as (delete from worker_calendar_entries where id=%L returning 1) select count(*)::text from d$q$, :'ag1'), '0');
select t_as(:'C1');
select audit.err('T-AG-06 cliente não cria entradas na agenda',
  $q$insert into worker_calendar_entries(kind, title, starts_on) values('job','x', today_pt())$q$);

-------------------------------------------------------------------------------
-- FLOW-090: cartão frota (demo)
-------------------------------------------------------------------------------
select t_as(:'W1');
select audit.err('T-FLEET-01 jardineiro não cria cartão já ativo',
  format($q$insert into worker_fleet_cards(worker_id, status) values(%L,'active')$q$, :'W1'));

-------------------------------------------------------------------------------
-- FLOW-091: cartão público e visitas
-------------------------------------------------------------------------------
reset role;
set role anon;
select t_as('');
select audit.val('T-CARD-03 anónimo regista visita ao cartão',
  format($q$select log_worker_card_visit(%L, 'qr', 'aparelho-1')::text$q$, :'W1')) as visit \gset
select audit.ok('T-CARD-04 origem inválida não dá erro (é gravada como link)',
  format($q$select log_worker_card_visit(%L, 'hack', 'aparelho-2')$q$, :'W1'));
reset role;
set role authenticated;

-------------------------------------------------------------------------------
-- FLOW-100: Storage
-------------------------------------------------------------------------------
select t_as(:'C1');
select audit.ok('T-STOR-01 cliente envia foto para a pasta dele',
  format($q$insert into storage.objects(bucket_id, name, owner) values('job-photos', %L, %L)$q$, :'C1' || '/novo.jpg', :'C1'));
select audit.err('T-STOR-02 cliente não envia para a pasta de outra pessoa',
  format($q$insert into storage.objects(bucket_id, name, owner) values('job-photos', %L, %L)$q$, :'C2' || '/novo.jpg', :'C1'));
select audit.err('T-STOR-03 avatar com nome de outra pessoa é recusado',
  format($q$insert into storage.objects(bucket_id, name, owner) values('avatars', %L, %L)$q$, :'C2' || '.jpg', :'C1'));
reset role;
select audit.eq('T-STOR-04 [INFO] buckets públicos (leitura sem sessão por URL)',
  $q$select string_agg(id || '=' || public::text, ',' order by id) from storage.buckets$q$, 'avatars=true,job-photos=true');

-------------------------------------------------------------------------------
-- FLOW-110: crons
-------------------------------------------------------------------------------
set role authenticated;
select t_as(:'C1');
select audit.err('T-CRON-01 utilizador não corre auto_expire_jobs', $q$select auto_expire_jobs()$q$);
select audit.err('T-CRON-02 utilizador não corre auto_confirm_completed_jobs', $q$select auto_confirm_completed_jobs()$q$);
select audit.err('T-CRON-03 utilizador não corre send_start_reminders', $q$select send_start_reminders()$q$);
select audit.err('T-CRON-04 utilizador não corre expire_direct_job_requests', $q$select expire_direct_job_requests()$q$);
reset role;
select t_as('');
select audit.ok('T-CRON-05 todos os jobs do pg_cron correm sem erro (como postgres)',
  $q$do $d$ declare r record; begin for r in select command from cron.job loop execute r.command; end loop; end $d$$q$);

-------------------------------------------------------------------------------
-- FLOW-008: eliminar conta
-------------------------------------------------------------------------------
update job_requests set created_at = created_at - interval '2 hours'; -- preparação: limite por hora
set role authenticated;
select t_as(:'C1');
select audit.val('T-DEL-00 preparação: pedido aberto da C1',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'Rua D',38.72,-9.14,'antes de eliminar','open','flexible') returning id$q$, :'C1', :'st')) as j7 \gset
select audit.ok('T-DEL-01 check_can_delete_my_account responde', $q$select check_can_delete_my_account()$q$);
select audit.ok('T-DEL-02 cliente elimina a conta', $q$select delete_my_account()$q$);
reset role;
select audit.eq('T-DEL-03 pedido aberto fica fechado',
  format($q$select (status <> 'open')::text from job_requests where id=%L$q$, :'j7'), 'true');
select audit.eq('T-DEL-04 perfil anonimizado (sem telefone)',
  format($q$select (deleted_at is not null and phone is null)::text from profiles where id=%L$q$, :'C1'), 'true');
select audit.eq('T-DEL-05 tokens do aparelho apagados',
  format($q$select count(*)::text from device_tokens where user_id=%L$q$, :'C1'), '0');

-------------------------------------------------------------------------------
\echo
\echo ===== RESULTADOS =====
select case when ok then 'PASS' else 'FAIL' end || ' | ' || id || coalesce(' | ' || detail, '') from audit.results order by seq;
select 'TOTAL ' || count(*) || ' | PASS ' || count(*) filter (where ok) || ' | FAIL ' || count(*) filter (where not ok) from audit.results;
