-- Painel de admin (migration 0082), 16/11/2026: cartões frota no painel,
-- gasolineiras parceiras e zonas do mapa. Corre depois do 10_flows.sql
-- (bash run.sh keep), na mesma BD. Cria contas próprias (C8, WA, WB, WC)
-- com tudo nos Açores, longe dos outros ficheiros, para as contas das
-- zonas não dependerem deles.

\set W1 '00000000-0000-0000-0000-0000000000a1'
\set AD '00000000-0000-0000-0000-0000000000ad'
\set C8 '00000000-0000-0000-0000-0000000000c8'
\set WA '00000000-0000-0000-0000-0000000000b1'
\set WB '00000000-0000-0000-0000-0000000000b2'
\set WC '00000000-0000-0000-0000-0000000000b3'

reset role;
select t_as('');
select id as st from service_types order by sort_order limit 1 \gset

-- ── Preparação (como postgres) ──
insert into auth.users(id, email, email_confirmed_at) values
 (:'C8', 'c8@teste.local', now()), (:'WA', 'wa@teste.local', now()),
 (:'WB', 'wb@teste.local', now()), (:'WC', 'wc@teste.local', now());
insert into profiles(id, role, full_name, phone) values
 (:'C8', 'client', 'Cliente Oito', '+351910000008'),
 (:'WA', 'worker', 'Jardineiro A', '+351910000021'),
 (:'WB', 'worker', 'Jardineiro B', '+351910000022'),
 (:'WC', 'worker', 'Jardineiro C', '+351910000023');
-- WA e WC (suspenso) em Angra; WB sem base marcada.
insert into worker_profiles(profile_id, radius_km, base_lat, base_lng, location_name) values
 (:'WA', 10, 38.70, -27.20, 'Angra Teste'),
 (:'WB', 10, 0, 0, null),
 (:'WC', 10, 38.70, -27.20, 'Angra Teste');
insert into worker_plans(worker_id, tier) values (:'WA', 'pro_plus');
insert into account_status(profile_id, suspended_at, suspended_reason) values (:'WC', now(), 'other');

-- Cartões: WA tem um antigo recusado e um novo por aprovar; WB um por aprovar.
insert into worker_fleet_cards(worker_id, barcode_value, card_number, holder_name, status, created_at)
values (:'WA', 'OLD-1', '1111', 'A ANTIGO', 'rejected', now() - interval '2 days') returning id as fa_old \gset
insert into worker_fleet_cards(worker_id, barcode_value, card_number, holder_name, status)
values (:'WA', 'NEW-1', '2222', 'JARDINEIRO A', 'pending') returning id as fa \gset
insert into worker_fleet_cards(worker_id, barcode_value, card_number, holder_name, status)
values (:'WB', 'B-1', '3333', 'JARDINEIRO B', 'pending') returning id as fb \gset

-- Pedidos da C8 em Angra: aberto há 2 dias sem propostas, um sem
-- resposta, um concluído com proposta 3 h depois. Em Ponta Delgada: um
-- aberto há 1 h (ainda não conta como sem resposta).
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode, created_at)
values (:'C8', :'st', 'Rua A 1', 'Angra Teste', 38.71, -27.21, 'aberto antigo', 'open', 'flexible', now() - interval '2 days') returning id as j1 \gset
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode)
values (:'C8', :'st', 'Rua A 2', 'Angra Teste', 38.71, -27.21, 'sem resposta', 'open', 'flexible') returning id as j2 \gset
update job_requests set status = 'no_response' where id = :'j2';
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode, created_at)
values (:'C8', :'st', 'Rua A 3', 'Angra Teste', 38.71, -27.21, 'concluído', 'open', 'flexible', now() - interval '1 day') returning id as j3 \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status, created_at)
values (:'j3', :'WA', 15, 'accepted', now() - interval '21 hours') returning id as p3 \gset
update job_requests set status = 'completed', accepted_proposal_id = :'p3' where id = :'j3';
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode, created_at)
values (:'C8', :'st', 'Rua B 1', 'Ponta Teste', 37.80, -25.50, 'aberto recente', 'open', 'flexible', now() - interval '1 hour') returning id as j4 \gset

select count(*) as acts0 from admin_actions \gset

