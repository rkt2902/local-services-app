-- Consumo de combustível (migration 0084), 26/11/2026: o Profissional lê e
-- grava as suas linhas; o painel junta as estatísticas para parceiros.
-- Corre depois do 10_flows.sql (bash run.sh keep), na mesma BD. Cria
-- contas próprias em Bragança e Beja, onde os outros ficheiros não põem
-- ninguém, para as contas por distrito não dependerem deles.

\set W1 '00000000-0000-0000-0000-0000000000a1'
\set C1 '00000000-0000-0000-0000-0000000000c1'
\set AD '00000000-0000-0000-0000-0000000000ad'
\set FC '00000000-0000-0000-0000-0000000000f0'
\set FA '00000000-0000-0000-0000-0000000000f1'
\set FB '00000000-0000-0000-0000-0000000000f2'
\set FD '00000000-0000-0000-0000-0000000000f3'

reset role;
select t_as('');
select id as st from service_types order by sort_order limit 1 \gset
select c.name as cat from service_types t join service_categories c on c.id = t.category_id where t.id = :'st' \gset

-- Estatísticas antes de criar as contas (o resto vem do 10_flows).
select t_aal2(:'AD');
select admin_partner_stats(6) as s0 \gset
select t_as('');

-- ── Preparação (como postgres) ──
-- FA (Pro, Bragança) e FB (Grátis, Bragança) respondem; FD (Beja) não.
insert into auth.users(id, email, email_confirmed_at) values
 (:'FC', 'fc@teste.local', now()), (:'FA', 'fa@teste.local', now()),
 (:'FB', 'fb@teste.local', now()), (:'FD', 'fd@teste.local', now());
insert into profiles(id, role, full_name, phone) values
 (:'FC', 'client', 'Cliente Combustível', '+351910000031'),
 (:'FA', 'worker', 'Profissional A', '+351910000032'),
 (:'FB', 'worker', 'Profissional B', '+351910000033'),
 (:'FD', 'worker', 'Profissional D', '+351910000034');
insert into worker_profiles(profile_id, radius_km, base_lat, base_lng, location_name) values
 (:'FA', 10, 41.80, -6.75, 'Bragança Teste'),
 (:'FB', 10, 41.70, -6.90, 'Bragança Teste'),
 (:'FD', 10, 38.01, -7.86, 'Beja Teste');
insert into worker_plans(worker_id, tier) values (:'FA', 'pro');

-- FB fez uma proposta há 2 dias (ativo); FA concluiu um trabalho este mês.
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode)
values (:'FC', :'st', 'Rua F 1', 'Bragança Teste', 41.80, -6.75, 'aberto', 'open', 'flexible') returning id as j1 \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status, created_at)
values (:'j1', :'FB', 15, 'pending', now() - interval '2 days');
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode)
values (:'FC', :'st', 'Rua F 2', 'Bragança Teste', 41.80, -6.75, 'concluído', 'open', 'flexible') returning id as j2 \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status)
values (:'j2', :'FA', 15, 'accepted') returning id as p2 \gset
update job_requests set status = 'completed', accepted_proposal_id = :'p2', marked_done_at = now() where id = :'j2';

select count(*) as acts0 from admin_actions \gset

-- ── Acesso ──
set role anon;
select t_as('');
select audit.err('T-FU-01 sem sessão não lê', $q$select * from get_my_fuel_usage()$q$, 'permission denied');
select audit.err('T-FU-02 sem sessão não grava', $q$select set_my_fuel_usage('[]')$q$, 'permission denied');
select audit.err('T-FU-03 sem sessão não vê as estatísticas', $q$select admin_partner_stats()$q$, 'permission denied');
reset role;
set role authenticated;
select t_as(:'FC');
select audit.err('T-FU-04 cliente não grava consumo',
  $q$select set_my_fuel_usage('[{"fuel_type_id": "diesel", "liters_per_month": 10}]')$q$, 'not_a_worker');
select audit.err('T-FU-05 a tabela do consumo é só do servidor', $q$select count(*) from worker_fuel_usage$q$, 'permission denied');
select audit.eq('T-FU-06 os tipos ativos leem-se, por ordem',
  $q$select string_agg(id, ',' order by sort_order) from fuel_types$q$, 'diesel,petrol,oil_2t,chain_oil');
