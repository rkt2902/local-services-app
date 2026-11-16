-- Painel de admin para suporte, fase B (migration 0079), 16/11/2026.
-- Corre depois do 10_flows.sql (bash run.sh keep), na mesma BD. O
-- 50_admin_support.sql pode correr antes ou não. Usa a cliente C2 porque
-- a C1 elimina a conta no 10_flows. Só para a BD local de teste.
--
-- Cada RPC nova tem 3 recusas (sem sessão, utilizador normal, admin sem
-- segundo fator), cada ação fica em admin_actions com motivo e nota e avisa
-- as pessoas, e nada se apaga de vez (avaliações e fotos vão para arquivo).

\set C2 '00000000-0000-0000-0000-0000000000c2'
\set W1 '00000000-0000-0000-0000-0000000000a1'
\set W2 '00000000-0000-0000-0000-0000000000a2'
\set AD '00000000-0000-0000-0000-0000000000ad'

reset role;
select t_as('');
select id as st from service_types order by sort_order limit 1 \gset

-- ── Preparação (como postgres) ──
-- jconf: confirmado com W1, e uma proposta pendente de W2.
insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
values (:'C2', :'st', 'Rua B 1', 38.72, -9.14, 'fase B confirmado', 'open', 'flexible') returning id as jconf \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status) values (:'jconf', :'W1', 15, 'accepted') returning id as pconf \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status) values (:'jconf', :'W2', 14, 'pending');
update job_requests set status='confirmed', accepted_proposal_id=:'pconf' where id=:'jconf';

-- jconf2: confirmado com W1, para marcar como concluído e anular.
insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode)
values (:'C2', :'st', 'Rua B 2', 38.72, -9.14, 'fase B concluir', 'open', 'flexible') returning id as jconf2 \gset
insert into job_proposals(job_id, worker_id, hourly_rate, status) values (:'jconf2', :'W1', 15, 'accepted') returning id as pconf2 \gset
update job_requests set status='confirmed', accepted_proposal_id=:'pconf2',
  before_photo_paths=array['b/antes1.jpg','b/antes2.jpg'] where id=:'jconf2';

-- jnr: expirou sem resposta, com data fixa já passada.
insert into job_requests(client_id, service_type_id, address_text, location_lat, location_lng, description, status, date_mode, preferred_date, expires_at)
values (:'C2', :'st', 'Rua B 3', 38.72, -9.14, 'fase B expirado', 'open', 'fixed', today_pt() - 3, now() - interval '1 day') returning id as jnr \gset
update job_requests set status='no_response' where id=:'jnr';

-- Avaliação da C2 ao W1 no jconf2 (só para moderar).
insert into ratings(job_id, rater_id, ratee_id, stars, comment)
values (:'jconf2', :'C2', :'W1', 1, 'comentário com o telefone 910 000 000') returning id as rt \gset

-- Reporte da C2 no jconf.
insert into job_reports(job_id, reporter_id, description) values (:'jconf', :'C2', 'o jardineiro não apareceu') returning id as rep \gset
insert into job_reports(job_id, reporter_id, description) values (:'jconf', :'C2', 'reporte repetido') returning id as rep2 \gset

select count(*) as acts0 from admin_actions \gset
select count(*) as notif0 from notifications \gset

-- ── Ajudas ──
select audit.eq('T-RES-01 sexta 10h + 1 dia útil = segunda 10h',
  $q$select to_char(add_business_days('2026-11-13 10:00 Europe/Lisbon', 1) at time zone 'Europe/Lisbon', 'Dy DD HH24')$q$, 'Mon 16 10');
select audit.eq('T-RES-02 15 dias úteis = 3 semanas',
  $q$select (add_business_days('2026-11-16 09:00 Europe/Lisbon', 15) - '2026-11-16 09:00 Europe/Lisbon'::timestamptz)::text$q$, '21 days');
select audit.eq('T-RES-03 prazo de denúncia = 7 dias corridos',
  $q$select (support_case_due('abuse', '2026-11-13 10:00+00') - '2026-11-13 10:00+00'::timestamptz)::text$q$, '7 days');

