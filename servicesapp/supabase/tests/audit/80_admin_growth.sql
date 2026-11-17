-- Painel de admin, fase 3 (migration 0081), 16/11/2026: funil, exportar
-- CSV e avisos a grupos. Corre depois do 10_flows.sql (bash run.sh keep),
-- na mesma BD; os outros ficheiros podem correr antes ou não. Cria contas
-- próprias (C7, W7, W8, W9) numa localidade inventada, "Braguinha", para
-- os números dos avisos não dependerem dos outros ficheiros. O funil
-- verifica diferenças (antes e depois de criar as contas).

\set W1 '00000000-0000-0000-0000-0000000000a1'
\set AD '00000000-0000-0000-0000-0000000000ad'
\set C7 '00000000-0000-0000-0000-0000000000c7'
\set W7 '00000000-0000-0000-0000-0000000000a7'
\set W8 '00000000-0000-0000-0000-0000000000a8'
\set W9 '00000000-0000-0000-0000-0000000000a9'

reset role;
select t_as('');
select id as st from service_types order by sort_order limit 1 \gset

-- Funil antes das contas novas.
set role authenticated;
select t_aal2(:'AD');
select admin_funnel(30) as f0 \gset
reset role;

-- ── Preparação (como postgres) ──
insert into auth.users(id, email, email_confirmed_at) values
 (:'C7', 'c7@teste.local', now()), (:'W7', 'w7@teste.local', now()),
 (:'W8', 'w8@teste.local', now()), (:'W9', 'w9@teste.local', now());
insert into profiles(id, role, full_name, phone) values
 (:'C7', 'client', 'Cliente Sete', '+351910000007'),
 (:'W7', 'worker', 'Jardineiro Sete', '+351910000017'),
 (:'W8', 'worker', 'Jardineiro Oito', '+351910000018'),
 (:'W9', 'worker', 'Jardineiro Nove', '+351910000019');
insert into worker_profiles(profile_id, radius_km, base_lat, base_lng, location_name) values
 (:'W7', 20, 41.55, -8.42, 'Braguinha'),
 (:'W8', 20, 41.55, -8.42, 'Braguinha de Cima'),
 (:'W9', 20, 41.55, -8.42, 'Braguinha');
insert into worker_service_types(worker_id, service_type_id) values (:'W7', :'st'), (:'W9', :'st');
insert into worker_plans(worker_id, tier) values (:'W7', 'pro');
-- W9 suspenso: fica fora de tudo.
insert into account_status(profile_id, suspended_at, suspended_reason) values (:'W9', now(), 'other');

-- C7: um pedido com proposta do W7, aceite e concluído, avaliado.
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode)
values (:'C7', :'st', 'Rua Secreta 7', 'Braguinha', 41.55, -8.42, 'fase 3 concluído', 'open', 'flexible') returning id as j7 \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status, created_at)
values (:'j7', :'W7', 15, 'accepted', now() + interval '2 hours') returning id as p7 \gset
update job_requests set status = 'completed', accepted_proposal_id = :'p7' where id = :'j7';
insert into ratings(job_id, rater_id, ratee_id, stars) values (:'j7', :'C7', :'W7', 5);

select count(*) as acts0 from admin_actions \gset

-- ── Recusas: sem sessão, utilizador normal, admin sem aal2 ──
create temp table g_calls(name text, sql text);
insert into g_calls values
  ('admin_funnel',          $q$select admin_funnel(30)$q$),
  ('admin_export_rows',     $q$select admin_export_rows('jobs', 30)$q$),
  ('admin_notice_audience', $q$select admin_notice_audience('worker')$q$),
  ('admin_send_notice',     $q$select admin_send_notice('Olá a todos', 'Texto do aviso de teste.', 'worker', null, null, 'Braguinha', 2)$q$),
  ('admin_list_notices',    $q$select * from admin_list_notices()$q$);
grant select on g_calls to anon, authenticated;

set role anon;
select t_as('');
select audit.err('T-GRO-01 sem sessão: ' || name, sql, 'permission denied') from g_calls;
reset role;
set role authenticated;
select t_as(:'W1');
select audit.err('T-GRO-02 utilizador normal: ' || name, sql, 'Sem acesso') from g_calls;
select t_as(:'AD');
select audit.err('T-GRO-03 admin sem segundo fator: ' || name, sql, 'Sem acesso') from g_calls;
reset role;
select audit.eq('T-GRO-04 recusas não enviam nem registam nada',
  $q$select (select count(*) from admin_actions) || ':' || (select count(*) from notifications where type = 'admin_notice')$q$,
  :'acts0' || ':0');

