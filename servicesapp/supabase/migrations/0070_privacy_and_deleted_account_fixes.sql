-- ══════════════════════════════════════════════════════════════
-- 0070 · Privacidade da morada e contas eliminadas (revisão, parte 3)
-- NOVA, NÃO APLICADA. Aplicar depois da 0068 e da 0069.
-- ══════════════════════════════════════════════════════════════
-- 1. get_jobs_in_radius / get_help_requests_in_radius: a distância passa
--    a ser medida à coordenada arredondada do pedido (a mesma que a app
--    mostra, ~1 km). Antes media à exata e, mudando o centro, dava para
--    chegar à morada exata em ~160 chamadas. A caixa de pré-filtro sobe
--    1 km para nunca ser ela a decidir.
-- 2. get_my_previous_workers esconde jardineiros com a conta eliminada;
--    get_repeat_hire_for_job devolve can_request = false para eles.
-- 3. delete_my_account liberta os pedidos diretos à espera do jardineiro.
-- 4. job_day_reached passa a ser true também com o trabalho iniciado:
--    trabalhos "a combinar" (sem data) fecham o pedido de ajudantes ao
--    começar, como os outros no dia. O cron que fecha os pedidos de ajuda
--    e a pesquisa de pedidos de ajuda seguem a mesma regra.
-- 5. log_worker_card_visit: no máximo 200 visitas por jardineiro por hora.
--    profiles: id, created_at e deleted_at só mudam pelo servidor.
-- ══════════════════════════════════════════════════════════════


-- ── 1. Pesquisas por raio ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_jobs_in_radius(worker_lat numeric, worker_lng numeric, radius_km integer)
 RETURNS SETOF job_requests
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH box AS (
    SELECT LEAST(GREATEST(radius_km, 1), 50)::double precision AS r,
           LEAST(GREATEST(radius_km, 1), 50)::double precision + 31 AS rb,
           worker_lat::double precision AS lat,
           worker_lng::double precision AS lng
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

REVOKE EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_jobs_in_radius(numeric, numeric, integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_help_requests_in_radius(worker_lat double precision, worker_lng double precision, radius_km integer)
 RETURNS TABLE(id uuid, job_id uuid, proposal_id uuid, slots_needed integer, status text, equipment_required boolean, created_post_confirmation boolean, created_at timestamp with time zone, location_lat double precision, location_lng double precision, service_type_id uuid, principal_name text, principal_avatar_url text, payment_per_helper numeric, confirmed_date date, confirmed_time time without time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        power(sin(radians((round(jr.location_lat::numeric, 2)::double precision - worker_lat) / 2)), 2)
        + cos(radians(worker_lat))
          * cos(radians(round(jr.location_lat::numeric, 2)::double precision))
          * power(sin(radians((round(jr.location_lng::numeric, 2)::double precision - worker_lng) / 2)), 2)
      ))) AS distance_km,
      LEAST(GREATEST(radius_km, 1), 50)::double precision AS r
    FROM   help_requests  hr
    JOIN   job_requests   jr ON jr.id = hr.job_id
    JOIN   job_proposals  jp ON jp.id = hr.proposal_id
    JOIN   profiles        p ON p.id  = jp.worker_id
    WHERE  hr.status = 'open'
      AND  jr.status = 'confirmed'
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
      AND  jr.started_at IS NULL
      AND  jr.location_lat BETWEEN worker_lat - 51 / 111.0 AND worker_lat + 51 / 111.0
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

REVOKE EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_help_requests_in_radius(double precision, double precision, integer) TO authenticated, service_role;


