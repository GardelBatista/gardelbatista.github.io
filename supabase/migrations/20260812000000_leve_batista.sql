-- LEVE BATISTA: cópia do schema do MyDose Lab neste banco, com o prefixo leve_.
-- Mesmo desenho do original: o conteúdo mora em `data jsonb` (o item inteiro),
-- leitura pública, escrita só de admin. O School reaproveita as tabelas curso_*
-- que já existem aqui.

-- quem é admin (espelho do is_mydose_admin, lendo a user_roles que já existe)
create or replace function public.is_batista_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid() and r.role::text = 'admin'
  );
$$;

-- perfil do usuário (espelho de profiles do Lab)
create table if not exists public.leve_profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  phone       text,
  profissao   text,
  came_from   text,
  is_cliente  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.leve_profiles enable row level security;
drop policy if exists leve_profiles_select_own_or_admin on public.leve_profiles;
create policy leve_profiles_select_own_or_admin on public.leve_profiles
  for select to authenticated using (id = auth.uid() or public.is_batista_admin());
drop policy if exists leve_profiles_update_own_or_admin on public.leve_profiles;
create policy leve_profiles_update_own_or_admin on public.leve_profiles
  for update to authenticated using (id = auth.uid() or public.is_batista_admin())
  with check (id = auth.uid() or public.is_batista_admin());

-- cria o perfil no cadastro (espelho do handle_new_user)
create or replace function public.leve_handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.leve_profiles (id, email, full_name, phone, profissao, came_from)
  values (
    new.id, new.email,
    nullif(new.raw_user_meta_data->>'full_name',''),
    nullif(new.raw_user_meta_data->>'phone',''),
    nullif(new.raw_user_meta_data->>'profissao',''),
    nullif(new.raw_user_meta_data->>'came_from','')
  )
  on conflict (id) do update set
    full_name = coalesce(public.leve_profiles.full_name, excluded.full_name),
    phone     = coalesce(public.leve_profiles.phone, excluded.phone),
    profissao = coalesce(public.leve_profiles.profissao, excluded.profissao),
    came_from = coalesce(public.leve_profiles.came_from, excluded.came_from);
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_leve on auth.users;
create trigger on_auth_user_created_leve
  after insert on auth.users for each row execute function public.leve_handle_new_user();

-- acervo (espelho de lab_items): o item inteiro em jsonb, item oculto some pra quem não é admin
create table if not exists public.leve_items (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,
  data        jsonb not null default '{}'::jsonb,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.leve_items enable row level security;
drop policy if exists leve_items_read on public.leve_items;
create policy leve_items_read on public.leve_items for select
  using (public.is_batista_admin() or (data->>'oculto') is distinct from 'true');
drop policy if exists leve_items_admin_ins on public.leve_items;
create policy leve_items_admin_ins on public.leve_items for insert with check (public.is_batista_admin());
drop policy if exists leve_items_admin_upd on public.leve_items;
create policy leve_items_admin_upd on public.leve_items for update using (public.is_batista_admin()) with check (public.is_batista_admin());
drop policy if exists leve_items_admin_del on public.leve_items;
create policy leve_items_admin_del on public.leve_items for delete using (public.is_batista_admin());

-- avisos do topo (espelho de lab_announcements)
create table if not exists public.leve_announcements (
  id          uuid primary key default gen_random_uuid(),
  data        jsonb not null default '{}'::jsonb,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.leve_announcements enable row level security;
drop policy if exists leve_ann_read on public.leve_announcements;
create policy leve_ann_read on public.leve_announcements for select using (true);
drop policy if exists leve_ann_admin_ins on public.leve_announcements;
create policy leve_ann_admin_ins on public.leve_announcements for insert with check (public.is_batista_admin());
drop policy if exists leve_ann_admin_upd on public.leve_announcements;
create policy leve_ann_admin_upd on public.leve_announcements for update using (public.is_batista_admin()) with check (public.is_batista_admin());
drop policy if exists leve_ann_admin_del on public.leve_announcements;
create policy leve_ann_admin_del on public.leve_announcements for delete using (public.is_batista_admin());

-- faixa editável (espelho de lab_banner): uma linha só
create table if not exists public.leve_banner (
  id          smallint primary key default 1 check (id = 1),
  data        jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
alter table public.leve_banner enable row level security;
drop policy if exists leve_banner_read on public.leve_banner;
create policy leve_banner_read on public.leve_banner for select using (true);
drop policy if exists leve_banner_admin_ins on public.leve_banner;
create policy leve_banner_admin_ins on public.leve_banner for insert with check (public.is_batista_admin());
drop policy if exists leve_banner_admin_upd on public.leve_banner;
create policy leve_banner_admin_upd on public.leve_banner for update using (public.is_batista_admin()) with check (public.is_batista_admin());

-- vídeos da semana (espelho de lab_videos): expiram em 7 dias sozinhos
create table if not exists public.leve_videos (
  id           uuid primary key default gen_random_uuid(),
  created_by   uuid,
  title        text,
  youtube_url  text not null,
  youtube_id   text,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default (now() + interval '7 days')
);
alter table public.leve_videos enable row level security;
drop policy if exists leve_videos_read_active on public.leve_videos;
create policy leve_videos_read_active on public.leve_videos for select to authenticated
  using (expires_at > now() or public.is_batista_admin());
drop policy if exists leve_videos_write_admin on public.leve_videos;
create policy leve_videos_write_admin on public.leve_videos for all to authenticated
  using (public.is_batista_admin()) with check (public.is_batista_admin());

-- vitrine do School: aponta para os cursos que JÁ existem neste banco
create or replace function public.leve_school_vitrine()
returns table(id uuid, title text, description text, cover_url text, category text, total_lessons integer)
language sql stable security definer set search_path = public as $$
  select id, title, description, cover_url, category, total_lessons
  from public.curso_courses
  where is_published = true
  order by updated_at desc;
$$;

grant execute on function public.is_batista_admin, public.leve_school_vitrine to anon, authenticated;
