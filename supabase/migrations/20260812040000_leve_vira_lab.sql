-- O produto se chama Lab, não Leve. Renomeia as tabelas e recria as funções,
-- porque função PL/pgSQL resolve o nome da tabela em tempo de execução: sem
-- recriar, tudo quebraria depois do rename.

alter table if exists public.leve_items          rename to lab_items;
alter table if exists public.leve_announcements  rename to lab_announcements;
alter table if exists public.leve_banner         rename to lab_banner;
alter table if exists public.leve_videos         rename to lab_videos;
alter table if exists public.leve_profiles       rename to lab_profiles;
alter table if exists public.leve_ambientes      rename to lab_ambientes;
alter table if exists public.leve_ambiente_membros rename to lab_ambiente_membros;

drop function if exists public.leve_handle_new_user() cascade;
create or replace function public.lab_handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.lab_profiles (id, email, full_name, phone, profissao, came_from)
  values (new.id, new.email,
    nullif(new.raw_user_meta_data->>'full_name',''),
    nullif(new.raw_user_meta_data->>'phone',''),
    nullif(new.raw_user_meta_data->>'profissao',''),
    nullif(new.raw_user_meta_data->>'came_from',''))
  on conflict (id) do update set
    full_name = coalesce(public.lab_profiles.full_name, excluded.full_name),
    phone     = coalesce(public.lab_profiles.phone, excluded.phone),
    profissao = coalesce(public.lab_profiles.profissao, excluded.profissao),
    came_from = coalesce(public.lab_profiles.came_from, excluded.came_from);
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_leve on auth.users;
drop trigger if exists on_auth_user_created_lab on auth.users;
create trigger on_auth_user_created_lab
  after insert on auth.users for each row execute function public.lab_handle_new_user();

create or replace function public.lab_pode_ver(p_ambiente text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.tipo = 'publico' from public.lab_ambientes a where a.slug = p_ambiente and a.ativo), false)
  or public.is_batista_admin()
  or exists (select 1 from public.lab_ambiente_membros m where m.ambiente = p_ambiente and m.user_id = auth.uid());
$$;

