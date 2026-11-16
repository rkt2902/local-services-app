-- Painel de admin para suporte, fase C (migration 0080), 16/11/2026.
-- Corre depois do 10_flows.sql (bash run.sh keep), na mesma BD; o 50 e o
-- 60 podem correr antes ou não. Cria contas próprias (C5, C6, W5, W6)
-- para não mexer nas dos outros ficheiros. Só para a BD local de teste.
--
-- Cada RPC nova tem 3 recusas (sem sessão, utilizador normal, admin sem
-- segundo fator), cada ação fica em admin_actions e avisa a pessoa, e uma
-- conta suspensa não age mas ainda se pode eliminar.

\set C2 '00000000-0000-0000-0000-0000000000c2'
\set W1 '00000000-0000-0000-0000-0000000000a1'
\set C5 '00000000-0000-0000-0000-0000000000c5'
\set C6 '00000000-0000-0000-0000-0000000000c6'
\set W5 '00000000-0000-0000-0000-0000000000a5'
\set W6 '00000000-0000-0000-0000-0000000000a6'
\set AD '00000000-0000-0000-0000-0000000000ad'

reset role;
select t_as('');
-- O 60 corre a 0079 outra vez no fim, o que repõe a versão antiga de
-- notify_proposal_closed_with_job; aqui a ordem real é 0079 e depois 0080.
\set QUIET on
\ir ../../migrations/0080_admin_accounts.sql
\set QUIET off
select id as st from service_types order by sort_order limit 1 \gset

-- ── Preparação (como postgres) ──
insert into auth.users(id, email, email_confirmed_at) values
 (:'C5', 'c5@teste.local', now()), (:'C6', 'c6@teste.local', now()),
 (:'W5', 'w5@teste.local', now()), (:'W6', 'w6@teste.local', null);
insert into profiles(id, role, full_name, phone, avatar_url) values
 (:'C5', 'client', 'Cliente Cinco', '+351910000005', 'https://x/avatars/c5.jpg'),
 (:'C6', 'client', 'Cliente Seis',  '+351910000006', null),
 (:'W5', 'worker', 'Jardineiro Cinco', '+351910000015', null),
 (:'W6', 'worker', 'Jardineiro Seis',  '+351910000016', null);
insert into worker_profiles(profile_id, radius_km, base_lat, base_lng, photos) values
 (:'W5', 25, 38.72, -9.14, array['https://x/p/w5-1.jpg', 'https://x/p/w5-2.jpg']),
 (:'W6', 15, 41.15, -8.61, '{}');
insert into worker_service_types select p, id
  from (values (:'W5'::uuid), (:'W6'::uuid)) v(p), service_types;
insert into worker_calendar_entries(worker_id, kind, title, starts_on)
values (:'W5', 'job', 'Sr. Silva, relva', current_date + 2);

-- jopen: pedido aberto da C5 com propostas de W5 e W6.
insert into job_requests(client_id, service_type_id, address_text, location_area, location_lat, location_lng, description, status, date_mode)
values (:'C5', :'st', 'Rua C 5', 'Lisboa', 38.72, -9.14, 'fase C aberto', 'open', 'flexible') returning id as jopen \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status) values
 (:'jopen', :'W5', 15, 'pending'), (:'jopen', :'W6', 16, 'pending');
update job_requests set proposal_count = 2 where id = :'jopen';
insert into job_photos(job_id, storage_path) values (:'jopen', :'C5' || '/x/relva.jpg');

-- jw: pedido aberto da C2 com proposta pendente do W5.
insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
values (:'C2', :'st', 'Rua C 6', 38.72, -9.14, 'fase C proposta', 'open', 'flexible') returning id as jw \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status) values (:'jw', :'W5', 15, 'pending');
update job_requests set proposal_count = 1 where id = :'jw';

-- jdir: pedido direto da C2 à espera do W5.
insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode,
                         direct_worker_id, direct_status, direct_until)