-- ── Recusas: sem sessão, utilizador normal, admin sem aal2 ──
create temp table z_calls(name text, sql text);
insert into z_calls values
  ('admin_list_fleet_cards',        $q$select * from admin_list_fleet_cards()$q$),
  ('admin_review_fleet_card',       format($q$select admin_review_fleet_card(%L, 'active')$q$, :'fa')),
  ('admin_list_partner_locations',  $q$select * from admin_list_partner_locations()$q$),
  ('admin_save_partner_location',   $q$select admin_save_partner_location(null, 'Posto', null, 'fuel_station', 'active', null, null, 38.7, -27.2, null)$q$),
  ('admin_delete_partner_location', $q$select admin_delete_partner_location('00000000-0000-0000-0000-000000000000')$q$),
  ('admin_map_zones',               $q$select * from admin_map_zones()$q$);
grant select on z_calls to anon, authenticated;

set role anon;
select t_as('');
select audit.err('T-PZ-01 sem sessão: ' || name, sql, 'permission denied') from z_calls;
reset role;
set role authenticated;
select t_as(:'W1');
select audit.err('T-PZ-02 utilizador normal: ' || name, sql, 'Sem acesso') from z_calls;
select t_as(:'AD');
select audit.err('T-PZ-03 admin sem segundo fator: ' || name, sql, 'Sem acesso') from z_calls;
reset role;
select audit.eq('T-PZ-04 recusas não mudam nem registam nada',
  format($q$select (select count(*) from admin_actions) || ':' || (select status from worker_fleet_cards where id = %L)$q$, :'fa'),
  :'acts0' || ':pending');

set role authenticated;
select t_as(:'WB');
select audit.err('T-PZ-05 jardineiro não escreve a decisão no pedido do cartão',
  format($q$insert into worker_fleet_cards(worker_id, barcode_value, status, review_message) values (%L, 'X', 'pending', 'aprovado')$q$, :'WB'),
  'row-level security');
select audit.err('T-PZ-06 gasolineiras são só do servidor',
  $q$select count(*) from partner_locations$q$, 'permission denied');
select t_as(:'WC');
select audit.err('T-PZ-07 conta suspensa não pede cartão',
  format($q$insert into worker_fleet_cards(worker_id, barcode_value, status) values (%L, 'X', 'pending')$q$, :'WC'),
  'suspensa');

-- ── Cartões frota ──
select t_aal2(:'AD');
select audit.eq('T-PZ-10 por aprovar: os dois mais recentes, o do WA com 2 tentativas e plano Pro+',
  format($q$select string_agg(worker_name || '/' || attempts || '/' || plan || '/' || is_latest, ',' order by worker_name)
     from admin_list_fleet_cards('pending') where worker_id in (%L, %L)$q$, :'WA', :'WB'),
  'Jardineiro A/2/pro_plus/true,Jardineiro B/1/free/true');
select audit.eq('T-PZ-11 todos: o antigo do WA vem marcado como não atual',
  format($q$select is_latest::text from admin_list_fleet_cards(null) where id = %L$q$, :'fa_old'), 'false');
select audit.err('T-PZ-12 estado inválido', $q$select * from admin_list_fleet_cards('perdido')$q$, 'desconhecido');
select audit.err('T-PZ-13 só se decide o cartão mais recente',
  format($q$select admin_review_fleet_card(%L, 'active')$q$, :'fa_old'), 'outro cartão depois');
select audit.err('T-PZ-14 recusar sem motivo',
  format($q$select admin_review_fleet_card(%L, 'rejected')$q$, :'fb'), 'motivo da lista');
select audit.err('T-PZ-15 motivo "outro" sem mensagem',
  format($q$select admin_review_fleet_card(%L, 'rejected', 'other', 'curto')$q$, :'fb'), '10 carateres');
select audit.err('T-PZ-16 decisão desconhecida',
  format($q$select admin_review_fleet_card(%L, 'talvez')$q$, :'fb'), 'desconhecida');
select audit.eq('T-PZ-17 aprovar o do WA',
  format($q$select admin_review_fleet_card(%L, 'active')$q$, :'fa'), 'active');
select audit.err('T-PZ-18 aprovar outra vez',
  format($q$select admin_review_fleet_card(%L, 'active')$q$, :'fa'), 'já não está à espera');
select audit.eq('T-PZ-19 retirar o do WA (a gasolineira não aceitou)',
  format($q$select admin_review_fleet_card(%L, 'rejected', 'partner_refused')$q$, :'fa'), 'rejected');
