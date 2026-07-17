-- Painel admin do /diagnostico do batista.growth: leitura via RPC com senha (bcrypt)
create extension if not exists pgcrypto;

create table if not exists public.batista_diagnostico_admin (
  id int primary key default 1 check (id = 1),
  senha_hash text not null
);
alter table public.batista_diagnostico_admin enable row level security;
-- nenhuma policy: nem anon nem authenticated leem/escrevem; só as functions (security definer)

create or replace function public.batista_diagnostico_admin_ok(p_senha text)
returns boolean language sql security definer set search_path = public, extensions as $$
  select exists(
    select 1 from public.batista_diagnostico_admin
    where id = 1 and senha_hash = crypt(p_senha, senha_hash)
  );
$$;

create or replace function public.batista_diagnostico_admin_leads(p_senha text, p_dias int default 30)
returns json language sql security definer set search_path = public, extensions as $$
  select case when not public.batista_diagnostico_admin_ok(p_senha) then null else (
    select coalesce(json_agg(l order by l.created_at desc), '[]'::json)
    from (
      select id, created_at, nome, whatsapp, perfil, faturamento, gargalo, tentou, urgencia, incompleto, passo
      from public.batista_diagnostico_leads
      where p_dias <= 0 or created_at > now() - (p_dias || ' days')::interval
      limit 500
    ) l
  ) end;
$$;

create or replace function public.batista_diagnostico_admin_metricas(p_senha text, p_dias int default 30)
returns json language sql security definer set search_path = public, extensions as $$
  select case when not public.batista_diagnostico_admin_ok(p_senha) then null else (
    select json_build_object(
      'visitas',      (select count(distinct session_id) from public.batista_diagnostico_events e where e.event = 'view'      and (p_dias <= 0 or e.created_at > now() - (p_dias || ' days')::interval)),
      'leads',        (select count(*) from public.batista_diagnostico_leads l where not l.incompleto and (p_dias <= 0 or l.created_at > now() - (p_dias || ' days')::interval)),
      'incompletos',  (select count(*) from public.batista_diagnostico_leads l where l.incompleto     and (p_dias <= 0 or l.created_at > now() - (p_dias || ' days')::interval)),
      'whats_clicks', (select count(distinct session_id) from public.batista_diagnostico_events e where e.event = 'whats_click' and (p_dias <= 0 or e.created_at > now() - (p_dias || ' days')::interval)),
      'funil',        (select coalesce(json_agg(f), '[]'::json) from (
                        select step, count(distinct session_id) as n
                        from public.batista_diagnostico_events e
                        where e.event = 'step' and (p_dias <= 0 or e.created_at > now() - (p_dias || ' days')::interval)
                        group by step order by n desc
                      ) f)
    )
  ) end;
$$;

create or replace function public.batista_diagnostico_admin_troca_senha(p_atual text, p_nova text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.batista_diagnostico_admin_ok(p_atual) then return false; end if;
  update public.batista_diagnostico_admin set senha_hash = crypt(p_nova, gen_salt('bf')) where id = 1;
  return true;
end;
$$;

grant execute on function public.batista_diagnostico_admin_ok, public.batista_diagnostico_admin_leads,
  public.batista_diagnostico_admin_metricas, public.batista_diagnostico_admin_troca_senha to anon;