-- ── Tabelas novas são só do servidor ──
set role authenticated;
select t_as(:'C2');
select audit.err('T-RES-04 utilizador não lê casos', $q$select count(*) from support_cases$q$, 'permission denied');
select audit.err('T-RES-05 utilizador não lê notas internas', $q$select count(*) from admin_notes$q$, 'permission denied');
select audit.err('T-RES-06 utilizador não lê avaliações ocultas', $q$select count(*) from ratings_hidden$q$, 'permission denied');
select audit.err('T-RES-07 utilizador não lê fotos ocultas', $q$select count(*) from job_photos_hidden$q$, 'permission denied');
select audit.eq('T-RES-08 reporte novo da app fica sempre como novo, mesmo que peça outro estado',
  format($q$with i as (insert into job_reports(job_id, reporter_id, description, status, resolved_at)
     values (%L, %L, 'teste estado', 'resolved', now()) returning status, resolved_at)
     select status || ':' || (resolved_at is null) from i$q$, :'jconf', :'C2'), 'new:true');
reset role;

-- ── Recusas: sem sessão, utilizador normal, admin sem aal2 ──
create temp table res_calls(name text, sql text);
insert into res_calls values
  ('admin_case_create',       format($q$select admin_case_create('help', 'x', %L)$q$, :'C2')),
  ('admin_case_update',       $q$select admin_case_update(gen_random_uuid(), 'resolved', 'x')$q$),
  ('admin_case_add_note',     $q$select admin_case_add_note(gen_random_uuid(), 'x')$q$),
  ('admin_list_cases',        $q$select * from admin_list_cases()$q$),
  ('admin_get_case',          $q$select admin_get_case(gen_random_uuid())$q$),
  ('admin_list_reports',      $q$select * from admin_list_reports()$q$),
  ('admin_set_report_status', format($q$select admin_set_report_status(%L, 'dismissed', 'sem fundamento')$q$, :'rep2')),
  ('admin_cancel_job',        format($q$select admin_cancel_job(%L, 'other', 'nota de teste')$q$, :'jconf')),
  ('admin_reopen_job',        format($q$select admin_reopen_job(%L, 'other', 'nota de teste')$q$, :'jnr')),
  ('admin_set_job_status',    format($q$select admin_set_job_status(%L, 'completed', 'other', 'nota de teste')$q$, :'jconf2')),
  ('admin_hide_rating',       format($q$select admin_hide_rating(%L, 'personal_data', 'nota de teste')$q$, :'rt')),
  ('admin_restore_rating',    format($q$select admin_restore_rating(%L, 'nota de teste')$q$, :'rt')),
  ('admin_hide_photo',        format($q$select admin_hide_photo(%L, 'b/antes1.jpg', 'other', 'nota de teste')$q$, :'jconf2')),
  ('admin_list_ratings',      $q$select * from admin_list_ratings()$q$),
  ('admin_add_note',          format($q$select admin_add_note(%L, 'x')$q$, :'C2')),
  ('admin_list_notes',        format($q$select * from admin_list_notes(%L)$q$, :'C2')),
  ('admin_list_actions',      $q$select * from admin_list_actions()$q$);
grant select on res_calls to anon, authenticated;

set role anon;
select t_as('');
select audit.err('T-RES-10 sem sessão: ' || name, sql, 'permission denied') from res_calls;
reset role;
set role authenticated;
select t_as(:'W1');
select audit.err('T-RES-11 utilizador normal: ' || name, sql, 'Sem acesso') from res_calls;
select t_as(:'AD');
select audit.err('T-RES-12 admin sem segundo fator: ' || name, sql, 'Sem acesso') from res_calls;
reset role;
select audit.eq('T-RES-13 recusas não mudam nada',
  format($q$select (select count(*) from admin_actions) || ':' || (select status from job_requests where id=%L)
     || ':' || (select count(*) from ratings where id=%L)$q$, :'jconf', :'rt'),
  :'acts0' || ':confirmed:1');

-- Ajudas internas não se chamam de fora.
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-RES-14 add_business_days não se chama pela API',
  $q$select add_business_days(now(), 1)$q$, 'permission denied');
select audit.err('T-RES-15 admin_assert_reason não se chama pela API',
  $q$select admin_assert_reason('other', 'nota')$q$, 'permission denied');