values (:'C2', :'st', 'Rua C 7', 38.72, -9.14, 'fase C direto', 'open', 'flexible', :'W5', 'waiting', now() + interval '20 hours')
returning id as jdir \gset

-- jconf: confirmado da C2 com o W5 (fica para o suporte decidir).
insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
values (:'C2', :'st', 'Rua C 8', 38.72, -9.14, 'fase C confirmado', 'open', 'flexible') returning id as jconf \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status) values (:'jconf', :'W5', 15, 'accepted') returning id as pconf \gset
update job_requests set status = 'confirmed', accepted_proposal_id = :'pconf',
  after_photo_paths = array[:'W5' || '/' || :'jconf' || '/depois.jpg'] where id = :'jconf';

-- jnew: outro pedido aberto da C2 para tentar propor depois de suspenso.
insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
values (:'C2', :'st', 'Rua C 9', 38.72, -9.14, 'fase C novo', 'open', 'flexible') returning id as jnew \gset

select count(*) as acts0 from admin_actions \gset

-- ── Colunas novas só o servidor muda ──
set role authenticated;
select t_as(:'C5');
select audit.err('T-ACC-01 a pessoa não lê nem mexe no estado da conta',
  $q$select count(*) from account_status$q$, 'permission denied');
select audit.err('T-ACC-02 a pessoa não se marca como ativa',
  format($q$insert into account_status(profile_id) values (%L)$q$, :'C5'), 'permission denied');
select audit.eq('T-ACC-03 sem estado, a app recebe objeto vazio',
  $q$select get_my_account_status()::text$q$, '{}');
reset role;

-- ── Recusas: sem sessão, utilizador normal, admin sem aal2 ──
create temp table acc_calls(name text, sql text);
insert into acc_calls values
  ('admin_suspend_user',       format($q$select admin_suspend_user(%L, 'other', 'nota de teste')$q$, :'W5')),
  ('admin_reactivate_user',    format($q$select admin_reactivate_user(%L, 'nota de teste')$q$, :'W5')),
  ('admin_schedule_closure',   format($q$select admin_schedule_closure(%L, 'other', 'nota de teste')$q$, :'W6')),
  ('admin_cancel_closure',     format($q$select admin_cancel_closure(%L, 'nota de teste')$q$, :'W6')),
  ('admin_export_user_data',   format($q$select admin_export_user_data(%L)$q$, :'C5')),
  ('admin_erase_user',         format($q$select admin_erase_user(%L, 'nota de teste')$q$, :'C6')),
  ('admin_hide_profile_photo', format($q$select admin_hide_profile_photo(%L, 'https://x/avatars/c5.jpg', 'other', 'nota de teste')$q$, :'C5')),
  ('admin_get_account',        format($q$select admin_get_account(%L)$q$, :'C5')),
  ('admin_resend_code',        format($q$select admin_resend_code(%L)$q$, :'W6')),
  ('admin_map_points',         $q$select * from admin_map_points()$q$);
grant select on acc_calls to anon, authenticated;

set role anon;
select t_as('');
select audit.err('T-ACC-10 sem sessão: ' || name, sql, 'permission denied') from acc_calls;
reset role;
set role authenticated;
select t_as(:'W1');
select audit.err('T-ACC-11 utilizador normal: ' || name, sql, 'Sem acesso') from acc_calls;
select t_as(:'AD');
select audit.err('T-ACC-12 admin sem segundo fator: ' || name, sql, 'Sem acesso') from acc_calls;
reset role;
select audit.eq('T-ACC-13 recusas não mudam nada',
  format($q$select (select count(*) from admin_actions) || ':' ||
     (select count(*) from profiles p where id in (%L, %L, %L) and deleted_at is null
        and not exists (select 1 from account_status s where s.profile_id = p.id))
     || ':' || (select avatar_url from profiles where id = %L)$q$, :'W5', :'W6', :'C6', :'C5'),
  :'acts0' || ':3:https://x/avatars/c5.jpg');

