-- Backend do /diagnostico do batista.growth (espelho da infra do diagnóstico MyDose)
create table if not exists public.batista_diagnostico_leads (
  id uuid primary key,
  created_at timestamptz not null default now(),
  nome text,
  whatsapp text,
  perfil text,
  faturamento text,
  gargalo text,
  tentou text,
  urgencia text,
  incompleto boolean not null default false,
  passo text,
  origem text default 'site'
);
alter table public.batista_diagnostico_leads enable row level security;
drop policy if exists "anon_insert_leads" on public.batista_diagnostico_leads;
create policy "anon_insert_leads" on public.batista_diagnostico_leads
  for insert to anon with check (true);

create table if not exists public.batista_diagnostico_events (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  session_id text not null,
  event text not null,
  step text,
  template text default 'v1'
);
alter table public.batista_diagnostico_events enable row level security;
drop policy if exists "anon_insert_events" on public.batista_diagnostico_events;
create policy "anon_insert_events" on public.batista_diagnostico_events
  for insert to anon with check (true);

-- lead parcial vira completo no MESMO id (nao duplica)
create or replace function public.batista_diagnostico_lead_complete(
  p_id uuid, p_nome text, p_whatsapp text, p_perfil text, p_faturamento text,
  p_gargalo text, p_tentou text, p_urgencia text
) returns void
language sql security definer set search_path = public as $$
  update public.batista_diagnostico_leads
     set nome=p_nome, whatsapp=p_whatsapp, perfil=p_perfil, faturamento=p_faturamento,
         gargalo=p_gargalo, tentou=p_tentou, urgencia=p_urgencia,
         incompleto=false, passo='fim'
   where id=p_id;
$$;
grant execute on function public.batista_diagnostico_lead_complete to anon;