create or replace function public.lab_ambiente_porta(p_slug text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('slug', a.slug, 'nome', a.nome, 'tipo', a.tipo,
    'temSenha', a.senha_hash is not null, 'bemVindo', a.bem_vindo)
  from public.lab_ambientes a where a.slug = p_slug and a.ativo;
$$;

create or replace function public.lab_area(p_slug text, p_senha text)
returns json language sql stable security definer set search_path = public, extensions as $$
  select case when not exists (
      select 1 from public.lab_ambientes a
      where a.slug = p_slug and a.ativo and a.senha_hash is not null
        and a.senha_hash = crypt(p_senha, a.senha_hash)
    ) then null else (
    select json_build_object(
      'slug', a.slug, 'nome', a.nome, 'tipo', a.tipo, 'schoolOn', a.school_on,
      'foco', a.foco, 'meta', a.meta, 'bemVindo', a.bem_vindo,
      'itens', (select coalesce(json_agg(json_build_object('slug', i.slug, 'sort', i.sort_order, 'data', i.data)
                order by i.sort_order), '[]'::json)
                from public.lab_items i
                where i.ambiente = a.slug and (i.data->>'oculto') is distinct from 'true'),
      'avisos', (select coalesce(json_agg(json_build_object('id', n.id, 'sort', n.sort_order, 'data', n.data)
                 order by n.sort_order), '[]'::json)
                 from public.lab_announcements n where n.ambiente = a.slug))
    from public.lab_ambientes a where a.slug = p_slug
  ) end;
$$;

create or replace function public.lab_ambiente(p_slug text)
returns json language sql stable security definer set search_path = public as $$
  select case when not public.lab_pode_ver(p_slug) then null else (
    select json_build_object('slug', a.slug, 'nome', a.nome, 'tipo', a.tipo,
      'schoolOn', a.school_on, 'foco', a.foco, 'meta', a.meta, 'bemVindo', a.bem_vindo)
    from public.lab_ambientes a where a.slug = p_slug and a.ativo) end;
$$;

create or replace function public.lab_ambiente_salvar(
  p_slug text, p_nome text, p_tipo text default 'cliente', p_school_on boolean default null,
  p_foco text default null, p_meta text default null, p_bem_vindo text default null)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not public.is_batista_admin() then raise exception 'só admin'; end if;
  insert into public.lab_ambientes (slug, nome, tipo, school_on, foco, meta, bem_vindo)
  values (p_slug, p_nome, coalesce(p_tipo,'cliente'), coalesce(p_school_on,false), p_foco, p_meta, p_bem_vindo)
  on conflict (slug) do update set
    nome = excluded.nome, tipo = excluded.tipo,
    school_on = coalesce(p_school_on, public.lab_ambientes.school_on),
    foco = coalesce(p_foco, public.lab_ambientes.foco),
    meta = coalesce(p_meta, public.lab_ambientes.meta),
    bem_vindo = coalesce(p_bem_vindo, public.lab_ambientes.bem_vindo);
  return p_slug;
end;
$$;

create or replace function public.lab_ambiente_senha(p_admin text, p_slug text, p_nova text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not (public.is_batista_admin() or public.batista_diagnostico_admin_ok(p_admin)) then return false; end if;
  update public.lab_ambientes set senha_hash = crypt(p_nova, gen_salt('bf')) where slug = p_slug;
  return found;
end;
$$;

create or replace function public.lab_membro_add(p_ambiente text, p_email text)
returns boolean language plpgsql security definer set search_path = public, auth as $$
declare v_uid uuid;
begin
  if not public.is_batista_admin() then raise exception 'só admin'; end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then return false; end if;
  insert into public.lab_ambiente_membros (ambiente, user_id) values (p_ambiente, v_uid) on conflict do nothing;
  return true;
end;
$$;

create or replace function public.lab_item_salvar(
  p_admin text, p_ambiente text, p_slug text, p_data jsonb, p_sort int default 0)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  if not (public.is_batista_admin() or public.batista_diagnostico_admin_ok(p_admin)) then
    raise exception 'sem permissão';
  end if;
  insert into public.lab_items (slug, data, sort_order, ambiente)
  values (p_slug, p_data, p_sort, p_ambiente)
  on conflict (slug) do update set data = excluded.data, sort_order = excluded.sort_order,
    ambiente = excluded.ambiente, updated_at = now();
  return p_slug;
end;
$$;

create or replace function public.lab_item_remover(p_admin text, p_slug text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not (public.is_batista_admin() or public.batista_diagnostico_admin_ok(p_admin)) then
    raise exception 'sem permissão';
  end if;
  delete from public.lab_items where slug = p_slug;
  return found;
end;
$$;

create or replace function public.lab_school_vitrine()
returns table(id uuid, title text, description text, cover_url text, category text, total_lessons integer)
language sql stable security definer set search_path = public as $$
  select id, title, description, cover_url, category, total_lessons
  from public.curso_courses where is_published = true order by updated_at desc;
$$;

-- as policies acompanharam o rename, mas as que citam a função antiga precisam apontar pra nova
drop policy if exists leve_items_read on public.lab_items;
create policy lab_items_read on public.lab_items for select
  using (public.lab_pode_ver(ambiente) and (public.is_batista_admin() or (data->>'oculto') is distinct from 'true'));
drop policy if exists leve_ann_read on public.lab_announcements;
create policy lab_ann_read on public.lab_announcements for select using (public.lab_pode_ver(ambiente));
drop policy if exists leve_videos_read_active on public.lab_videos;
create policy lab_videos_read_active on public.lab_videos for select to authenticated
  using (public.lab_pode_ver(ambiente) and (expires_at > now() or public.is_batista_admin()));

-- o ambiente público do Batista chama Lab
update public.lab_ambientes set nome = 'Lab' where slug = 'gardel';

drop function if exists public.leve_pode_ver(text) cascade;
drop function if exists public.leve_ambiente_porta(text);
drop function if exists public.leve_area(text,text);
drop function if exists public.leve_ambiente(text);
drop function if exists public.leve_ambiente_salvar(text,text,text,boolean,text,text,text);
drop function if exists public.leve_ambiente_senha(text,text,text);
drop function if exists public.leve_membro_add(text,text);
drop function if exists public.leve_item_salvar(text,text,text,jsonb,int);
drop function if exists public.leve_item_remover(text,text);
drop function if exists public.leve_school_vitrine();

grant execute on function public.lab_pode_ver, public.lab_ambiente_porta, public.lab_area,
  public.lab_ambiente, public.lab_ambiente_salvar, public.lab_ambiente_senha, public.lab_membro_add,
  public.lab_item_salvar, public.lab_item_remover, public.lab_school_vitrine to anon, authenticated;