select audit.err('T-FU-07 utilizador normal não vê as estatísticas', $q$select admin_partner_stats()$q$, 'Sem acesso');
select t_as(:'AD');
select audit.err('T-FU-08 admin sem segundo fator não vê as estatísticas', $q$select admin_partner_stats()$q$, 'Sem acesso');

-- ── Gravar e ler ──
select t_as(:'FA');
select audit.eq('T-FU-10 sem respostas, a lista vem vazia', $q$select count(*)::text from get_my_fuel_usage()$q$, '0');
select audit.ok('T-FU-11 grava dois combustíveis',
  $q$select set_my_fuel_usage('[{"fuel_type_id": "petrol", "liters_per_month": 80}, {"fuel_type_id": "oil_2t", "liters_per_month": 4.25}]')$q$);
select audit.eq('T-FU-12 lê pela ordem dos tipos, com uma casa decimal',
  $q$select string_agg(fuel_type_id || '=' || liters_per_month, ',') from get_my_fuel_usage()$q$, 'petrol=80.0,oil_2t=4.3');
select audit.err('T-FU-13 tipo repetido falha e nada muda',
  $q$select set_my_fuel_usage('[{"fuel_type_id": "diesel", "liters_per_month": 10}, {"fuel_type_id": "diesel", "liters_per_month": 20}]')$q$, 'duplicate');
select audit.err('T-FU-14 tipo que não existe', $q$select set_my_fuel_usage('[{"fuel_type_id": "kerosene", "liters_per_month": 10}]')$q$, 'foreign key');
select audit.err('T-FU-15 zero litros', $q$select set_my_fuel_usage('[{"fuel_type_id": "diesel", "liters_per_month": 0}]')$q$, 'check');
select audit.err('T-FU-16 litros a mais', $q$select set_my_fuel_usage('[{"fuel_type_id": "diesel", "liters_per_month": 20000}]')$q$, 'check');
select audit.err('T-FU-17 não é uma lista', $q$select set_my_fuel_usage('{"fuel_type_id": "diesel"}')$q$, 'invalid_items');
select audit.eq('T-FU-18 depois das recusas fica o que estava',
  $q$select string_agg(fuel_type_id || '=' || liters_per_month, ',') from get_my_fuel_usage()$q$, 'petrol=80.0,oil_2t=4.3');
select t_as(:'FB');
select audit.ok('T-FU-19 outro Profissional grava o seu',
  $q$select set_my_fuel_usage('[{"fuel_type_id": "diesel", "liters_per_month": 120}, {"fuel_type_id": "oil_2t", "liters_per_month": 2}]')$q$);
select audit.eq('T-FU-20 cada um só vê o seu', $q$select string_agg(fuel_type_id, ',') from get_my_fuel_usage()$q$, 'diesel,oil_2t');
select t_as(:'FD');
select audit.ok('T-FU-21 grava e depois limpa com lista vazia',
  $q$select set_my_fuel_usage('[{"fuel_type_id": "diesel", "liters_per_month": 50}]'), set_my_fuel_usage('[]')$q$);
select audit.eq('T-FU-22 limpo fica sem linhas', $q$select count(*)::text from get_my_fuel_usage()$q$, '0');

-- Um tipo desativado deixa de se poder escolher.
reset role;
update fuel_types set active = false where id = 'chain_oil';
set role authenticated;
select t_as(:'FD');
select audit.err('T-FU-23 tipo desativado recusado',
  $q$select set_my_fuel_usage('[{"fuel_type_id": "chain_oil", "liters_per_month": 3}]')$q$, 'inactive_fuel_type');
select audit.eq('T-FU-24 tipo desativado não aparece na lista', $q$select count(*)::text from fuel_types where id = 'chain_oil'$q$, '0');
reset role;
update fuel_types set active = true where id = 'chain_oil';
set role authenticated;

-- ── Estatísticas ──
select t_aal2(:'AD');
select admin_partner_stats(6) as s1 \gset
reset role;
create temp table fu_s(s0 jsonb, s1 jsonb);
insert into fu_s values (:'s0', :'s1');
select audit.eq('T-FU-30 três Profissionais registados a mais',
  $q$select ((s1->'workers'->>'registered')::int - (s0->'workers'->>'registered')::int)::text from fu_s$q$, '3');
select audit.eq('T-FU-31 dois ativos a mais (proposta e trabalho concluído)',
  $q$select ((s1->'workers'->>'active_30d')::int - (s0->'workers'->>'active_30d')::int)::text from fu_s$q$, '2');
