-- 0074_audit_fixes.sql
-- NOVA, NÃO APLICADA. Aplicar no SQL Editor depois da 0073 (ordem: 0067 a 0074).
--
-- Correções da auditoria sistemática de 12/11/2026
-- (docs/systematic-debugging-audit/04-BUG-REPORT.md). Nenhuma RPC muda de
-- assinatura nem de forma de retorno, por isso não há DROP FUNCTION.
--
--  BUG-001  withdraw_proposal bloqueia o pedido e a proposta (corrida com accept_proposal).
--  BUG-002  INSERT de job_requests pela app não traz campos de execução nem de lembretes.
--  BUG-003  INSERT de job_requests pela app recusa data fixa no passado.
--  BUG-004  get_jobs_in_radius e get_help_requests_in_radius usam a base e o raio
--           gravados do jardineiro e só respondem a contas de jardineiro.
--  BUG-005  job_photos_before_insert bloqueia o pedido antes de contar as fotos.
--  BUG-006  worker_profiles.radius_km entre 1 e 50; avisos nunca além de 50 km.
--  BUG-007  propostas com mínimo maior do que o máximo (horas ou dias) recusadas.
--  BUG-008  limites de tamanho nos textos escritos diretamente pela app.
--  BUG-009  avaliações deixam de ser legíveis sem sessão.
--  BUG-012  avaliar duas vezes dá erro em vez de ser ignorado em silêncio.
--
-- Pode correr duas vezes sem erro.

