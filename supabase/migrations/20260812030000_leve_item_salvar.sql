-- Publicar material sem depender de estar logado no navegador: a mesma senha de
-- admin que já existe no site autoriza a escrita. É o que permite operar a área
-- do cliente por script, do jeito que o resto do site já é operado.
create or replace function public.leve_item_salvar(
  p_admin text, p_ambiente text, p_slug text, p_data jsonb, p_sort int default 0)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  if not (public.is_batista_admin() or public.batista_diagnostico_admin_ok(p_admin)) then
    raise exception 'sem permissão';
  end if;
  insert into public.leve_items (slug, data, sort_order, ambiente)
  values (p_slug, p_data, p_sort, p_ambiente)
  on conflict (slug) do update set
    data = excluded.data, sort_order = excluded.sort_order,
    ambiente = excluded.ambiente, updated_at = now();
  return p_slug;
end;
$$;

create or replace function public.leve_item_remover(p_admin text, p_slug text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not (public.is_batista_admin() or public.batista_diagnostico_admin_ok(p_admin)) then
    raise exception 'sem permissão';
  end if;
  delete from public.leve_items where slug = p_slug;
  return found;
end;
$$;

grant execute on function public.leve_item_salvar, public.leve_item_remover to anon, authenticated;
