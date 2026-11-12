-- Auditoria 2026-11-12: regressão dos bugs corrigidos na 0074 (BUG-xxx em
-- 04-BUG-REPORT.md). Antes da 0074 estas asserções falhavam; depois passam.
-- Corre depois de 10_flows.sql na BD pj_audit (bash run.sh keep). Só local.
\set C2 '00000000-0000-0000-0000-0000000000c2'
\set W1 '00000000-0000-0000-0000-0000000000a1'
select id as st from service_types order by sort_order limit 1 \gset
truncate audit.results;
update job_requests set created_at = created_at - interval '2 hours' where client_id = :'C2'; -- preparação

-- BUG-002: campos de execução enviados pela app no INSERT são ignorados
set role authenticated;
select t_as(:'C2');
select audit.val('F-002a cliente envia started_at, marked_done_at e fotos no INSERT',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,started_at,before_photo_paths,marked_done_at)
     values(%L,%L,'Rua F',38.72,-9.14,'pedido manipulado','open','flexible',now(),array['qualquer/caminho.jpg'],now()) returning id$q$, :'C2', :'st')) as jf \gset
reset role;
select audit.eq('F-002b o pedido nasce sem started_at, marked_done_at nem fotos',
  format($q$select (started_at is null and marked_done_at is null and before_photo_paths = '{}')::text from job_requests where id=%L$q$, :'jf'), 'true');
set role authenticated;
select t_as(:'W1');
select audit.val('F-002c jardineiro propõe',
  format($q$select create_proposal(%L, 15, 1, 2, 1, null, null, null, true)$q$, :'jf')) as pf \gset
select t_as(:'C2');
select audit.ok('F-002d cliente aceita', format($q$select accept_proposal(%L,%L)$q$, :'pf', :'jf'));
select t_as(:'W1');
select audit.ok('F-002e o jardineiro pode cancelar (não começou)',
  format($q$select cancel_job(%L, 'other')$q$, :'jf'));

-- BUG-003: data fixa no passado recusada no INSERT
select t_as(:'C2');
select audit.err('F-003a pedido com data fixa de há 10 dias é recusado',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,preferred_date)
     values(%L,%L,'Rua G',38.72,-9.14,'data no passado','open','fixed',today_pt()-10)$q$, :'C2', :'st'), 'já passou');
select audit.val('F-003b data fixa de hoje continua aceite',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode,preferred_date)
     values(%L,%L,'Rua G',38.72,-9.14,'data de hoje','open','fixed',today_pt()) returning id$q$, :'C2', :'st')) as jt \gset

-- BUG-004: a pesquisa usa a base gravada, não as coordenadas enviadas
select t_as(:'W1');
select audit.eq('F-004a jardineiro de Lisboa continua a ver o pedido de Lisboa mesmo mandando coordenadas do Porto',
  format($q$select count(*)::text from get_jobs_in_radius(41.15,-8.61,10) where id=%L$q$, :'jt'), '1');
select t_as(:'C2');
select audit.eq('F-004b conta de cliente não lista pedidos',
  $q$select count(*)::text from get_jobs_in_radius(38.72,-9.14,50)$q$, '0');

-- BUG-007: mínimo maior do que o máximo
reset role;
update job_requests set created_at = created_at - interval '2 hours' where client_id = :'C2'; -- preparação
set role authenticated;
select t_as(:'C2');
select audit.val('F-007a preparação: pedido',
  format($q$insert into job_requests(client_id,service_type_id,address_text,location_lat,location_lng,description,status,date_mode)
     values(%L,%L,'Rua H',38.72,-9.14,'horas trocadas','open','flexible') returning id$q$, :'C2', :'st')) as jh \gset
select t_as(:'W1');
select audit.err('F-007b proposta com 6h a 2h é recusada',
  format($q$select create_proposal(%L, 15, 6, 2, 1, null, null, null, true)$q$, :'jh'), 'mínima');
select audit.err('F-007c proposta com 5 a 2 dias é recusada',
  format($q$select create_proposal(p_job_id=>%L, p_hourly_rate=>15, p_estimated_days_min=>5, p_estimated_days_max=>2, p_scheduled_flexible=>true)$q$, :'jh'), 'dias');
select audit.err('F-007d (controlo) pessoas = 0 é recusado',
  format($q$select create_proposal(%L, 15, 1, 2, 0, null, null, null, true)$q$, :'jh'), 'pessoas');
select audit.ok('F-007e proposta normal continua a passar',
  format($q$select create_proposal(%L, 15, 2, 4, 1, null, null, null, true)$q$, :'jh'));

-- BUG-006: raio entre 1 e 50 km
select audit.err('F-006a raio de 5000 km é recusado',
  format($q$update worker_profiles set radius_km=5000 where profile_id=%L$q$, :'W1'), 'radius_km_range');
select audit.ok('F-006b raio de 50 km continua aceite',
  format($q$update worker_profiles set radius_km=50 where profile_id=%L$q$, :'W1'));
reset role;
update worker_profiles set radius_km=30 where profile_id=:'W1'; -- repor

-- BUG-008: limites de tamanho
set role authenticated;
select t_as(:'C2');
select audit.err('F-008a nome com 100 000 caracteres é recusado',
  format($q$update profiles set full_name=repeat('x',100000) where id=%L$q$, :'C2'), 'full_name_length');
select audit.ok('F-008b nome normal continua aceite',
  format($q$update profiles set full_name='Cliente Dois' where id=%L$q$, :'C2'));
select t_as(:'W1');
select audit.err('F-008c bio com 5000 caracteres é recusada',
  format($q$update worker_profiles set bio=repeat('b',5000) where profile_id=%L$q$, :'W1'), 'bio_length');
reset role;

\echo ===== REGRESSÃO DOS BUGS CORRIGIDOS =====
select case when ok then 'PASS' else 'FAIL' end || ' | ' || id || coalesce(' | ' || detail, '') from audit.results order by seq;
