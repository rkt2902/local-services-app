-- 0075_web_test_fixes.sql
-- NOVA, NÃO APLICADA. Aplicar no SQL Editor depois da 0074.
--
-- Achados dos testes web com várias contas de 12/11
-- (relatorios/2026-11-12-testes-manuais-web/RELATORIO.md):
--
--   W-2  Um pedido criado pela app sem morada (o geocoding falhou e a
--        cliente não escreveu nada) já não entra: "Editar pedido" exigia-a
--        e falhava depois. A app também passa a pedi-la no passo 2.
--   W-7  Painel admin: "+N no período" deixa de contar contas eliminadas,
--        como o total ao lado (que já as tirava).
--
-- Nenhuma assinatura muda (CREATE OR REPLACE chega). Pode correr duas vezes.

-- ── W-2 ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.job_request_track_visibility()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- 0074: um pedido criado pela app nasce sem nada da execução nem dos
    -- lembretes, e com data fixa nunca no passado. As funções do servidor
    -- (cancel_job ao reabrir) correm como dono e não passam por aqui.
    IF current_user IN ('authenticated', 'anon') THEN
      IF NEW.date_mode = 'fixed' AND NEW.preferred_date < today_pt() THEN
        RAISE EXCEPTION 'A data do pedido já passou. Escolhe outra data.';
      END IF;
      -- 0075 (W-2): sem morada o pedido não se pode editar depois
      -- (update_job_request exige-a) e o jardineiro não sabe a zona.
      IF btrim(COALESCE(NEW.address_text, '')) = '' THEN
        RAISE EXCEPTION 'Indica a morada.';
      END IF;
      NEW.started_at                    := NULL;
      NEW.marked_done_at                := NULL;
      NEW.completion_photo_path         := NULL;
      NEW.before_photo_paths            := '{}';
      NEW.after_photo_paths             := '{}';
      NEW.day_reminder_sent_on          := NULL;
      NEW.overdue_notified_at           := NULL;
      NEW.confirmation_reminder_sent_at := NULL;
      NEW.start_reminder_for            := NULL;
      NEW.late_start_reminder_for       := NULL;
      NEW.undated_expiry_warned_at      := NULL;
    END IF;
    NEW.search_extra_km        := 0;
    NEW.followup_stage         := 0;
    NEW.no_proposals_nudged_at := NULL;
    NEW.visible_to_all_at :=
      CASE WHEN COALESCE(NEW.direct_status, '') IN ('waiting', 'on_hold')
           THEN NULL ELSE now() END;
    RETURN NEW;
  END IF;

  -- A app (cliente com sessão) não mexe nestes campos: só as RPCs e o cron.
  IF current_setting('request.jwt.claim.sub', true) IS NOT NULL
     AND current_user IN ('authenticated', 'anon')
     AND (NEW.search_extra_km        IS DISTINCT FROM OLD.search_extra_km
       OR NEW.followup_stage         IS DISTINCT FROM OLD.followup_stage
       OR NEW.no_proposals_nudged_at IS DISTINCT FROM OLD.no_proposals_nudged_at
       OR NEW.visible_to_all_at      IS DISTINCT FROM OLD.visible_to_all_at)
  THEN
    RAISE EXCEPTION 'Estes dados do pedido não se podem alterar.';
  END IF;

  -- Fim da reserva do pedido direto: o relógio dos lembretes começa agora.
  IF COALESCE(OLD.direct_status, '') IN ('waiting', 'on_hold')
     AND COALESCE(NEW.direct_status, '') NOT IN ('waiting', 'on_hold')
  THEN
    NEW.visible_to_all_at := now();
  END IF;
  RETURN NEW;
END;
$function$;

-- ── W-7 ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_overview(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_since  timestamptz;
  v_result jsonb;
BEGIN
  PERFORM public.assert_verified_admin();
  v_since := CASE WHEN p_days IS NULL THEN '-infinity'::timestamptz
                  ELSE now() - make_interval(days => GREATEST(p_days, 1)) END;

  WITH jobs AS (
    SELECT jr.*,
           (SELECT min(jp.created_at) FROM job_proposals jp
            WHERE jp.job_id = jr.id) AS first_proposal_at
    FROM   job_requests jr
    WHERE  jr.created_at >= v_since
  )
  SELECT jsonb_build_object(
    'clients_total',   (SELECT count(*) FROM profiles
                        WHERE role = 'client' AND deleted_at IS NULL),
    'workers_total',   (SELECT count(*) FROM profiles
                        WHERE role = 'worker' AND deleted_at IS NULL),
    'clients_new',     (SELECT count(*) FROM profiles
                        WHERE role = 'client' AND created_at >= v_since
                          AND deleted_at IS NULL),
    'workers_new',     (SELECT count(*) FROM profiles
                        WHERE role = 'worker' AND created_at >= v_since
                          AND deleted_at IS NULL),
    'jobs_published',  (SELECT count(*) FROM jobs),
    'jobs_with_proposal_24h',
                       (SELECT count(*) FROM jobs
                        WHERE first_proposal_at <= created_at + interval '24 hours'),
    'avg_hours_to_first_proposal',
                       (SELECT round((avg(extract(epoch FROM first_proposal_at - created_at))
                                      / 3600)::numeric, 1)
                        FROM jobs WHERE first_proposal_at IS NOT NULL),
    'jobs_accepted',   (SELECT count(*) FROM jobs
                        WHERE status IN ('confirmed', 'awaiting_confirmation', 'completed')),
    'jobs_completed',  (SELECT count(*) FROM jobs WHERE status = 'completed'),
    'jobs_cancelled',  (SELECT count(*) FROM jobs WHERE status = 'cancelled'),
    'jobs_no_response',(SELECT count(*) FROM jobs WHERE status = 'no_response'),
    'avg_rating',      (SELECT round(avg(r.stars)::numeric, 2)
                        FROM ratings r
                        JOIN profiles p ON p.id = r.ratee_id AND p.role = 'worker'
                        WHERE r.created_at >= v_since),
    'ratings_count',   (SELECT count(*)
                        FROM ratings r
                        JOIN profiles p ON p.id = r.ratee_id AND p.role = 'worker'
                        WHERE r.created_at >= v_since),
    'workers_pro',     (SELECT count(*) FROM profiles p
                        WHERE p.role = 'worker' AND p.deleted_at IS NULL
                          AND public.worker_active_tier(p.id) = 'pro'),
    'workers_pro_plus',(SELECT count(*) FROM profiles p
                        WHERE p.role = 'worker' AND p.deleted_at IS NULL
                          AND public.worker_active_tier(p.id) = 'pro_plus'),
    'alert_open_without_proposals_12h',
                       (SELECT count(*) FROM job_requests
                        WHERE status = 'open' AND proposal_count = 0
                          AND created_at < now() - interval '12 hours'),
    'alert_reports_7d',(SELECT count(*) FROM job_reports
                        WHERE created_at >= now() - interval '7 days'),
    'alert_fleet_cards_pending',
                       (SELECT count(*) FROM worker_fleet_cards WHERE status = 'pending'),
    'alert_plans_ending_7d',
                       (SELECT count(*) FROM worker_plans
                        WHERE tier <> 'free' AND ends_at IS NOT NULL
                          AND ends_at BETWEEN CURRENT_DATE AND CURRENT_DATE + 7)
  ) INTO v_result;

  RETURN v_result;
END;
$function$;