-- ── Casos ──
select audit.err('T-RES-20 tipo de caso inválido', $q$select admin_case_create('urgente', 'x')$q$, 'inválido');
select audit.err('T-RES-21 caso sem resumo', $q$select admin_case_create('help', '   ')$q$, 'resumo');
select audit.val('T-RES-22 caso a partir de um reporte',
  format($q$select admin_case_create('report', 'Jardineiro não apareceu', p_report_id=>%L)$q$, :'rep')) as case1 \gset
reset role;
select audit.eq('T-RES-23 caso herda pessoa e pedido do reporte',
  format($q$select (person_id=%L and job_id=%L)::text from support_cases where id=%L$q$, :'C2', :'jconf', :'case1'), 'true');
select audit.eq('T-RES-24 prazo do reporte = 2 dias úteis, receção = 1 dia útil',
  format($q$select (due_at = add_business_days(created_at, 2) and ack_due_at = add_business_days(created_at, 1))::text from support_cases where id=%L$q$, :'case1'), 'true');
select audit.eq('T-RES-25 o reporte passa a em análise e fica ligado',
  format($q$select status || ':' || (case_id=%L) from job_reports where id=%L$q$, :'case1', :'rep'), 'in_review:true');
set role authenticated;
select t_aal2(:'AD');
select audit.val('T-RES-26 caso de ajuda por email, sem pessoa',
  $q$select admin_case_create('gdpr', 'Pede cópia dos dados', p_contact_email=>'alguem@exemplo.pt')$q$) as case2 \gset
reset role;
select audit.eq('T-RES-27 números seguidos',
  format($q$select ((select number from support_cases where id=%L) - (select number from support_cases where id=%L))::text$q$, :'case2', :'case1'), '1');
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-RES-28 nota interna', format($q$select admin_case_add_note(%L, 'Liguei à cliente.')$q$, :'case1'));
reset role;
select audit.eq('T-RES-29 nota interna não conta como resposta',
  format($q$select (first_reply_at is null)::text from support_cases where id=%L$q$, :'case1'), 'true');
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-RES-30 resposta enviada', format($q$select admin_case_add_note(%L, 'Recebemos o teu reporte.', 'reply')$q$, :'case1'));
reset role;
select audit.eq('T-RES-31 a primeira resposta marca a receção',
  format($q$select (first_reply_at is not null)::text from support_cases where id=%L$q$, :'case1'), 'true');
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-RES-32 nota vazia', format($q$select admin_case_add_note(%L, '  ')$q$, :'case1'), 'vazia');
select audit.err('T-RES-33 fechar sem decisão', format($q$select admin_case_update(%L, 'resolved')$q$, :'case1'), 'decisão');
select audit.ok('T-RES-34 à espera da pessoa', format($q$select admin_case_update(%L, 'waiting_user')$q$, :'case1'));
select audit.eq('T-RES-35 lista de casos abertos traz os dois, o mais urgente primeiro',
  format($q$select string_agg(case_id::text, ',' order by ord) from (select case_id, row_number() over () ord from admin_list_cases()) s
     where case_id in (%L, %L)$q$, :'case1', :'case2'), :'case1' || ',' || :'case2');
select audit.eq('T-RES-36 ficha do caso traz notas e reporte',
  format($q$select jsonb_array_length(j->'notes') || ':' || jsonb_array_length(j->'reports') || ':' || (j->>'person_email')
     from admin_get_case(%L) j$q$, :'case1'), '2:1:c2@teste.local');
select audit.ok('T-RES-37 fechar com decisão',
  format($q$select admin_case_update(%L, 'resolved', 'Pedido cancelado pelo suporte; cliente avisada.')$q$, :'case1'));
reset role;
select audit.eq('T-RES-38 fechar o caso resolve o reporte',
  format($q$select status || ':' || (resolved_at is not null) from job_reports where id=%L$q$, :'rep'), 'resolved:true');
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-RES-39 caso fechado sai dos abertos e aparece em todos',
  format($q$select (not exists (select 1 from admin_list_cases() where case_id=%L)
     and exists (select 1 from admin_list_cases('all') where case_id=%L))::text$q$, :'case1', :'case1'), 'true');
