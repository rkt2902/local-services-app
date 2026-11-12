-- Auditoria 2026-11-12: reprodução dos achados (BUG-xxx em 04-BUG-REPORT.md).
-- Corre depois de 10_flows.sql na BD pj_audit (bash run.sh keep). Só local.
\set C2 '00000000-0000-0000-0000-0000000000c2'
\set W1 '00000000-0000-0000-0000-0000000000a1'
select id as st from service_types order by sort_order limit 1 \gset
truncate audit.results;
update job_requests set created_at = created_at - interval '2 hours' where client_id = :'C2'; -- preparação

-- BUG-002: a app consegue criar um pedido já "iniciado" (started_at no INSERT)
set role authenticated;
select t_as(:'C2');
select audit.val('F-002a cliente cria pedido com started_at e before_photo_paths preenchidos',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,started_at,before_photo_paths,marked_done_at)
     values(%L,%L,'Rua F',38.72,-9.14,'pedido manipulado','open','flexible',now(),array['qualquer/caminho.jpg'],now()) returning id$q$, :'C2', :'st')) as jf \gset
select t_as(:'W1');
select audit.val('F-002b jardineiro propõe',
  format($q$select create_proposal(%L, 15, 1, 2, 1, null, null, null, true)$q$, :'jf')) as pf \gset
select t_as(:'C2');
select audit.ok('F-002c cliente aceita', format($q$select accept_proposal(%L,%L)$q$, :'pf', :'jf'));
select t_as(:'W1');
select audit.err('F-002d [efeito] o jardineiro já não consegue cancelar ("já começou")',
  format($q$select cancel_job(%L, 'other')$q$, :'jf'));
select audit.err('F-002e [efeito] o jardineiro não consegue Iniciar ("já foi iniciado")',
  format($q$select start_job(%L, '{}')$q$, :'jf'));
reset role;
select audit.eq('F-002f [efeito] o trabalho aparece como em curso sem o jardineiro ter iniciado',
  format($q$select (started_at is not null)::text from job_requests where id=%L$q$, :'jf'), 'true');

-- BUG-003: pedido com data fixa no passado é aceite pelo servidor
set role authenticated;
select t_as(:'C2');
select audit.val('F-003a pedido com data fixa de há 10 dias é criado',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,preferred_date)
     values(%L,%L,'Rua G',38.72,-9.14,'data no passado','open','fixed',today_pt()-10) returning id$q$, :'C2', :'st')) as jp \gset
select t_as(:'W1');
select audit.eq('F-003b não aparece a nenhum jardineiro',
  format($q$select count(*)::text from get_jobs_in_radius(38.72,-9.14,30) where id=%L$q$, :'jp'), '0');
reset role;
select t_as('');
select auto_expire_jobs();
select audit.eq('F-003c a corrida seguinte do cron fecha-o como sem resposta',
  format($q$select status from job_requests where id=%L$q$, :'jp'), 'no_response');

-- BUG-007: horas mínimas maiores do que as máximas
set role authenticated;
select t_as(:'C2');
select audit.val('F-007a preparação: pedido',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'Rua H',38.72,-9.14,'horas trocadas','open','flexible') returning id$q$, :'C2', :'st')) as jh \gset
select t_as(:'W1');
select audit.val('F-007b proposta com 6h a 2h é gravada',
  format($q$select create_proposal(%L, 15, 6, 2, 1, null, null, null, true)$q$, :'jh')) as ph \gset
select audit.err('F-007c (controlo) pessoas = 0 é recusado',
  format($q$select create_proposal(%L, 15, 1, 2, 0, null, null, null, true)$q$, :'jh'), 'pessoas');


-- BUG-006: raio do jardineiro sem limite pela API (a app só deixa 1 a 50 km)
set role authenticated;
select t_as(:'W1');
select audit.ok('F-006a jardineiro grava raio de 5000 km por UPDATE direto',
  format($q$update worker_profiles set radius_km=5000 where profile_id=%L$q$, :'W1'));
reset role;
update job_requests set created_at = created_at - interval '3 hours'; -- preparação: limite por hora
set role authenticated;
select t_as(:'C2');
select audit.ok('F-006b cliente cria pedido em Faro',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'Faro',37.02,-7.93,'pedido em Faro','open','flexible')$q$, :'C2', :'st'));
reset role;
select audit.eq('F-006c [efeito] o jardineiro de Lisboa recebe o aviso do pedido em Faro',
  format($q$select count(*)::text from notifications n join job_requests j on j.id=n.related_id where n.user_id=%L and n.type='new_job_in_radius' and j.description='pedido em Faro'$q$, :'W1'), '1');
update worker_profiles set radius_km=30 where profile_id=:'W1'; -- repor

-- BUG-008: textos sem limite de tamanho escritos diretamente pela API
set role authenticated;
select t_as(:'C2');
select audit.eq('F-008a nome do perfil com 100 000 caracteres é aceite',
  format($q$with u as (update profiles set full_name=repeat('x',100000) where id=%L returning length(full_name)) select max(length)::text from u$q$, :'C2'), '100000');
select audit.ok('F-008b repor o nome', format($q$update profiles set full_name='Cliente Dois' where id=%L$q$, :'C2'));
reset role;

\echo ===== ACHADOS =====
select case when ok then 'PASS' else 'FAIL' end || ' | ' || id || coalesce(' | ' || detail, '') from audit.results order by seq;