-- ── 2. Jardineiros com a conta eliminada ───────────────────────
CREATE OR REPLACE FUNCTION public.get_my_previous_workers()
 RETURNS TABLE(worker_id uuid, worker_name text, worker_avatar_url text, last_job_id uuid, service_type_id uuid, job_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT w.worker_id, p.full_name, p.avatar_url, w.job_id, w.service_type_id, w.job_date
  FROM (
    SELECT DISTINCT ON (jp.worker_id)
           jp.worker_id,
           jr.id AS job_id,
           jr.service_type_id,
           COALESCE(jr.confirmed_date, jr.updated_at::date) AS job_date
    FROM   job_requests  jr
    JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
    WHERE  jr.client_id = auth.uid()
      AND  jr.status    = 'completed'
    ORDER BY jp.worker_id, COALESCE(jr.confirmed_date, jr.updated_at::date) DESC, jr.updated_at DESC
  ) w
  JOIN   profiles        p  ON p.id = w.worker_id
  JOIN   worker_profiles wp ON wp.profile_id = w.worker_id
  WHERE  p.deleted_at IS NULL
    AND  NOT EXISTS (
    SELECT 1 FROM ratings r
    WHERE  r.job_id = w.job_id AND r.rater_id = auth.uid()
      AND  r.ratee_id = w.worker_id AND r.stars < 4
  )
  ORDER BY w.job_date DESC
  LIMIT 10;
$function$;

CREATE OR REPLACE FUNCTION public.get_repeat_hire_for_job(p_job_id uuid)
 RETURNS TABLE(worker_id uuid, worker_name text, worker_avatar_url text, service_type_id uuid, job_date date, can_request boolean, my_stars integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jp.worker_id,
         p.full_name,
         p.avatar_url,
         jr.service_type_id,
         COALESCE(jr.confirmed_date, jr.updated_at::date),
         worker_can_receive_direct_requests(jp.worker_id),
         (SELECT r.stars FROM ratings r
          WHERE  r.job_id = jr.id AND r.rater_id = auth.uid() AND r.ratee_id = jp.worker_id)
  FROM   job_requests  jr
  JOIN   job_proposals jp ON jp.id = jr.accepted_proposal_id
  LEFT JOIN profiles   p  ON p.id  = jp.worker_id
  WHERE  jr.id        = p_job_id
    AND  jr.client_id = auth.uid()
    AND  jr.status    = 'completed';
$function$;


-- ── 3. Eliminar conta liberta pedidos diretos ──────────────────
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_email     text;
  v_old_email text;
  v_pwd       text;
  v_blocker   text;
  r           record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;

  PERFORM 1 FROM profiles WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Não autorizado.';
  END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Esta conta já foi eliminada.';
  END IF;

  -- ── Trabalho em curso: recusa ──────────────────────────────────
  v_blocker := account_deletion_blocker(v_uid);
  IF v_blocker IS NOT NULL THEN
    RAISE EXCEPTION '%', v_blocker;
  END IF;

  -- ── Como cliente: cancela os pedidos abertos ───────────────────
  -- O pedido fica cancelled antes de as propostas passarem a rejected,
  -- para o trigger da 0048 avisar cada jardineiro com o texto certo.
  FOR r IN
    SELECT id FROM job_requests
    WHERE  client_id = v_uid AND status = 'open'
    FOR UPDATE
  LOOP
    UPDATE job_requests
    SET    status        = 'cancelled',
           cancelled_by  = v_uid,
           cancel_reason = 'no_longer_needed',
           updated_at    = now()
    WHERE  id = r.id;

    UPDATE job_proposals
    SET    status = 'rejected', updated_at = now()
    WHERE  job_id = r.id AND status = 'pending';
  END LOOP;

  -- ── Como jardineiro: retira as propostas pendentes ─────────────
  -- Mesmo efeito que withdraw_proposal (superseded, contador, aviso).
  FOR r IN
    SELECT jp.id, jp.job_id, jr.client_id, jr.status AS job_status
    FROM   job_proposals jp
    JOIN   job_requests  jr ON jr.id = jp.job_id
    WHERE  jp.worker_id = v_uid AND jp.status = 'pending'
    FOR UPDATE OF jp
  LOOP
    UPDATE job_proposals
    SET    status = 'superseded', updated_at = now()
    WHERE  id = r.id;

    UPDATE job_requests
    SET    proposal_count = GREATEST(proposal_count - 1, 0),
           updated_at     = now()
    WHERE  id = r.job_id;

    IF r.job_status = 'open' THEN
      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (r.client_id, 'proposal_withdrawn', 'Proposta retirada',
        'Um jardineiro retirou a proposta que te tinha feito.',
        r.job_id, 'job_request');
    END IF;
  END LOOP;

  -- ── 0070: pedidos diretos à espera deste jardineiro ────────────
  -- Antes ficavam reservados até 24h a uma conta que já não existe.
  -- Mesmo efeito que "Não posso": mostra a outros ou para e avisa a
  -- cliente, conforme ela escolheu. Corre antes de apagar o nome.
  FOR r IN
    SELECT id FROM job_requests
    WHERE  direct_worker_id = v_uid
      AND  status = 'open'
      AND  direct_status = 'waiting'
    FOR UPDATE
  LOOP
    PERFORM end_direct_reservation(r.id, 'declined');
  END LOOP;

  -- ── Candidaturas a ajudante ainda por decidir ──────────────────
  UPDATE help_acceptances
  SET    status = 'cancelled'
  WHERE  worker_id = v_uid AND status = 'pending';

  -- ── Pedidos de ajuda do próprio ainda por preencher ────────────
  FOR r IN
    SELECT hr.id
    FROM   help_requests hr
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  jp.worker_id = v_uid
      AND  hr.status IN ('pending_approval', 'open')
    FOR UPDATE OF hr
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O jardineiro responsável fechou o pedido de ajuda.',
           r.id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = r.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id = r.id AND status = 'pending';

    UPDATE help_requests SET status = 'cancelled' WHERE id = r.id;
  END LOOP;

  -- ── Dados pessoais (sem DELETE do perfil: há FKs sem cascade) ──
  PERFORM erase_account_data(v_uid);

  -- ── auth: bloqueia o email 90 dias, depois tira-o da conta ─────
  IF to_regclass('auth.users') IS NOT NULL THEN
    EXECUTE 'SELECT email FROM auth.users WHERE id = $1'
      INTO v_old_email USING v_uid;

    IF public.email_block_hash(v_old_email) IS NOT NULL THEN
      INSERT INTO deleted_account_emails (email_hash, deleted_at, blocked_until)
      VALUES (public.email_block_hash(v_old_email), now(), now() + interval '90 days')
      ON CONFLICT (email_hash) DO UPDATE
        SET deleted_at    = EXCLUDED.deleted_at,
            blocked_until = EXCLUDED.blocked_until;
    END IF;
  END IF;

  v_email := 'eliminado+' || v_uid::text || '@invalid.local';

  IF to_regprocedure('extensions.crypt(text,text)') IS NOT NULL
     AND to_regprocedure('extensions.gen_salt(text)') IS NOT NULL THEN
    EXECUTE 'SELECT extensions.crypt($1, extensions.gen_salt(''bf''))'
      INTO v_pwd USING gen_random_uuid()::text;
  ELSIF to_regprocedure('public.crypt(text,text)') IS NOT NULL
     AND to_regprocedure('public.gen_salt(text)') IS NOT NULL THEN
    EXECUTE 'SELECT public.crypt($1, public.gen_salt(''bf''))'
      INTO v_pwd USING gen_random_uuid()::text;
  ELSE
    -- Não é um hash bcrypt válido: nenhuma palavra-passe lhe corresponde.
    v_pwd := 'deleted:' || md5(gen_random_uuid()::text || clock_timestamp()::text);
  END IF;

  IF to_regclass('auth.users') IS NOT NULL THEN
    -- banned_until a 1000 anos em vez de 'infinity': o GoTrue lê esta
    -- coluna para time.Time e um timestamp infinito dá erro ao ler o
    -- utilizador.
    EXECUTE $sql$
      UPDATE auth.users
      SET    email              = $2,
             phone              = NULL,
             raw_user_meta_data = '{}'::jsonb,
             encrypted_password = $3,
             banned_until       = now() + interval '1000 years',
             updated_at         = now()
      WHERE  id = $1
    $sql$ USING v_uid, v_email, v_pwd;

    -- Colunas que só existem em versões do GoTrue: limpa-as se existirem.
    BEGIN
      EXECUTE 'UPDATE auth.users SET email_change = '''', phone_change = '''' WHERE id = $1'
        USING v_uid;
    EXCEPTION WHEN undefined_column THEN
      NULL;
    END;
  END IF;

  -- identities guarda o email (provider_id/identity_data); refresh_tokens
  -- tem user_id em varchar, por isso a comparação é sempre em texto.
  IF to_regclass('auth.identities') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.identities WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.refresh_tokens') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.refresh_tokens WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.sessions') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.sessions WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.mfa_factors') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.mfa_factors WHERE user_id::text = $1' USING v_uid::text;
  END IF;
  IF to_regclass('auth.one_time_tokens') IS NOT NULL THEN
    EXECUTE 'DELETE FROM auth.one_time_tokens WHERE user_id::text = $1' USING v_uid::text;
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.delete_my_account() TO authenticated, service_role;


-- ── 4. Trabalho iniciado conta como "dia do trabalho" ──────────
CREATE OR REPLACE FUNCTION public.job_day_reached(p_job_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT started_at IS NOT NULL OR COALESCE(confirmed_date <= today_pt(), false)
     FROM job_requests WHERE id = p_job_id),
    false
  );