-------------------------------------------------------------------------------
-- BUG-001: withdraw_proposal
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.withdraw_proposal(p_proposal_id uuid, p_job_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_client_id uuid;
BEGIN
  -- Mesma ordem de bloqueio do accept_proposal (pedido, depois proposta):
  -- se a cliente estiver a aceitar ao mesmo tempo, espera-se por ela e
  -- volta-se a ver o estado já atualizado.
  SELECT client_id INTO v_client_id
  FROM   job_requests WHERE id = p_job_id
  FOR UPDATE;

  PERFORM 1 FROM job_proposals
  WHERE  id        = p_proposal_id
    AND  job_id    = p_job_id
    AND  worker_id = auth.uid()
    AND  status    = 'pending'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou não pode ser retirada.';
  END IF;

  UPDATE job_proposals
  SET status = 'superseded', updated_at = now()
  WHERE id = p_proposal_id AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Proposta não encontrada ou não pode ser retirada.';
  END IF;

  UPDATE job_requests
  SET proposal_count = GREATEST(proposal_count - 1, 0),
      updated_at     = now()
  WHERE id = p_job_id;

  INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
  VALUES (
    v_client_id,
    'proposal_withdrawn',
    'Proposta retirada',
    'Um jardineiro retirou a sua proposta.',
    p_job_id,
    'job_request'
  );
END;
$function$;

-------------------------------------------------------------------------------
-- BUG-004, BUG-006, BUG-005, BUG-002/003, BUG-012: funções reescritas a
-- partir da versão atual (0059 a 0073), só com as linhas marcadas "0074".
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_jobs_in_radius(worker_lat numeric, worker_lng numeric, radius_km integer)
 RETURNS SETOF job_requests
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 0074: o centro e o raio vêm do perfil gravado, nunca dos parâmetros
  -- (a app já manda a base e o raio do perfil; os parâmetros ficam só para
  -- não mudar a assinatura). Só contas de jardineiro têm linha aqui.
  WITH box AS (
    SELECT LEAST(GREATEST(wp.radius_km, 1), 50)::double precision AS r,
           LEAST(GREATEST(wp.radius_km, 1), 50)::double precision + 31 AS rb,
           wp.base_lat::double precision AS lat,
           wp.base_lng::double precision AS lng
    FROM   public.worker_profiles wp
    JOIN   public.profiles pr ON pr.id = wp.profile_id
                             AND pr.role = 'worker' AND pr.deleted_at IS NULL
    WHERE  wp.profile_id = auth.uid()
  )
  SELECT mask_job_location(jr)
  FROM   box b
  JOIN   public.job_requests jr
    ON   jr.status = 'open'
   AND   (
           (jr.location_lat BETWEEN b.lat - b.rb / 111.0 AND b.lat + b.rb / 111.0
            AND jr.location_lng BETWEEN b.lng - b.rb / (111.0 * GREATEST(cos(radians(b.lat)), 0.01))
                                    AND b.lng + b.rb / (111.0 * GREATEST(cos(radians(b.lat)), 0.01)))
           OR (jr.direct_status IN ('waiting', 'on_hold') AND jr.direct_worker_id = auth.uid())
         )
  CROSS JOIN LATERAL (
    SELECT 2 * 6371 * asin(LEAST(1, sqrt(
      power(sin(radians((round(jr.location_lat::numeric, 2)::double precision - b.lat) / 2)), 2)
      + cos(radians(b.lat))
        * cos(radians(round(jr.location_lat::numeric, 2)::double precision))
        * power(sin(radians((round(jr.location_lng::numeric, 2)::double precision - b.lng) / 2)), 2)
    ))) AS distance_km
  ) d
  CROSS JOIN LATERAL (
    SELECT jr.direct_worker_id = auth.uid()
           AND (
             (jr.direct_status = 'waiting'
               AND (jr.direct_until > now() OR NOT jr.direct_auto_release))
             OR (jr.direct_status = 'on_hold' AND jr.direct_hold_reason = 'expired')
           ) AS for_me
  ) dr
  WHERE  auth.uid() IS NOT NULL
    AND  NOT (auth.uid() = ANY(jr.excluded_worker_ids))
    AND  jr.client_id <> auth.uid()
    AND  NOT (jr.date_mode = 'fixed' AND jr.preferred_date < today_pt())
    AND  NOT job_reserved_for_other(jr.direct_status, jr.direct_until,
                                    jr.direct_worker_id, auth.uid(),
                                    jr.direct_auto_release)
    AND  NOT EXISTS (
      SELECT 1 FROM public.job_proposals jp
      WHERE  jp.job_id = jr.id AND jp.worker_id = auth.uid() AND jp.status = 'pending'
    )
    AND  (d.distance_km <= b.r + jr.search_extra_km OR COALESCE(dr.for_me, false))
  ORDER BY COALESCE(dr.for_me, false) DESC, d.distance_km ASC;
$function$;

CREATE OR REPLACE FUNCTION public.get_help_requests_in_radius(worker_lat double precision, worker_lng double precision, radius_km integer)
 RETURNS TABLE(id uuid, job_id uuid, proposal_id uuid, slots_needed integer, status text, equipment_required boolean, created_post_confirmation boolean, created_at timestamp with time zone, location_lat double precision, location_lng double precision, service_type_id uuid, principal_name text, principal_avatar_url text, payment_per_helper numeric, confirmed_date date, confirmed_time time without time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- 0074: centro e raio do perfil gravado do jardineiro, não dos parâmetros.
  WITH me AS (
    SELECT wp.base_lat::double precision AS lat,
           wp.base_lng::double precision AS lng,
           wp.radius_km                  AS rk
    FROM   public.worker_profiles wp
    JOIN   public.profiles pr ON pr.id = wp.profile_id
                             AND pr.role = 'worker' AND pr.deleted_at IS NULL
    WHERE  wp.profile_id = auth.uid()
  )
  SELECT id, job_id, proposal_id, slots_needed, status, equipment_required,
         created_post_confirmation, created_at,
         round(location_lat::numeric, 2)::double precision,
         round(location_lng::numeric, 2)::double precision,
         service_type_id, principal_name, principal_avatar_url,
         payment_per_helper, confirmed_date, confirmed_time
  FROM (
    SELECT
      hr.id, hr.job_id, hr.proposal_id, hr.slots_needed, hr.status,
      hr.equipment_required, hr.created_post_confirmation, hr.created_at,
      round(jr.location_lat::numeric, 2)::double precision AS location_lat,
      round(jr.location_lng::numeric, 2)::double precision AS location_lng,
      jr.service_type_id, p.full_name AS principal_name,
      p.avatar_url AS principal_avatar_url,
      CASE WHEN hr.equipment_required THEN jp.hourly_rate
           ELSE jp.hourly_rate * 0.7
      END AS payment_per_helper,
      jr.confirmed_date, jr.confirmed_time,
      2 * 6371 * asin(LEAST(1, sqrt(
        power(sin(radians((round(jr.location_lat::numeric, 2)::double precision - me.lat) / 2)), 2)
        + cos(radians(me.lat))
          * cos(radians(round(jr.location_lat::numeric, 2)::double precision))
          * power(sin(radians((round(jr.location_lng::numeric, 2)::double precision - me.lng) / 2)), 2)
      ))) AS distance_km,
      LEAST(GREATEST(me.rk, 1), 50)::double precision AS r
    FROM   help_requests  hr
    JOIN   job_requests   jr ON jr.id = hr.job_id
    JOIN   job_proposals  jp ON jp.id = hr.proposal_id
    JOIN   profiles        p ON p.id  = jp.worker_id
    CROSS JOIN me
    WHERE  hr.status = 'open'
      AND  jr.status = 'confirmed'
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
      AND  jr.started_at IS NULL
      AND  jr.location_lat BETWEEN me.lat - 51 / 111.0 AND me.lat + 51 / 111.0
      AND  jp.worker_id <> auth.uid()
      AND  EXISTS (SELECT 1 FROM worker_profiles wp WHERE wp.profile_id = auth.uid())
      AND  NOT EXISTS (
        SELECT 1 FROM help_acceptances ha
        WHERE ha.help_request_id = hr.id
          AND ha.worker_id = auth.uid()
          AND ha.status IN ('pending', 'accepted')
      )
  ) t
  WHERE t.distance_km <= t.r
  ORDER BY t.distance_km ASC;
$function$;

CREATE OR REPLACE FUNCTION public.job_candidate_workers(p_job job_requests)
 RETURNS TABLE(worker_id uuid, distance_km double precision, radius_km integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT wp.profile_id,
         km_between(wp.base_lat, wp.base_lng, p_job.location_lat, p_job.location_lng),
         -- 0074: nunca mais de 50 km, como a pesquisa (o CHECK novo já o garante).
         LEAST(GREATEST(wp.radius_km, 1), 50)
  FROM   worker_profiles wp
  JOIN   profiles p ON p.id = wp.profile_id AND p.deleted_at IS NULL
  WHERE  wp.profile_id <> p_job.client_id
    AND  NOT (wp.profile_id = ANY(COALESCE(p_job.excluded_worker_ids, '{}'::uuid[])))
    AND  (
           EXISTS (SELECT 1 FROM worker_service_types wst
                   WHERE wst.worker_id = wp.profile_id
                     AND wst.service_type_id = p_job.service_type_id)
           OR NOT EXISTS (SELECT 1 FROM worker_service_types wst
                          WHERE wst.worker_id = wp.profile_id)
         )
    AND  NOT EXISTS (SELECT 1 FROM job_proposals jp
                     WHERE jp.job_id = p_job.id AND jp.worker_id = wp.profile_id);
$function$;

CREATE OR REPLACE FUNCTION public.job_photos_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_client uuid;
  v_status text;
BEGIN
  -- 0074: um envio de cada vez por pedido, para a contagem do máximo de 2
  -- fotos não falhar com dois envios ao mesmo tempo. Advisory lock porque a
  -- cliente não tem permissão de UPDATE no pedido (FOR UPDATE não veria a linha).
  PERFORM pg_advisory_xact_lock(hashtextextended('job_photos:' || NEW.job_id::text, 0));

  SELECT client_id, status INTO v_client, v_status
  FROM   job_requests WHERE id = NEW.job_id;

  IF v_status IS DISTINCT FROM 'open' THEN
    RAISE EXCEPTION 'Só podes juntar fotos a um pedido aberto.';
  END IF;
  -- Ficheiros do próprio cliente (o cancel_job copia as linhas do pedido
  -- original, que estão na mesma pasta).
  IF NEW.storage_path IS NULL
     OR NEW.storage_path NOT LIKE v_client::text || '/%' THEN
    RAISE EXCEPTION 'Foto inválida.';
  END IF;
  IF (SELECT count(*) FROM job_photos WHERE job_id = NEW.job_id) >= 2 THEN
    RAISE EXCEPTION 'Cada pedido pode ter no máximo 2 fotos.';
  END IF;
  RETURN NEW;
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.submit_client_rating(p_job_id uuid, p_stars integer, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF v_job.client_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado: só o cliente pode submeter esta avaliação.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Proposta aceite não encontrada.';
  END IF;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;

  -- 0074: avisar em vez de ignorar em silêncio.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Já avaliaste esta pessoa neste trabalho.';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_helper_rating(p_job_id uuid, p_stars integer, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_is_helper boolean;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM   help_requests    hr
    JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                              AND ha.status = 'accepted'
                              AND ha.worker_id = auth.uid()
    WHERE  hr.proposal_id = v_job.accepted_proposal_id
  ) INTO v_is_helper;

  IF NOT v_is_helper THEN
    RAISE EXCEPTION 'Não autorizado: só ajudantes aceites podem submeter esta avaliação.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), v_principal, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;

  -- 0074: avisar em vez de ignorar em silêncio.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Já avaliaste esta pessoa neste trabalho.';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_principal_rating(p_job_id uuid, p_ratee_id uuid, p_stars integer, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_job       job_requests%ROWTYPE;
  v_principal uuid;
  v_valid     boolean := false;
BEGIN
  SELECT * INTO v_job FROM job_requests WHERE id = p_job_id FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.';
  END IF;
  IF v_job.status <> 'completed' THEN
    RAISE EXCEPTION 'Só é possível avaliar trabalhos concluídos.';
  END IF;
  IF p_stars < 1 OR p_stars > 5 THEN
    RAISE EXCEPTION 'Avaliação inválida: entre 1 e 5 estrelas.';
  END IF;

  SELECT jp.worker_id INTO v_principal
  FROM   job_proposals jp WHERE jp.id = v_job.accepted_proposal_id;

  IF v_principal IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Não autorizado: só o prestador principal pode submeter esta avaliação.';
  END IF;

  IF p_ratee_id = v_job.client_id THEN v_valid := true; END IF;

  IF NOT v_valid THEN
    SELECT EXISTS (
      SELECT 1
      FROM   help_requests    hr
      JOIN   help_acceptances ha ON ha.help_request_id = hr.id
                                AND ha.status = 'accepted'
                                AND ha.worker_id = p_ratee_id
      WHERE  hr.proposal_id = v_job.accepted_proposal_id
    ) INTO v_valid;
  END IF;

  IF NOT v_valid THEN
    RAISE EXCEPTION 'Não autorizado: o utilizador avaliado não é participante deste trabalho.';
  END IF;

  INSERT INTO ratings (job_id, rater_id, ratee_id, stars, comment)
  VALUES (p_job_id, auth.uid(), p_ratee_id, p_stars, p_comment)
  ON CONFLICT (job_id, rater_id, ratee_id) DO NOTHING;

  -- 0074: avisar em vez de ignorar em silêncio.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Já avaliaste esta pessoa neste trabalho.';
  END IF;
END;
$function$;
-------------------------------------------------------------------------------
-- BUG-006: raio entre 1 e 50 km (o slider da app já é 1 a 50)
-------------------------------------------------------------------------------
UPDATE worker_profiles
SET    radius_km = LEAST(GREATEST(radius_km, 1), 50)
WHERE  radius_km < 1 OR radius_km > 50;

ALTER TABLE worker_profiles DROP CONSTRAINT IF EXISTS worker_profiles_radius_km_range;
ALTER TABLE worker_profiles
  ADD CONSTRAINT worker_profiles_radius_km_range CHECK (radius_km BETWEEN 1 AND 50);

-------------------------------------------------------------------------------
-- BUG-007: mínimo nunca maior do que o máximo
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.job_proposal_validate_ranges()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.estimated_hours_min IS NOT NULL AND NEW.estimated_hours_max IS NOT NULL
     AND NEW.estimated_hours_min > NEW.estimated_hours_max THEN
    RAISE EXCEPTION 'A duração mínima não pode ser maior do que a máxima.';
  END IF;
  IF NEW.estimated_days_min IS NOT NULL AND NEW.estimated_days_max IS NOT NULL
     AND NEW.estimated_days_min > NEW.estimated_days_max THEN
    RAISE EXCEPTION 'O número mínimo de dias não pode ser maior do que o máximo.';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.job_proposal_validate_ranges() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_job_proposal_validate_ranges ON job_proposals;
CREATE TRIGGER trg_job_proposal_validate_ranges
  BEFORE INSERT ON job_proposals
  FOR EACH ROW EXECUTE FUNCTION public.job_proposal_validate_ranges();

-------------------------------------------------------------------------------
-- BUG-008: limites de tamanho (folgados: a app nunca chega lá). NOT VALID
-- para não falhar por causa de linhas antigas; vale para tudo o que for
-- escrito a partir de agora.
-------------------------------------------------------------------------------
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_full_name_length;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_full_name_length CHECK (char_length(full_name) <= 120) NOT VALID;
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_phone_length;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_phone_length CHECK (char_length(phone) <= 30) NOT VALID;
ALTER TABLE worker_profiles DROP CONSTRAINT IF EXISTS worker_profiles_bio_length;
ALTER TABLE worker_profiles
  ADD CONSTRAINT worker_profiles_bio_length CHECK (char_length(bio) <= 2000) NOT VALID;
ALTER TABLE job_reports DROP CONSTRAINT IF EXISTS job_reports_description_length;
ALTER TABLE job_reports
  ADD CONSTRAINT job_reports_description_length CHECK (char_length(description) <= 4000) NOT VALID;
ALTER TABLE ratings DROP CONSTRAINT IF EXISTS ratings_comment_length;
ALTER TABLE ratings
  ADD CONSTRAINT ratings_comment_length CHECK (char_length(comment) <= 1000) NOT VALID;

-------------------------------------------------------------------------------
-- BUG-009: avaliações só com sessão. O cartão público continua a mostrar a
-- média e a última avaliação pela view worker_public_card (não depende disto).
-------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Leitura pública de avaliações" ON ratings;
DROP POLICY IF EXISTS "Avaliações visíveis com sessão" ON ratings;
CREATE POLICY "Avaliações visíveis com sessão"
  ON ratings FOR SELECT TO authenticated
  USING (true);