select audit.eq('T-PZ-20 recusar o do WB (plano)',
  format($q$select admin_review_fleet_card(%L, 'rejected', 'not_eligible')$q$, :'fb'), 'rejected');
select audit.err('T-PZ-21 recusar o que já está recusado',
  format($q$select admin_review_fleet_card(%L, 'rejected', 'other', 'Mais uma razão qualquer.')$q$, :'fb'), 'já está recusado');
reset role;
select audit.eq('T-PZ-22 avisos ao jardineiro: ativo, desativado, recusado',
  format($q$select string_agg(title, ',' order by created_at, title) from notifications
     where type = 'fleet_card_reviewed' and user_id in (%L, %L)$q$, :'WA', :'WB'),
  'Cartão frota ativo,Cartão frota desativado,Cartão frota recusado');
select audit.eq('T-PZ-23 registo: aprovado, retirado, recusado (com o cartão)',
  format($q$select string_agg(action, ',' order by created_at, id) from admin_actions
     where action like 'fleet\_card\_%%' and details->>'card_id' in (%L, %L)$q$, :'fa', :'fb'),
  'fleet_card_approved,fleet_card_revoked,fleet_card_rejected');
select audit.eq('T-PZ-24 ver a lista fica no Registo',
  $q$select (count(*) > 0)::text from admin_actions where action = 'view_fleet_cards'$q$, 'true');
set role authenticated;
select t_as(:'WB');
select audit.eq('T-PZ-25 o jardineiro lê a mensagem da recusa no seu cartão',
  $q$select status || ':' || (review_message like '%Pro+%') || ':' || (reviewed_at is not null) from worker_fleet_cards order by created_at desc limit 1$q$,
  'rejected:true:true');

-- ── Gasolineiras ──
select t_aal2(:'AD');
select audit.err('T-PZ-30 fora de Portugal',
  $q$select admin_save_partner_location(null, 'Posto', null, 'fuel_station', 'active', null, null, 40.4, -3.7, null)$q$, 'em Portugal');
select audit.err('T-PZ-31 nome curto',
  $q$select admin_save_partner_location(null, 'P', null, 'fuel_station', 'active', null, null, 38.7, -27.2, null)$q$, 'nome');
select audit.err('T-PZ-32 estado inválido',
  $q$select admin_save_partner_location(null, 'Posto', null, 'fuel_station', 'aberto', null, null, 38.7, -27.2, null)$q$, 'Estado');
select audit.err('T-PZ-33 tipo inválido',
  $q$select admin_save_partner_location(null, 'Posto', null, 'banco', 'active', null, null, 38.7, -27.2, null)$q$, 'Tipo');
select admin_save_partner_location(null, '  Posto Angra  ', 'Marca X', 'fuel_station', 'active', 'Estrada 1', 'Angra Teste', 38.705, -27.205, null) as pa1 \gset
select admin_save_partner_location(null, 'Posto Ponta', 'Marca Y', 'fuel_station', 'prospect', null, 'Ponta Teste', 37.80, -25.50, 'Falar com o gerente') as pa2 \gset
select admin_save_partner_location(null, 'Posto Fechado', null, 'fuel_station', 'ended', null, 'Angra Teste', 38.705, -27.205, null) as pa3 \gset
select audit.eq('T-PZ-34 alterar mantém o id',
  format($q$select (admin_save_partner_location(%L, 'Posto Angra', 'Marca X', 'fuel_station', 'active', 'Estrada 1', 'Angra Teste', 38.705, -27.205, 'Parceira desde novembro') = %L)::text$q$, :'pa1', :'pa1'),
  'true');
select audit.err('T-PZ-35 alterar um que não existe',
  $q$select admin_save_partner_location('00000000-0000-0000-0000-000000000000', 'Posto', null, 'fuel_station', 'active', null, null, 38.7, -27.2, null)$q$, 'não encontrado');
select audit.eq('T-PZ-36 Angra: nome sem espaços, 1 jardineiro cobre (o suspenso não), 3 pedidos perto, 2 sem resposta',
  format($q$select name || '/' || workers_covering || '/' || workers_nearby || '/' || jobs_nearby || '/' || jobs_unanswered || '/' || notes
     from admin_list_partner_locations() where id = %L$q$, :'pa1'),
  'Posto Angra/1/1/3/2/Parceira desde novembro');