$function$;

CREATE OR REPLACE FUNCTION public.help_request_open_for_candidate(p_help_request_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM   help_requests hr
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    JOIN   job_requests  jr ON jr.id = hr.job_id
    WHERE  hr.id        = p_help_request_id
      AND  hr.status    = 'open'
      AND  jr.status    = 'confirmed'
      AND  (jr.confirmed_date IS NULL OR jr.confirmed_date > today_pt())
      AND  jr.started_at IS NULL
      AND  jp.worker_id <> auth.uid()
      AND  jr.client_id <> auth.uid()
  );
$function$;

CREATE OR REPLACE FUNCTION public.close_help_requests_on_job_day()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hr        RECORD;
  v_accepted  integer;
BEGIN
  FOR v_hr IN
    SELECT hr.id, hr.status, jp.worker_id AS principal_id
    FROM   help_requests hr
    JOIN   job_requests  jr ON jr.id = hr.job_id
    JOIN   job_proposals jp ON jp.id = hr.proposal_id
    WHERE  hr.status IN ('pending_approval', 'open')
      AND  jr.status = 'confirmed'
      AND  (jr.started_at IS NOT NULL
            OR (jr.confirmed_date IS NOT NULL AND jr.confirmed_date <= today_pt()))
    FOR UPDATE OF hr SKIP LOCKED
  LOOP
    INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
    SELECT ha.worker_id, 'help_rejected', 'Candidatura fechada',
           'O dia do trabalho chegou e o pedido de ajuda fechou sem a tua candidatura ser aceite.',
           v_hr.id, 'help_request'
    FROM   help_acceptances ha
    WHERE  ha.help_request_id = v_hr.id AND ha.status = 'pending';

    UPDATE help_acceptances
    SET    status = 'rejected'
    WHERE  help_request_id = v_hr.id AND status = 'pending';

    SELECT count(*) INTO v_accepted
    FROM   help_acceptances
    WHERE  help_request_id = v_hr.id AND status = 'accepted';

    IF v_accepted > 0 THEN
      UPDATE help_requests
      SET    status = 'filled', slots_needed = v_accepted
      WHERE  id = v_hr.id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.principal_id, 'help_request_closed', 'Pedido de ajudantes fechado',
        'O trabalho é hoje, por isso o pedido de ajudantes fechou. A tua equipa fica com '
          || v_accepted
          || CASE WHEN v_accepted = 1 THEN ' ajudante.' ELSE ' ajudantes.' END,
        v_hr.id, 'help_request');
    ELSE
      UPDATE help_requests SET status = 'cancelled' WHERE id = v_hr.id;

      INSERT INTO notifications (user_id, type, title, body, related_id, related_type)
      VALUES (v_hr.principal_id, 'help_request_closed', 'Pedido de ajudantes fechado',
        CASE WHEN v_hr.status = 'pending_approval'
          THEN 'O trabalho é hoje e o cliente não chegou a aprovar os ajudantes. O pedido fechou.'
          ELSE 'O trabalho é hoje e ninguém foi aceite como ajudante. O pedido fechou.'
        END,
        v_hr.id, 'help_request');
    END IF;
  END LOOP;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.close_help_requests_on_job_day() FROM PUBLIC, anon, authenticated;