-- Ajudas internas não se chamam de fora.
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-ACC-14 account_suspend_core não se chama pela API',
  format($q$select account_suspend_core(%L, 'other', null)$q$, :'W5'), 'permission denied');
select audit.err('T-ACC-15 account_delete_core não se chama pela API',
  format($q$select account_delete_core(%L)$q$, :'C6'), 'permission denied');
select audit.err('T-ACC-16 process_account_closures não se chama pela API',
  $q$select process_account_closures()$q$, 'permission denied');
select audit.err('T-ACC-17 account_storage_paths não se chama pela API',
  format($q$select account_storage_paths(%L)$q$, :'C5'), 'permission denied');
select audit.err('T-ACC-18 is_account_suspended não se chama pela API',
  format($q$select is_account_suspended(%L)$q$, :'C5'), 'permission denied');
select audit.err('T-ACC-19 tabela das fotos de perfil ocultas é só do servidor',
  $q$select count(*) from profile_photos_hidden$q$, 'permission denied');

-- ── Suspender um jardineiro ──
select audit.err('T-ACC-20 motivo fora da lista', format($q$select admin_suspend_user(%L, 'zangado', 'nota de teste')$q$, :'W5'), 'motivo');
select audit.err('T-ACC-21 nota curta', format($q$select admin_suspend_user(%L, 'other', 'x')$q$, :'W5'), 'nota');
select audit.err('T-ACC-22 não se suspende a si próprio', format($q$select admin_suspend_user(%L, 'other', 'nota de teste')$q$, :'AD'), 'própria');
select audit.eq('T-ACC-23 suspender devolve os trabalhos aceites por decidir',
  format($q$select admin_suspend_user(%L, 'terms_violation', 'Três queixas de faltas.', 'Faltaste a três trabalhos marcados.')::text$q$, :'W5'), '1');
reset role;
select audit.eq('T-ACC-24 fica suspenso com motivo e mensagem',
  format($q$select suspended_reason || ':' || suspended_message from account_status where profile_id = %L and suspended_at is not null$q$, :'W5'),
  'terms_violation:Faltaste a três trabalhos marcados.');
select audit.eq('T-ACC-25 propostas pendentes dele retiradas e contadores certos',
  format($q$select string_agg(jp.status || '/' || jr.proposal_count, ',' order by jr.description)
     from job_proposals jp join job_requests jr on jr.id = jp.job_id
     where jp.worker_id = %L and jp.job_id in (%L, %L)$q$, :'W5', :'jopen', :'jw'),
  'superseded/1,superseded/0');
select audit.eq('T-ACC-26 a cliente é avisada sem dizer porquê',
  format($q$select count(*)::text from notifications where user_id = %L and related_id = %L
     and type = 'proposal_withdrawn' and body like '%%deixou de estar disponível%%'$q$, :'C2', :'jw'), '1');
select audit.eq('T-ACC-27 pedido direto à espera dele deixa de esperar',
  format($q$select (coalesce(direct_status, '') <> 'waiting' and direct_worker_id is null)::text from job_requests where id = %L$q$, :'jdir'), 'true');
select audit.eq('T-ACC-28 trabalho confirmado fica como estava',
  format($q$select status from job_requests where id = %L$q$, :'jconf'), 'confirmed');
select audit.eq('T-ACC-29 o jardineiro recebe o aviso com a mensagem e o contacto',
  format($q$select count(*)::text from notifications where user_id = %L and type = 'support_notice'
     and title = 'Conta suspensa' and body like 'Faltaste a três trabalhos marcados.%%suporte@projardim.pt%%'$q$, :'W5'), '1');
select audit.eq('T-ACC-30 sem cartão público nem pedidos novos da zona',
  format($q$select worker_can_use_public_card(%L)::text || ':' ||
     (select count(*) from job_candidate_workers((select j from job_requests j where id = %L)) where worker_id = %L)$q$,
     :'W5', :'jnew', :'W5'), 'false:0');
