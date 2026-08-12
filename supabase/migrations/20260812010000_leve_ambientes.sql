-- Multi-ambiente do Leve: o mesmo app serve o acervo público do Gardel e a área
-- de cada cliente (gardelbatista.com.br/<slug>). No ambiente de cliente, o que
-- no acervo é tutorial aqui é MATERIAL da consultoria. School acende por ambiente.

create table if not exists public.leve_ambientes (
  slug        text primary key,
  nome        text not null,
  tipo        text not null default 'cliente',   -- publico | cliente
  school_on   boolean not null default false,
  foco        text,                              -- qual é o foco agora
  meta        text,                              -- onde precisa chegar
  bem_vindo   text,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now()
);
alter table public.leve_ambientes enable row level security;
drop policy if exists leve_amb_read on public.leve_ambientes;
create policy leve_amb_read on public.leve_ambientes for select using (ativo);
drop policy if exists leve_amb_admin on public.leve_ambientes;
create policy leve_amb_admin on public.leve_ambientes for all to authenticated
  using (public.is_batista_admin()) with check (public.is_batista_admin());

-- quem entra em ambiente de cliente
create table if not exists public.leve_ambiente_membros (
  ambiente   text not null references public.leve_ambientes(slug) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  papel      text not null default 'cliente',
  criado_em  timestamptz not null default now(),
  primary key (ambiente, user_id)
);
alter table public.leve_ambiente_membros enable row level security;
drop policy if exists leve_membro_self on public.leve_ambiente_membros;
create policy leve_membro_self on public.leve_ambiente_membros for select to authenticated
  using (user_id = auth.uid() or public.is_batista_admin());
drop policy if exists leve_membro_admin on public.leve_ambiente_membros;
create policy leve_membro_admin on public.leve_ambiente_membros for all to authenticated
  using (public.is_batista_admin()) with check (public.is_batista_admin());

create or replace function public.leve_pode_ver(p_ambiente text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select a.tipo = 'publico' from public.leve_ambientes a where a.slug = p_ambiente and a.ativo),
    false)
  or public.is_batista_admin()
  or exists (select 1 from public.leve_ambiente_membros m
             where m.ambiente = p_ambiente and m.user_id = auth.uid());
$$;

-- conteúdo passa a ter dono: o ambiente
alter table public.leve_items         add column if not exists ambiente text not null default 'gardel';
alter table public.leve_announcements add column if not exists ambiente text not null default 'gardel';
alter table public.leve_videos        add column if not exists ambiente text not null default 'gardel';
create index if not exists leve_items_amb_idx on public.leve_items (ambiente, sort_order);

-- item de ambiente de cliente só aparece para quem é daquele ambiente
drop policy if exists leve_items_read on public.leve_items;
create policy leve_items_read on public.leve_items for select
  using (public.leve_pode_ver(ambiente)
         and (public.is_batista_admin() or (data->>'oculto') is distinct from 'true'));

drop policy if exists leve_ann_read on public.leve_announcements;
create policy leve_ann_read on public.leve_announcements for select using (public.leve_pode_ver(ambiente));

drop policy if exists leve_videos_read_active on public.leve_videos;
create policy leve_videos_read_active on public.leve_videos for select to authenticated
  using (public.leve_pode_ver(ambiente) and (expires_at > now() or public.is_batista_admin()));

-- admin: criar ambiente e dar acesso por e-mail, sem sair do painel
create or replace function public.leve_ambiente_salvar(
  p_slug text, p_nome text, p_tipo text default 'cliente', p_school_on boolean default null,
  p_foco text default null, p_meta text default null, p_bem_vindo text default null)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not public.is_batista_admin() then raise exception 'só admin'; end if;
  insert into public.leve_ambientes (slug, nome, tipo, school_on, foco, meta, bem_vindo)
  values (p_slug, p_nome, coalesce(p_tipo,'cliente'), coalesce(p_school_on,false), p_foco, p_meta, p_bem_vindo)
  on conflict (slug) do update set
    nome = excluded.nome, tipo = excluded.tipo,
    school_on = coalesce(p_school_on, public.leve_ambientes.school_on),
    foco = coalesce(p_foco, public.leve_ambientes.foco),
    meta = coalesce(p_meta, public.leve_ambientes.meta),
    bem_vindo = coalesce(p_bem_vindo, public.leve_ambientes.bem_vindo);
  return p_slug;
end;
$$;

create or replace function public.leve_membro_add(p_ambiente text, p_email text)
returns boolean language plpgsql security definer set search_path = public, auth as $$
declare v_uid uuid;
begin
  if not public.is_batista_admin() then raise exception 'só admin'; end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then return false; end if;   -- ainda não criou conta
  insert into public.leve_ambiente_membros (ambiente, user_id) values (p_ambiente, v_uid)
  on conflict do nothing;
  return true;
end;
$$;

-- a home do ambiente: o que o app precisa saber antes de desenhar
create or replace function public.leve_ambiente(p_slug text)
returns json language sql stable security definer set search_path = public as $$
  select case when not public.leve_pode_ver(p_slug) then null else (
    select json_build_object(
      'slug', a.slug, 'nome', a.nome, 'tipo', a.tipo, 'schoolOn', a.school_on,
      'foco', a.foco, 'meta', a.meta, 'bemVindo', a.bem_vindo)
    from public.leve_ambientes a where a.slug = p_slug and a.ativo
  ) end;
$$;

grant execute on function public.leve_pode_ver, public.leve_ambiente_salvar,
  public.leve_membro_add, public.leve_ambiente to anon, authenticated;

-- o Leve do Gardel (acervo público) e o primeiro cliente
insert into public.leve_ambientes (slug, nome, tipo, school_on, bem_vindo)
values ('gardel', 'Leve', 'publico', false, 'O acervo de quem executa.')
on conflict (slug) do nothing;
