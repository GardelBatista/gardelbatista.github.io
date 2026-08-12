-- Ambiente de cliente entra por SENHA, sem tela de cadastro. O ambiente público
-- (o acervo do Batista) continua com conta. Quem manda é o slug.

alter table public.leve_ambientes add column if not exists senha_hash text;

-- o que o app pode saber ANTES de qualquer senha: só o suficiente para desenhar a porta
create or replace function public.leve_ambiente_porta(p_slug text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'slug', a.slug, 'nome', a.nome, 'tipo', a.tipo,
    'temSenha', a.senha_hash is not null, 'bemVindo', a.bem_vindo)
  from public.leve_ambientes a where a.slug = p_slug and a.ativo;
$$;

-- a área inteira mediante senha: ambiente + materiais, sem exigir login
create or replace function public.leve_area(p_slug text, p_senha text)
returns json language sql stable security definer set search_path = public, extensions as $$
  select case when not exists (
      select 1 from public.leve_ambientes a
      where a.slug = p_slug and a.ativo and a.senha_hash is not null
        and a.senha_hash = crypt(p_senha, a.senha_hash)
    ) then null else (
    select json_build_object(
      'slug', a.slug, 'nome', a.nome, 'tipo', a.tipo, 'schoolOn', a.school_on,
      'foco', a.foco, 'meta', a.meta, 'bemVindo', a.bem_vindo,
      'itens', (
        select coalesce(json_agg(json_build_object(
          'slug', i.slug, 'sort', i.sort_order, 'data', i.data
        ) order by i.sort_order), '[]'::json)
        from public.leve_items i
        where i.ambiente = a.slug and (i.data->>'oculto') is distinct from 'true'
      ),
      'avisos', (
        select coalesce(json_agg(json_build_object('id', n.id, 'sort', n.sort_order, 'data', n.data)
               order by n.sort_order), '[]'::json)
        from public.leve_announcements n where n.ambiente = a.slug
      )
    )
    from public.leve_ambientes a where a.slug = p_slug
  ) end;
$$;

create or replace function public.leve_ambiente_senha(p_admin text, p_slug text, p_nova text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  -- aceita tanto o admin logado quanto a senha de admin que já existia no site
  if not (public.is_batista_admin() or public.batista_diagnostico_admin_ok(p_admin)) then
    return false;
  end if;
  update public.leve_ambientes set senha_hash = crypt(p_nova, gen_salt('bf')) where slug = p_slug;
  return found;
end;
$$;

grant execute on function public.leve_ambiente_porta, public.leve_area, public.leve_ambiente_senha to anon, authenticated;
