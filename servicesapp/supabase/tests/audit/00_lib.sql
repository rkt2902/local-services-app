-- Auditoria 2026-11-12: pequenas funções de asserção para os cenários da BD.
-- Só para a BD local de teste (montada por build.sh). Nunca correr na BD viva.
--
-- Cada asserção grava uma linha em audit.results (id, ok, detalhe). Quando a
-- instrução testada devia falhar e passa, os efeitos são desfeitos (exceção
-- interna), para não contaminar os testes seguintes.

create schema if not exists audit;
grant usage on schema audit to authenticated, anon;

create table if not exists audit.results(
  seq bigserial primary key,
  id text not null,
  ok boolean not null,
  detail text
);
grant insert, select on audit.results to authenticated, anon;
grant usage on sequence audit.results_seq_seq to authenticated, anon;

-- A instrução tem de correr sem erro.
create or replace function audit.ok(p_id text, p_sql text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    insert into audit.results(id, ok, detail) values (p_id, false, 'erro inesperado: ' || sqlerrm);
    return;
  end;
  insert into audit.results(id, ok, detail) values (p_id, true, null);
end $$;

-- A instrução tem de falhar (e, se p_pat vier, a mensagem tem de conter p_pat).
create or replace function audit.err(p_id text, p_sql text, p_pat text default null) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
    raise exception 'AUDIT_NO_ERROR';
  exception when others then
    if sqlerrm = 'AUDIT_NO_ERROR' then
      insert into audit.results(id, ok, detail) values (p_id, false, 'devia ter falhado e passou');
    elsif p_pat is null or sqlerrm ilike '%' || p_pat || '%' then
      insert into audit.results(id, ok, detail) values (p_id, true, 'recusado: ' || sqlerrm);
    else
      insert into audit.results(id, ok, detail) values (p_id, false, 'erro diferente do esperado: ' || sqlerrm);
    end if;
  end;
end $$;

-- A consulta devolve um valor; compara como texto.
create or replace function audit.eq(p_id text, p_sql text, p_expected text) returns void
language plpgsql as $$
declare v text;
begin
  begin
    execute p_sql into v;
  exception when others then
    insert into audit.results(id, ok, detail) values (p_id, false, 'erro inesperado: ' || sqlerrm);
    return;
  end;
  insert into audit.results(id, ok, detail)
  values (p_id, v is not distinct from p_expected,
          'esperado=' || coalesce(p_expected, 'NULL') || ' obtido=' || coalesce(v, 'NULL'));
end $$;

-- Corre e devolve o valor (para guardar com \gset); grava falha se der erro.
create or replace function audit.val(p_id text, p_sql text) returns text
language plpgsql as $$
declare v text;
begin
  begin
    execute p_sql into v;
  exception when others then
    insert into audit.results(id, ok, detail) values (p_id, false, 'erro inesperado: ' || sqlerrm);
    return null;
  end;
  insert into audit.results(id, ok, detail) values (p_id, v is not null, 'valor=' || coalesce(v, 'NULL'));
  return v;
end $$;

grant execute on all functions in schema audit to authenticated, anon;

-- Identidade do pedido (o que o PostgREST põe em request.jwt.claim.*).
create or replace function public.t_as(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false),
         set_config('request.jwt.claims', json_build_object('sub', u, 'aal', 'aal1')::text, false)
$$;
create or replace function public.t_aal2(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u, false),
         set_config('request.jwt.claims', json_build_object('sub', u, 'aal', 'aal2')::text, false)
$$;
grant execute on function public.t_as(text), public.t_aal2(text) to authenticated, anon;