select audit.err('T-ACC-31 ninguém lhe faz pedidos diretos',
  format($q$insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode, direct_worker_id, direct_status, direct_until)
     values (%L, %L, 'x', 38.72, -9.14, 'x', 'open', 'flexible', %L, 'waiting', now() + interval '1 day')$q$, :'C2', :'st', :'W5'),
  'não está disponível');
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-ACC-32 suspender duas vezes', format($q$select admin_suspend_user(%L, 'other', 'nota de teste')$q$, :'W5'), 'já está suspensa');
select t_as(:'W5');
select audit.err('T-ACC-33 suspenso não faz propostas',
  format($q$select create_proposal(%L, 15, 2, 4, 1, null, today_pt()+3, '09:00')$q$, :'jnew'), 'suspensa');
select audit.err('T-ACC-34 suspenso não marca dias de trabalho',
  format($q$insert into job_work_days(job_id, day_number, started_at) values (%L, 1, now())$q$, :'jconf'), 'suspensa');
-- Quem não está suspenso continua a poder agir no trabalho com ele.
select t_as(:'C2');
select audit.ok('T-ACC-35 a cliente continua a poder mexer no trabalho confirmado',
  format($q$update job_requests set updated_at = now() where id = %L$q$, :'jconf'));

-- ── Suspender uma cliente ──
select t_aal2(:'AD');
select audit.eq('T-ACC-40 suspender a cliente',
  format($q$select admin_suspend_user(%L, 'illegal_content', 'Fotos com conteúdo ilegal.')::text$q$, :'C5'), '0');
reset role;
select audit.eq('T-ACC-41 pedido aberto fecha com motivo próprio e sem autor',
  format($q$select status || ':' || cancel_reason || ':' || (cancelled_by is null) from job_requests where id = %L$q$, :'jopen'),
  'cancelled:account_suspended:true');
select audit.eq('T-ACC-42 a proposta do W6 passa a recusada e o aviso fala do suporte',
  format($q$select (select status from job_proposals where job_id = %L and worker_id = %L) || ':' ||
     (select count(*) from notifications where user_id = %L and related_id = %L and body like 'O suporte da ProJardim cancelou%%')$q$,
     :'jopen', :'W6', :'W6', :'jopen'), 'rejected:1');
select audit.eq('T-ACC-43 sem mensagem própria, o aviso usa o texto padrão',
  format($q$select count(*)::text from notifications where user_id = %L and title = 'Conta suspensa'
     and body like 'A tua conta ProJardim foi suspensa pelo suporte.%%'$q$, :'C5'), '1');
set role authenticated;
select t_as(:'C5');
select audit.err('T-ACC-44 cliente suspensa não cria pedidos',
  format($q$insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
     values (%L, %L, 'x', 38.72, -9.14, 'x', 'open', 'flexible')$q$, :'C5', :'st'), 'suspensa');
select audit.eq('T-ACC-45 a app lê o próprio estado, sem o motivo interno',
  $q$select (s ? 'suspended_at')::text || ':' || (s ? 'suspended_reason') from get_my_account_status() s$q$, 'true:false');
reset role;

-- ── Reativar ──
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-ACC-50 reativar pede nota', format($q$select admin_reactivate_user(%L, '')$q$, :'W5'), 'nota');
select audit.err('T-ACC-51 reativar conta ativa', format($q$select admin_reactivate_user(%L, 'nota de teste')$q$, :'W6'), 'não está suspensa');
select audit.ok('T-ACC-52 reativar o jardineiro', format($q$select admin_reactivate_user(%L, 'Contestou e tinha razão.')$q$, :'W5'));
reset role;
select audit.eq('T-ACC-53 volta ao normal e é avisado',
  format($q$select (suspended_at is null and suspended_reason is null)::text || ':' || worker_can_use_public_card(%L)
     || ':' || (select count(*) from notifications where user_id = %L and title = 'Conta reativada')
     from account_status where profile_id = %L$q$, :'W5', :'W5', :'W5'), 'true:true:1');