select audit.eq('T-RES-40 casos por pessoa',
  format($q$select count(*)::text from admin_list_cases('all', p_target_id=>%L)$q$, :'C2'), '1');

-- ── Reportes ──
select audit.eq('T-RES-41 lista de reportes abertos traz o repetido e não o resolvido',
  format($q$select (exists (select 1 from admin_list_reports() where report_id=%L)
     and not exists (select 1 from admin_list_reports() where report_id=%L))::text$q$, :'rep2', :'rep'), 'true');
select audit.eq('T-RES-42 o reporte diz quem reportou e o prazo',
  format($q$select reporter_role || ':' || (due_at > created_at) from admin_list_reports() where report_id=%L$q$, :'rep2'), 'client:true');
select audit.err('T-RES-43 dispensar sem nota',
  format($q$select admin_set_report_status(%L, 'dismissed')$q$, :'rep2'), 'nota');
select audit.ok('T-RES-44 dispensar com nota',
  format($q$select admin_set_report_status(%L, 'dismissed', 'Repetido do anterior.')$q$, :'rep2'));

-- ── Cancelar ──
select audit.err('T-RES-50 motivo fora da lista',
  format($q$select admin_cancel_job(%L, 'porque sim', 'nota de teste')$q$, :'jconf'), 'motivo');
select audit.err('T-RES-51 nota curta',
  format($q$select admin_cancel_job(%L, 'other', 'ok')$q$, :'jconf'), 'nota');
select audit.ok('T-RES-52 cancelar pelo suporte',
  format($q$select admin_cancel_job(%L, 'terms_violation', 'Jardineiro faltou duas vezes.', 'Cancelámos este pedido a teu pedido.')$q$, :'jconf'));
reset role;
select audit.eq('T-RES-53 pedido fica cancelado pelo suporte, sem autor',
  format($q$select status || ':' || cancel_reason || ':' || (cancelled_by is null) from job_requests where id=%L$q$, :'jconf'), 'cancelled:support:true');
select audit.eq('T-RES-54 a proposta pendente do outro jardineiro fica recusada',
  format($q$select status from job_proposals where job_id=%L and worker_id=%L$q$, :'jconf', :'W2'), 'rejected');
select audit.eq('T-RES-55 cliente e jardineiro recebem o aviso com a mensagem',
  format($q$select string_agg(user_id::text, ',' order by user_id) from notifications
     where related_id=%L and type='job_cancelled' and body like 'Cancelámos este pedido a teu pedido.%%'$q$, :'jconf'),
  :'W1' || ',' || :'C2');
select audit.eq('T-RES-58 o jardineiro da proposta pendente sabe que foi o suporte',
  format($q$select (body like 'O suporte da ProJardim cancelou%%')::text from notifications where related_id=%L and user_id=%L and type='proposal_rejected'$q$, :'jconf', :'W2'), 'true');
select audit.eq('T-RES-56 linha do tempo marca o cancelamento pelo admin',
  format($q$select actor_kind from job_events where job_id=%L and event_type='cancelled'$q$, :'jconf'), 'admin');
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-RES-57 não se cancela duas vezes',
  format($q$select admin_cancel_job(%L, 'other', 'nota de teste')$q$, :'jconf'), 'fechado');

-- ── Reabrir ──
select audit.err('T-RES-60 só pedidos expirados',
  format($q$select admin_reopen_job(%L, 'app_error', 'nota de teste')$q$, :'jconf'), 'expiraram');
select audit.ok('T-RES-61 reabrir o expirado',
  format($q$select admin_reopen_job(%L, 'app_error', 'Expirou por erro na app.')$q$, :'jnr'));
reset role;
select audit.eq('T-RES-62 volta a aberto por 48 horas e a data passada fica flexível',
  format($q$select status || ':' || (expires_at between now() + interval '47 hours' and now() + interval '49 hours')
     || ':' || date_mode || ':' || (preferred_date is null) from job_requests where id=%L$q$, :'jnr'),
  'open:true:flexible:true');
select audit.eq('T-RES-63 a cliente é avisada',
  format($q$select count(*)::text from notifications where related_id=%L and type='job_reopened' and user_id=%L$q$, :'jnr', :'C2'), '1');