select audit.eq('T-PZ-37 Ponta Delgada: ninguém cobre, 1 pedido recente (ainda não sem resposta)',
  format($q$select workers_covering || '/' || jobs_nearby || '/' || jobs_unanswered from admin_list_partner_locations() where id = %L$q$, :'pa2'),
  '0/1/0');
select audit.eq('T-PZ-38 parceiras primeiro, depois em conversa, depois acabadas',
  format($q$select string_agg(status, ',' order by ord) from (select status, row_number() over () ord
     from admin_list_partner_locations() where id in (%L, %L, %L)) s$q$, :'pa1', :'pa2', :'pa3'),
  'active,prospect,ended');

-- ── Zonas ──
select audit.eq('T-PZ-40 zona de Angra: 3 pedidos, 2 sem resposta, 1 concluído, 1.ª proposta em 3 h, 1 base, 1 cobre, 1 gasolineira (a acabada não conta)',
  $q$select area || '/' || jobs || '/' || jobs_unanswered || '/' || jobs_completed || '/' || median_hours_first_proposal
     || '/' || workers_based || '/' || workers_covering || '/' || partners
     from admin_map_zones(90, 10) where 38.71 between lat_min and lat_max and -27.21 between lng_min and lng_max$q$,
  'Angra Teste/3/2/1/3/1/1/1');
select audit.eq('T-PZ-41 zona de Ponta Delgada: 1 pedido, ninguém cobre, gasolineira em conversa conta',
  $q$select jobs || '/' || jobs_unanswered || '/' || workers_covering || '/' || partners
     from admin_map_zones(90, 10) where 37.80 between lat_min and lat_max and -25.50 between lng_min and lng_max$q$,
  '1/0/0/1');
select audit.eq('T-PZ-42 quadrados nunca abaixo de 5 km',
  $q$select round(((lat_max - lat_min) * 111)::numeric, 1)::text from admin_map_zones(90, 1) limit 1$q$, '5.0');
select audit.eq('T-PZ-43 período de 1 dia: em Ponta Delgada conta o pedido de há 1 hora',
  $q$select jobs || '/' || partners from admin_map_zones(1, 10)
     where 37.80 between lat_min and lat_max and -25.50 between lng_min and lng_max$q$,
  '1/1');
select audit.eq('T-PZ-44 apagar uma gasolineira',
  format($q$select admin_delete_partner_location(%L)::text || (select count(*) from admin_list_partner_locations() where id = %L)$q$, :'pa3', :'pa3'),
  '0');
select audit.err('T-PZ-45 apagar outra vez', format($q$select admin_delete_partner_location(%L)$q$, :'pa3'), 'não encontrado');
reset role;
select audit.eq('T-PZ-46 registo das gasolineiras',
  $q$select string_agg(action, ',' order by created_at, id) from admin_actions where action like 'partner\_%'$q$,
  'partner_created,partner_created,partner_created,partner_updated,partner_deleted');
select audit.eq('T-PZ-47 auxiliar das bases não se chama pela API',
  $q$select has_function_privilege('authenticated', 'public.admin_active_worker_bases()', 'execute')::text$q$, 'false');
select audit.eq('T-PZ-48 nenhuma RPC nova recebe ids de pessoas',
  $q$select count(*)::text from pg_proc p where proname in ('admin_list_fleet_cards','admin_review_fleet_card',
     'admin_list_partner_locations','admin_save_partner_location','admin_delete_partner_location','admin_map_zones')
     and exists (select 1 from unnest(p.proargnames) a where a in ('p_worker_id','p_client_id','p_user_id','p_admin_id'))$q$, '0');

-- ── Correr a migration outra vez ──
\set QUIET on
\ir ../../migrations/0082_admin_partners_zones.sql
\set QUIET off
select audit.eq('T-PZ-60 correr outra vez não perde gasolineiras nem decisões',
  format($q$select (select count(*) from partner_locations) || ':' || (select review_message is not null from worker_fleet_cards where id = %L)$q$, :'fb'),
  '2:true');

select format('%s | %s | %s', case when ok then 'PASS' else 'FAIL' end, id, coalesce(detail, ''))
from audit.results where id like 'T-PZ-%' order by seq;
select format('TOTAL %s | PASS %s | FAIL %s', count(*), count(*) filter (where ok), count(*) filter (where not ok))
from audit.results where id like 'T-PZ-%';