-- ── 5. Limites de escrita ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.log_worker_card_visit(p_worker_id uuid, p_source text, p_device_key text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_source text := CASE WHEN p_source IN ('qr', 'link', 'app') THEN p_source ELSE 'link' END;
  v_key    text := NULLIF(btrim(p_device_key), '');
  v_id     uuid;
BEGIN
  IF v_key IS NOT NULL AND char_length(v_key) NOT BETWEEN 8 AND 64 THEN
    v_key := NULL;
  END IF;

  IF v_uid IS NOT NULL AND v_uid = p_worker_id THEN
    RETURN NULL;
  END IF;

  IF NOT worker_can_use_public_card(p_worker_id) THEN
    RETURN NULL;
  END IF;

  IF v_key IS NOT NULL THEN
    SELECT id INTO v_id
    FROM   worker_card_visits
    WHERE  worker_id  = p_worker_id
      AND  device_key = v_key
      AND  created_at > now() - interval '30 minutes'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_id IS NOT NULL THEN
      IF v_uid IS NOT NULL THEN
        UPDATE worker_card_visits SET visitor_id = v_uid
        WHERE  id = v_id AND visitor_id IS NULL;
      END IF;
      RETURN v_id;
    END IF;
  END IF;

  -- 0070: chamada sem sessão e sem limite enchia a tabela e os números
  -- do cartão. Acima de 200 visitas na última hora deixa de contar.
  IF (SELECT count(*) FROM worker_card_visits
      WHERE  worker_id = p_worker_id
        AND  created_at > now() - interval '1 hour') >= 200 THEN
    RETURN NULL;
  END IF;

  INSERT INTO worker_card_visits (worker_id, source, device_key, visitor_id)
  VALUES (p_worker_id, v_source, v_key, v_uid)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.log_worker_card_visit(uuid, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.log_worker_card_visit(uuid, text, text) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.prevent_profile_protected_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Só bloqueia pedidos diretos da app; funções do servidor
  -- (erase_account_data, por exemplo) correm como dono e passam.
  IF current_user IN ('authenticated', 'anon')
     AND (NEW.id         IS DISTINCT FROM OLD.id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at)
  THEN
    RAISE EXCEPTION 'Estes dados do perfil não se podem alterar.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tg_prevent_profile_protected_columns ON public.profiles;
CREATE TRIGGER tg_prevent_profile_protected_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_profile_protected_columns();

NOTIFY pgrst, 'reload schema';