select t_as('');
select audit.ok('T-RES-64 a expiração automática corre', $q$select auto_expire_jobs()$q$);
select audit.eq('T-RES-65 e não volta a fechar o pedido reaberto',
  format($q$select status from job_requests where id=%L$q$, :'jnr'), 'open');

-- ── Corrigir o estado ──
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-RES-70 anular confirmação de um trabalho por concluir',
  format($q$select admin_set_job_status(%L, 'awaiting_confirmation', 'app_error', 'nota de teste')$q$, :'jconf2'), 'concluído');
select audit.err('T-RES-71 estado fora da lista',
  format($q$select admin_set_job_status(%L, 'open', 'app_error', 'nota de teste')$q$, :'jconf2'), 'inválido');
select audit.ok('T-RES-72 marcar como concluído',
  format($q$select admin_set_job_status(%L, 'completed', 'app_error', 'Trabalho feito, a app não fechou.')$q$, :'jconf2'));
reset role;
select audit.eq('T-RES-73 concluído, com datas preenchidas e os dois avisados',
  format($q$select status || ':' || (marked_done_at is not null) || ':' ||
     (select count(*) from notifications where related_id=%L and type='job_completed') from job_requests where id=%L$q$, :'jconf2', :'jconf2'),
  'completed:true:2');
set role authenticated;
select t_aal2(:'AD');
select audit.ok('T-RES-74 anular a confirmação',
  format($q$select admin_set_job_status(%L, 'awaiting_confirmation', 'user_request', 'Cliente diz que ficou por acabar.')$q$, :'jconf2'));
reset role;
select audit.eq('T-RES-75 volta a esperar pela cliente, com 7 dias novos',
  format($q$select status || ':' || (marked_done_at > now() - interval '1 minute') from job_requests where id=%L$q$, :'jconf2'),
  'awaiting_confirmation:true');
select audit.eq('T-RES-76 cliente recebe pedido de confirmação e jardineiro aviso do suporte',
  format($q$select string_agg(type, ',' order by type) from notifications where related_id=%L and type in ('job_marked_done','support_notice')
     and created_at > now() - interval '1 minute'$q$, :'jconf2'), 'job_marked_done,support_notice');

-- ── Avaliações ──
select avg_rating as avg0 from worker_rating_summary where worker_id=:'W1' \gset
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-RES-80 avaliações visíveis com filtro de estrelas',
  format($q$select count(*)::text from admin_list_ratings(p_stars=>1) where rating_id=%L$q$, :'rt'), '1');
select audit.ok('T-RES-81 ocultar avaliação',
  format($q$select admin_hide_rating(%L, 'personal_data', 'Comentário tem o telefone.')$q$, :'rt'));
reset role;
select audit.eq('T-RES-82 sai das avaliações e fica no arquivo',
  format($q$select (select count(*) from ratings where id=%L) || ':' || (select hidden_reason from ratings_hidden where id=%L)$q$, :'rt', :'rt'),
  '0:personal_data');
select audit.eq('T-RES-83 a média do jardineiro deixa de contar com ela',
  format($q$select (coalesce((select avg_rating from worker_rating_summary where worker_id=%L), 0) <> %s)::text$q$, :'W1', coalesce(nullif(:'avg0', ''), '0')), 'true');
select audit.eq('T-RES-84 quem avaliou é avisado',
  format($q$select count(*)::text from notifications where user_id=%L and type='support_notice' and title='Avaliação ocultada'$q$, :'C2'), '1');
select audit.err('T-RES-85 não se volta a avaliar o mesmo trabalho',
  format($q$insert into ratings(job_id, rater_id, ratee_id, stars) values (%L, %L, %L, 5)$q$, :'jconf2', :'C2', :'W1'), 'Já avaliaste');
set role authenticated;
select t_aal2(:'AD');
select audit.eq('T-RES-86 aparece nas ocultas',
  format($q$select (hidden and hidden_reason='personal_data')::text from admin_list_ratings(p_hidden=>true) where rating_id=%L$q$, :'rt'), 'true');