set role authenticated;
select t_aal2(:'AD');
select audit.err('T-GRO-05 admin_counts_person não se chama pela API',
  format($q$select admin_counts_person(%L)$q$, :'W7'), 'permission denied');
select audit.err('T-GRO-06 admin_notice_recipients não se chama pela API',
  $q$select * from admin_notice_recipients('worker', null, null, null)$q$, 'permission denied');
select audit.err('T-GRO-07 tabela dos avisos é só do servidor',
  $q$select count(*) from admin_notices$q$, 'permission denied');

-- ── Funil ──
select admin_funnel(30) as f1 \gset
select audit.eq('T-GRO-10 clientes: +1 registo que pediu, recebeu proposta, contratou, concluiu e avaliou',
  format($q$select string_agg(((%L::jsonb->'clients'->>k)::int - (%L::jsonb->'clients'->>k)::int)::text, ',' order by o)
     from unnest(array['signed_up','posted','got_proposal','hired','completed','rated']) with ordinality u(k, o)$q$, :'f1', :'f0'),
  '1,1,1,1,1,1');
select audit.eq('T-GRO-11 pedidos: +1 criado, com proposta, aceite, concluído e avaliado',
  format($q$select string_agg(((%L::jsonb->'jobs'->>k)::int - (%L::jsonb->'jobs'->>k)::int)::text, ',' order by o)
     from unnest(array['created','with_proposal','accepted','completed','rated']) with ordinality u(k, o)$q$, :'f1', :'f0'),
  '1,1,1,1,1');
select audit.eq('T-GRO-12 jardineiros: +2 (o suspenso não conta), 2 com perfil, 1 propôs, 1 contratado, 1 concluiu, 1 Pro',
  format($q$select string_agg(((%L::jsonb->'workers'->>k)::int - (%L::jsonb->'workers'->>k)::int)::text, ',' order by o)
     from unnest(array['signed_up','profile_ready','proposed','hired','completed','paid_plan']) with ordinality u(k, o)$q$, :'f1', :'f0'),
  '2,2,1,1,1,1');
select audit.ok('T-GRO-13 tempo mediano até à primeira proposta é um número',
  format($q$select (%L::jsonb->'jobs'->>'median_hours_to_first_proposal')::numeric$q$, :'f1'));
select audit.ok('T-GRO-14 desde sempre (0) também responde', $q$select admin_funnel(0)$q$);

-- ── Exportar ──
select audit.eq('T-GRO-20 pedidos: 10 colunas, o da C7 com serviço, localidade e jardineiro',
  format($q$select jsonb_array_length(d->'columns') || ':' ||
     (select r->>4 || '/' || (r->>7) from jsonb_array_elements(d->'rows') r where r->>0 = %L)
     from admin_export_rows('jobs', 30) d$q$, :'j7'),
  '10:Braguinha/Jardineiro Sete');
select audit.eq('T-GRO-21 sem telefones, emails nem morada exata',
  $q$select ((select admin_export_rows('jobs', 30)::text) || (select admin_export_rows('clients', 30)::text)
     || (select admin_export_rows('workers', 30)::text)) ~ '(\+3519|@teste\.local|Rua Secreta)'$q$::text, 'false');
select audit.eq('T-GRO-22 jardineiros: plano, concluídos, média e estado',
  format($q$select (select r->>5 || '/' || (r->>9) || '/' || (r->>10) || '/' || (r->>12)
     from jsonb_array_elements(d->'rows') r where r->>0 = %L)
     || '|' || (select r->>12 from jsonb_array_elements(d->'rows') r where r->>0 = %L)
     from admin_export_rows('workers', 30) d$q$, :'W7', :'W9'),
  'pro/1/5.00/ativa|suspensa');
select audit.eq('T-GRO-23 clientes: pedidos e concluídos',
  format($q$select (select r->>3 || '/' || (r->>4) from jsonb_array_elements(d->'rows') r where r->>0 = %L)
     from admin_export_rows('clients', 30) d$q$, :'C7'), '1/1');
select audit.err('T-GRO-24 tipo inválido', $q$select admin_export_rows('pagamentos', 30)$q$, 'inválido');

-- ── Avisos ──
select audit.eq('T-GRO-30 jardineiros de Braguinha: 2 (o suspenso não conta)',
  $q$select admin_notice_audience('worker', null, null, 'braguinha')::text$q$, '2');
select audit.eq('T-GRO-31 só Pro', $q$select admin_notice_audience('worker', array['pro'], null, 'Braguinha')::text$q$, '1');
select audit.eq('T-GRO-32 só quem faz o serviço',
  format($q$select admin_notice_audience('worker', null, %L, 'Braguinha')::text$q$, :'st'), '1');