set role authenticated;
select t_as(:'W5');
select audit.ok('T-ACC-54 reativado volta a propor',
  format($q$select create_proposal(%L, 15, 2, 4, 1, null, today_pt()+3, '09:00')$q$, :'jnew'));
reset role;

-- ── Encerramento com 30 dias ──
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-ACC-60 marcar encerramento a 30 dias',
  format($q$select (admin_schedule_closure(%L, 'terms_violation', 'Perfil com dados falsos.', 'O perfil tem dados falsos.')::date - current_date)::text$q$, :'W6'), '30');
select audit.err('T-ACC-61 não se marca duas vezes',
  format($q$select admin_schedule_closure(%L, 'other', 'nota de teste')$q$, :'W6'), 'Já há um encerramento');
reset role;
select audit.eq('T-ACC-62 aviso com a data e a mensagem; a conta continua ativa',
  format($q$select (not is_account_suspended(%L))::text || ':' ||
     (select count(*) from notifications where user_id = %L and title = 'Aviso de encerramento da conta'
        and body like '%%' || to_char(now() + interval '30 days', 'DD/MM/YYYY') || '. O perfil tem dados falsos.%%')$q$,
     :'W6', :'W6'), 'true:1');
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-ACC-63 cancelar o encerramento', format($q$select admin_cancel_closure(%L, 'Corrigiu o perfil.')$q$, :'W6'));
select audit.err('T-ACC-64 cancelar sem encerramento marcado', format($q$select admin_cancel_closure(%L, 'nota de teste')$q$, :'W6'), 'não tem encerramento');
select audit.ok('T-ACC-65 marcar outra vez', format($q$select admin_schedule_closure(%L, 'terms_violation', 'Voltou a pôr dados falsos.')$q$, :'W6'));
reset role;
select t_as('');
select audit.eq('T-ACC-66 o cron não faz nada antes da data', $q$select process_account_closures()::text$q$, '0');
update account_status set closing_at = now() - interval '1 minute' where profile_id = :'W6';
select audit.eq('T-ACC-67 na data, o cron suspende', $q$select process_account_closures()::text$q$, '1');
select audit.eq('T-ACC-68 suspensa com o motivo do aviso e registo de sistema',
  format($q$select suspended_reason || ':' ||
     (select count(*) from admin_actions where action = 'closure_done' and target_id = %L and admin_id is null)
     from account_status where profile_id = %L$q$, :'W6', :'W6'), 'terms_violation:1');
select audit.eq('T-ACC-69 o cron corre outra vez sem repetir', $q$select process_account_closures()::text$q$, '0');
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-ACC-70 reativar depois do encerramento', format($q$select admin_reactivate_user(%L, 'Acordo por email.')$q$, :'W6'));
reset role;
select audit.eq('T-ACC-71 o encerramento já cumprido não volta a disparar',
  format($q$select (closing_at is null and suspended_at is null)::text from account_status where profile_id = %L$q$, :'W6'), 'true');
select audit.eq('T-ACC-72 o cron diário está marcado',
  $q$select count(*)::text from cron.job where jobname = 'account-closures' and command = 'SELECT process_account_closures()'$q$, '1');

-- ── Estado da conta e reenviar código ──
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-ACC-80 email mascarado e por confirmar',
  format($q$select (admin_get_account(%L)->>'email_masked') || ':' || (admin_get_account(%L)->>'email_confirmed')$q$, :'W6', :'W6'),
  'w***@teste.local:false');
select audit.eq('T-ACC-81 trabalhos em curso e o que impede eliminar',
  format($q$select (admin_get_account(%L)->>'jobs_in_progress') || ':' || ((admin_get_account(%L)->>'deletion_blocker') is not null)$q$, :'W5', :'W5'),
  '1:true');
select audit.eq('T-ACC-82 reenviar código devolve o email para a app enviar',
  format($q$select admin_resend_code(%L)$q$, :'W6'), 'w6@teste.local');
select audit.err('T-ACC-83 email já confirmado', format($q$select admin_resend_code(%L)$q$, :'W5'), 'já está confirmado');