select audit.err('T-RES-87 ocultar outra vez', format($q$select admin_hide_rating(%L, 'other', 'nota de teste')$q$, :'rt'), 'não encontrada');
select audit.ok('T-RES-88 repor avaliação', format($q$select admin_restore_rating(%L, 'Afinal não tinha dados.')$q$, :'rt'));
reset role;
select audit.eq('T-RES-89 volta tal e qual',
  format($q$select stars || ':' || (select count(*) from ratings_hidden where id=%L) from ratings where id=%L$q$, :'rt', :'rt'), '1:0');

-- ── Fotos ──
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-RES-90 foto que não é do pedido',
  format($q$select admin_hide_photo(%L, 'outra/foto.jpg', 'other', 'nota de teste')$q$, :'jconf2'), 'não encontrada');
select audit.ok('T-RES-91 ocultar foto de antes',
  format($q$select admin_hide_photo(%L, 'b/antes1.jpg', 'illegal_content', 'Aparece a cara de uma criança.')$q$, :'jconf2'));
reset role;
select audit.eq('T-RES-92 sai do pedido e fica no arquivo',
  format($q$select array_to_string(before_photo_paths, ',') || ':' || (select kind from job_photos_hidden where job_id=%L) from job_requests where id=%L$q$, :'jconf2', :'jconf2'),
  'b/antes2.jpg:before');
select audit.eq('T-RES-93 o jardineiro que tirou a foto é avisado',
  format($q$select count(*)::text from notifications where user_id=%L and related_id=%L and title='Foto ocultada'$q$, :'W1', :'jconf2'), '1');

-- ── Notas internas ──
set role authenticated;
select t_aal2(:'AD');
select audit.err('T-RES-100 nota numa ficha que não existe',
  $q$select admin_add_note(gen_random_uuid(), 'nota')$q$, 'não encontrada');
select audit.ok('T-RES-101 nota na ficha da cliente', format($q$select admin_add_note(%L, 'Cliente prefere email.')$q$, :'C2'));
select audit.ok('T-RES-102 nota na ficha do pedido', format($q$select admin_add_note(%L, 'Ver caso #1.')$q$, :'jconf'));
select audit.eq('T-RES-103 notas por ficha, com autor',
  format($q$select string_agg(body || ' / ' || author_email, ';') from admin_list_notes(%L)$q$, :'C2'), 'Cliente prefere email. / ad@teste.local');

-- ── Registo ──
select audit.eq('T-RES-110 sem consultas, o registo só traz mudanças',
  $q$select count(*)::text from admin_list_actions(p_include_reads=>false, p_limit=>100) where action like 'view\_%' or action='search'$q$, '0');
select audit.eq('T-RES-111 o cancelamento fica com motivo e nota',
  format($q$select details->>'reason' || ':' || (details->>'note') from admin_list_actions('cancel_job', %L)$q$, :'jconf'),
  'terms_violation:Jardineiro faltou duas vezes.');
reset role;
select audit.eq('T-RES-112 cada ação tem registo',
  $q$select string_agg(distinct action, ',' order by action) from admin_actions
     where action in ('case_create','case_update','case_note','report_status','cancel_job','reopen_job','set_job_status','hide_rating','restore_rating','hide_photo','add_note','view_case')$q$,
  'add_note,cancel_job,case_create,case_note,case_update,hide_photo,hide_rating,reopen_job,report_status,restore_rating,set_job_status,view_case');
select audit.eq('T-RES-113 nenhuma RPC nova recebe o id de quem chama',
  $q$select count(*)::text from pg_proc p where proname like 'admin\_%' and exists (
     select 1 from unnest(p.proargnames) a where a in ('p_admin_id','p_user_id','p_actor_id','p_created_by'))$q$, '0');

-- ── Correr a migration outra vez ──
\set QUIET on
\ir ../../migrations/0079_admin_support_resolve.sql
\set QUIET off
select audit.eq('T-RES-120 correr outra vez não perde casos nem arquivo',
  $q$select (select count(*) from support_cases) || ':' || (select count(*) from job_photos_hidden)$q$, '2:1');

select format('%s | %s | %s', case when ok then 'PASS' else 'FAIL' end, id, coalesce(detail, ''))
from audit.results where id like 'T-RES-%' order by seq;
select format('TOTAL %s | PASS %s | FAIL %s', count(*), count(*) filter (where ok), count(*) filter (where not ok))
from audit.results where id like 'T-RES-%';