select audit.eq('T-GRO-33 clientes com pedidos em Braguinha',
  $q$select admin_notice_audience('client', null, null, 'Braguinha')::text$q$, '1');
select audit.err('T-GRO-34 papel inválido', $q$select admin_notice_audience('admin')$q$, 'profissionais ou clientes');
select audit.err('T-GRO-35 plano inválido', $q$select admin_notice_audience('worker', array['ouro'])$q$, 'Plano inválido');
select audit.err('T-GRO-36 título curto',
  $q$select admin_send_notice('Oi', 'Texto do aviso de teste.', 'worker', null, null, 'Braguinha', 2)$q$, 'título');
select audit.err('T-GRO-37 texto curto',
  $q$select admin_send_notice('Novidades', 'curto', 'worker', null, null, 'Braguinha', 2)$q$, 'texto');
select audit.err('T-GRO-38 contagem diferente da que o admin viu',
  $q$select admin_send_notice('Novidades', 'Texto do aviso de teste.', 'worker', null, null, 'Braguinha', 5)$q$, 'mudou (agora 2)');
select audit.err('T-GRO-39 ninguém nos filtros',
  $q$select admin_send_notice('Novidades', 'Texto do aviso de teste.', 'worker', null, null, 'Lugar Nenhum', 0)$q$, 'Ninguém');
select audit.eq('T-GRO-40 enviar aos 2',
  $q$select admin_send_notice('  Novidades  ', 'Texto do aviso de teste.', 'worker', null, null, 'Braguinha', 2)::text$q$, '2');
select audit.err('T-GRO-41 o mesmo aviso não sai duas vezes em 24 h',
  $q$select admin_send_notice('Novidades', 'Texto do aviso de teste.', 'worker', array['pro'], null, 'Braguinha', 1)$q$, '24 horas');
reset role;
select audit.eq('T-GRO-42 cada um recebe um aviso admin_notice ligado ao envio',
  format($q$select string_agg(n.user_id::text, ',' order by n.user_id) || ':' || bool_and(n.related_id = a.id and n.title = 'Novidades')
     from notifications n, admin_notices a where n.type = 'admin_notice'$q$),
  :'W7' || ',' || :'W8' || ':true');
select audit.eq('T-GRO-43 o suspenso não recebe',
  format($q$select count(*)::text from notifications where type = 'admin_notice' and user_id = %L$q$, :'W9'), '0');
update notifications set read = true where type = 'admin_notice' and user_id = :'W7';
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-GRO-44 histórico com destinatários, lidos e filtros',
  $q$select recipients || ':' || read_count || ':' || (audience->>'area') || ':' || admin_email from admin_list_notices()$q$,
  '2:1:Braguinha:ad@teste.local');
reset role;

-- ── Registo ──
select audit.eq('T-GRO-50 funil, exportação e envio ficam no registo',
  $q$select string_agg(distinct action, ',' order by action) from admin_actions
     where action in ('view_funnel', 'export_csv', 'send_notice')$q$,
  'export_csv,send_notice,view_funnel');
select audit.eq('T-GRO-51 exportação regista o tipo e o número de linhas',
  $q$select count(*)::text from admin_actions where action = 'export_csv' and details ? 'kind' and details ? 'rows'$q$, '6');
select audit.eq('T-GRO-52 nenhuma RPC recebe o id de quem chama',
  $q$select count(*)::text from pg_proc p where proname like 'admin\_%' and exists (
     select 1 from unnest(p.proargnames) a where a in ('p_admin_id','p_user_id','p_actor_id','p_created_by'))$q$, '0');

-- ── Correr a migration outra vez ──
\set QUIET on
\ir ../../migrations/0081_admin_growth.sql
-- A 0081 outra vez tira a versão da 0082 do admin_send_notice: volta-se a
-- correr a 0082, pela ordem certa.
\ir ../../migrations/0082_admin_partners_zones.sql
-- A 0083 (textos formais) vem depois desta na ordem real.
\ir ../../migrations/0083_formal_texts.sql
\set QUIET off
select audit.eq('T-GRO-60 correr outra vez não perde o histórico',
  $q$select count(*)::text from admin_notices$q$, '1');

select format('%s | %s | %s', case when ok then 'PASS' else 'FAIL' end, id, coalesce(detail, ''))
from audit.results where id like 'T-GRO-%' order by seq;
select format('TOTAL %s | PASS %s | FAIL %s', count(*), count(*) filter (where ok), count(*) filter (where not ok))
from audit.results where id like 'T-GRO-%';