-- ── Fotos de perfil e portefólio ──
select audit.ok('T-ACC-90 retirar a foto de perfil',
  format($q$select admin_hide_profile_photo(%L, 'https://x/avatars/c5.jpg', 'illegal_content', 'Foto imprópria.')$q$, :'C5'));
select audit.ok('T-ACC-91 retirar uma foto do portefólio',
  format($q$select admin_hide_profile_photo(%L, 'https://x/p/w5-1.jpg', 'personal_data', 'Mostra uma matrícula.')$q$, :'W5'));
select audit.err('T-ACC-92 foto que não é do perfil',
  format($q$select admin_hide_profile_photo(%L, 'https://x/outra.jpg', 'other', 'nota de teste')$q$, :'W5'), 'não encontrada');
reset role;
select audit.eq('T-ACC-93 fotos saem do perfil e vão para arquivo',
  format($q$select coalesce((select avatar_url from profiles where id = %L), 'sem') || ':' ||
     (select array_to_string(photos, ',') from worker_profiles where profile_id = %L) || ':' ||
     (select string_agg(kind, ',' order by kind) from profile_photos_hidden where profile_id in (%L, %L))$q$,
     :'C5', :'W5', :'C5', :'W5'), 'sem:https://x/p/w5-2.jpg:avatar,portfolio');
select audit.eq('T-ACC-94 a pessoa é avisada',
  format($q$select count(*)::text from notifications where user_id in (%L, %L) and title = 'Foto retirada'$q$, :'C5', :'W5'), '2');

-- ── Exportar ──
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-ACC-100 exportação da cliente tem conta, perfil e pedidos com fotos',
  format($q$select (d->'account'->>'email') || ':' || (d->'profile'->>'full_name') || ':' ||
     jsonb_array_length(d->'jobs_as_client') || ':' || jsonb_array_length(d->'jobs_as_client'->0->'photos')
     from admin_export_user_data(%L) d$q$, :'C5'), 'c5@teste.local:Cliente Cinco:1:1');
select audit.eq('T-ACC-101 exportação do jardineiro tem propostas, agenda e ficheiros',
  format($q$select jsonb_array_length(d->'proposals') || ':' || jsonb_array_length(d->'calendar'->'entries') || ':' ||
     (d->'storage'->'avatars'->>0) || ':' || jsonb_array_length(d->'storage'->'job_photos')
     from admin_export_user_data(%L) d$q$, :'W5'),
  '4:1:' || :'W5' || '.jpg:1');
select audit.eq('T-ACC-102 do pedido onde trabalhou só sai a localidade, nunca a morada da cliente',
  format($q$select (d::text like '%%Rua C 8%%')::text from admin_export_user_data(%L) d$q$, :'W5'), 'false');
select audit.eq('T-ACC-103 avaliações recebidas sem quem avaliou',
  format($q$select count(*)::text from admin_export_user_data(%L) d, jsonb_array_elements(d->'ratings_received') r where r ? 'rater_id'$q$, :'W5'), '0');
reset role;

-- ── Mapa ──
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-ACC-110 jardineiros com raio e pedidos ativos',
  format($q$select (select radius_km || ':' || plan || ':' || status from admin_map_points() where kind = 'worker' and id = %L)
     || '|' || (select count(*) from admin_map_points() where kind = 'job' and id in (%L, %L, %L))$q$, :'W5', :'jw', :'jconf', :'jopen'),
  '25:free:active|2');

-- ── Eliminar a pedido ──
select audit.err('T-ACC-120 eliminar pede nota', format($q$select admin_erase_user(%L, '')$q$, :'C5'), 'nota');
select audit.err('T-ACC-121 não se elimina a si próprio', format($q$select admin_erase_user(%L, 'nota de teste')$q$, :'AD'), 'usa a app');
select audit.err('T-ACC-122 trabalho em curso impede eliminar, como na app',
  format($q$select admin_erase_user(%L, 'Pedido por email a 16/11.')$q$, :'W5'), 'trabalho');