select audit.eq('T-FU-32 um Pro a mais',
  $q$select ((s1->'workers'->>'pro')::int - (s0->'workers'->>'pro')::int)::text from fu_s$q$, '1');
select audit.eq('T-FU-33 duas respostas a mais (quem limpou não conta)',
  $q$select ((s1->'survey'->>'answered')::int - (s0->'survey'->>'answered')::int)::text from fu_s$q$, '2');
select audit.eq('T-FU-34 litros por tipo somados',
  $q$select string_agg(f1->>'id' || '=' || ((f1->>'liters')::numeric - (f0->>'liters')::numeric)
                       || '/' || ((f1->>'workers')::int - (f0->>'workers')::int), ',')
     from fu_s, jsonb_array_elements(s1->'fuel') f1
     join jsonb_array_elements((select s0->'fuel' from fu_s)) f0 on f0->>'id' = f1->>'id'$q$,
  'diesel=120.0/1,petrol=80.0/1,oil_2t=6.3/2,chain_oil=0/0');
select audit.eq('T-FU-35 Bragança: 2 registados, 2 ativos, 2 respostas, litros por tipo',
  $q$select d->>'registered' || ':' || (d->>'active_30d') || ':' || (d->>'answered') || ':' || (d->'liters'->>'diesel') || ':' || (d->'liters'->>'petrol') || ':' || (d->'liters'->>'oil_2t')
     from fu_s, jsonb_array_elements(s1->'districts') d where d->>'district' = 'Bragança'$q$,
  '2:2:2:120.0:80.0:6.3');
select audit.eq('T-FU-36 Beja: 1 registado, sem resposta',
  $q$select d->>'registered' || ':' || (d->>'answered') || ':' || (d->'liters')::text
     from fu_s, jsonb_array_elements(s1->'districts') d where d->>'district' = 'Beja'$q$,
  '1:0:{}');
select audit.eq('T-FU-37 trabalho concluído conta no mês e na categoria',
  format($q$select ((select coalesce(sum((c->>'count')::int), 0) from fu_s, jsonb_array_elements(s1->'completed') c
                      where c->>'month' = to_char(now(), 'YYYY-MM') and c->>'category' = %L)
                  - (select coalesce(sum((c->>'count')::int), 0) from fu_s, jsonb_array_elements(s0->'completed') c
                      where c->>'month' = to_char(now(), 'YYYY-MM') and c->>'category' = %L))::text$q$, :'cat', :'cat'),
  '1');
select audit.eq('T-FU-38 distrito aproximado',
  $q$select approx_district(41.15, -8.61) || ',' || approx_district(38.72, -9.14) || ',' || approx_district(37.02, -7.93)
            || ',' || approx_district(38.70, -27.20) || ',' || approx_district(32.65, -16.91) || ',' || coalesce(approx_district(0, 0), 'nulo')$q$,
  'Porto,Lisboa,Faro,Açores,Madeira,nulo');
select audit.eq('T-FU-39 ver as estatísticas fica no registo',
  format($q$select (count(*) - %s)::text from admin_actions$q$, :'acts0'), '1');

-- Conta suspensa sai das contas.
insert into account_status(profile_id, suspended_at, suspended_reason) values (:'FB', now(), 'other');
set role authenticated;
select t_aal2(:'AD');
select admin_partner_stats(6) as s2 \gset
reset role;
update fu_s set s0 = :'s2';
select audit.eq('T-FU-40 suspenso não conta em Bragança nem nos litros',
  $q$select d->>'registered' || ':' || coalesce(d->'liters'->>'diesel', '-')
     from fu_s, jsonb_array_elements(s0->'districts') d where d->>'district' = 'Bragança'$q$, '1:-');

-- Correr a migration outra vez não perde respostas nem tipos.
\set QUIET on
\ir ../../migrations/0084_worker_fuel_usage.sql
\set QUIET off
select audit.eq('T-FU-41 correr outra vez mantém tudo',
  $q$select (select count(*) from fuel_types) || ':' || (select count(*) from worker_fuel_usage where worker_id in ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f2'))$q$,
  '4:4');

select format('%s | %s | %s', case when ok then 'PASS' else 'FAIL' end, id, coalesce(detail, ''))
from audit.results where id like 'T-FU-%' order by seq;
select format('TOTAL %s | PASS %s | FAIL %s', count(*), count(*) filter (where ok), count(*) filter (where not ok))
from audit.results where id like 'T-FU-%';