select audit.eq('T-ACC-123 eliminar a cliente suspensa devolve os ficheiros a apagar',
  format($q$select (r->'avatars'->>0) || ':' || jsonb_array_length(r->'job_photos')
     from admin_erase_user(%L, 'Pedido por email a 16/11.') r$q$, :'C5'), :'C5' || '.jpg:1');
reset role;
select audit.eq('T-ACC-124 a conta fica eliminada como na app',
  format($q$select full_name || ':' || (deleted_at is not null) || ':' ||
     (select email like 'eliminado+%%' from auth.users where id = %L) from profiles where id = %L$q$, :'C5', :'C5'),
  'Conta eliminada:true:true');
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-ACC-125 eliminar duas vezes', format($q$select admin_erase_user(%L, 'nota de teste')$q$, :'C5'), 'já foi eliminada');
select audit.err('T-ACC-126 conta eliminada não se suspende', format($q$select admin_suspend_user(%L, 'other', 'nota de teste')$q$, :'C5'), 'eliminada');

-- Quem está suspenso pode eliminar a própria conta na app.
select audit.ok('T-ACC-127 suspender a C6', format($q$select admin_suspend_user(%L, 'other', 'Teste de eliminação.')$q$, :'C6'));
select t_as(:'C6');
select audit.ok('T-ACC-128 conta suspensa elimina-se na app', $q$select delete_my_account()$q$);
select audit.err('T-ACC-129 mas a autorização de escrita não fica para depois',
  format($q$insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
     values (%L, %L, 'x', 38.72, -9.14, 'x', 'open', 'flexible')$q$, :'C6', :'st'), 'suspensa');
reset role;
select audit.eq('T-ACC-130 delete_my_account continua só para quem tem sessão',
  $q$select has_function_privilege('anon', 'delete_my_account()', 'execute')::text || ':' ||
     has_function_privilege('authenticated', 'delete_my_account()', 'execute')$q$, 'false:true');

-- ── Registo ──
select audit.eq('T-ACC-140 cada ação tem registo',
  $q$select string_agg(distinct action, ',' order by action) from admin_actions
     where action in ('suspend_user','reactivate_user','schedule_closure','cancel_closure','closure_done',
                      'export_user','erase_user','hide_profile_photo','resend_code','view_map')$q$,
  'cancel_closure,closure_done,erase_user,export_user,hide_profile_photo,reactivate_user,resend_code,schedule_closure,suspend_user,view_map');
select audit.eq('T-ACC-141 suspensão fica com motivo, nota e mensagem',
  format($q$select details->>'reason' || ':' || (details->>'note') || ':' || (details->>'jobs_in_progress')
     from admin_actions where action = 'suspend_user' and target_id = %L$q$, :'W5'),
  'terms_violation:Três queixas de faltas.:1');
select audit.eq('T-ACC-142 nenhuma RPC recebe o id de quem chama',
  $q$select count(*)::text from pg_proc p where proname like 'admin\_%' and exists (
     select 1 from unnest(p.proargnames) a where a in ('p_admin_id','p_user_id','p_actor_id','p_created_by'))$q$, '0');

-- ── Correr a migration outra vez ──
\set QUIET on
\ir ../../migrations/0080_admin_accounts.sql
\set QUIET off
select audit.eq('T-ACC-150 correr outra vez não perde estado nem duplica o cron',
  format($q$select (select count(*) from profiles where id = %L and deleted_at is not null) || ':' ||
     (select count(*) from profile_photos_hidden) || ':' || (select count(*) from cron.job where jobname = 'account-closures')$q$, :'C6'),
  '1:2:1');

select format('%s | %s | %s', case when ok then 'PASS' else 'FAIL' end, id, coalesce(detail, ''))
from audit.results where id like 'T-ACC-%' order by seq;
select format('TOTAL %s | PASS %s | FAIL %s', count(*), count(*) filter (where ok), count(*) filter (where not ok))
from audit.results where id like 'T-ACC-%';
