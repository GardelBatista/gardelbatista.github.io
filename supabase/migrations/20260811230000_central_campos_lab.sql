-- Central de consultoria: campos que o padrão do Lab exige (slug para deep-link,
-- categoria para os filtros, destaque, e o que o cliente ganha com o material).
alter table public.batista_entregaveis add column if not exists slug text;
alter table public.batista_entregaveis add column if not exists categoria text;
alter table public.batista_entregaveis add column if not exists resultado text;
alter table public.batista_entregaveis add column if not exists destaque boolean not null default false;
create unique index if not exists batista_entregaveis_slug_idx on public.batista_entregaveis (cliente_slug, slug) where slug is not null;

alter table public.batista_trilha add column if not exists duracao text;

-- as assinaturas antigas viram overload e quebram o grant: dropar primeiro
drop function if exists public.batista_entregavel_salvar(text,text,text,text,text,text,text,int,date,boolean,uuid);
drop function if exists public.batista_trilha_salvar(text,text,text,text,text,text,text,int,int,boolean,uuid);

-- área do cliente: agora devolve os campos novos
create or replace function public.batista_cliente_area(p_slug text, p_senha text)
returns json language sql security definer set search_path = public, extensions as $$
  select case when not public.batista_cliente_ok(p_slug, p_senha) then null else (
    select json_build_object(
      'nome',           c.nome,
      'bemVindo',       c.bem_vindo,
      'mostrarTrilha',  c.mostrar_trilha,
      'entregaveis', (
        select coalesce(json_agg(json_build_object(
          'id', e.id, 'slug', coalesce(e.slug, e.id::text), 'titulo', e.titulo,
          'descricao', e.descricao, 'resultado', e.resultado, 'tipo', e.tipo,
          'categoria', e.categoria, 'url', e.url, 'status', e.status,
          'data', e.data_entrega, 'destaque', e.destaque
        ) order by e.ordem, e.criado_em), '[]'::json)
        from public.batista_entregaveis e
        where e.cliente_slug = c.slug and e.publicado
      ),
      'trilha', (
        select coalesce(json_agg(json_build_object(
          'id', t.id, 'semana', t.semana, 'titulo', t.titulo, 'fonte', t.fonte,
          'url', t.url, 'tipo', t.tipo, 'porque', t.porque, 'duracao', t.duracao
        ) order by t.semana nulls last, t.ordem), '[]'::json)
        from public.batista_trilha t
        where t.cliente_slug = c.slug and t.publicado
      )
    )
    from public.batista_clientes c where c.slug = p_slug
  ) end;
$$;

create or replace function public.batista_entregavel_salvar(
  p_admin text, p_slug text, p_titulo text, p_descricao text default null,
  p_tipo text default 'documento', p_url text default null, p_status text default 'entregue',
  p_ordem int default 0, p_data date default null, p_publicado boolean default true,
  p_id uuid default null, p_doc_slug text default null, p_categoria text default null,
  p_resultado text default null, p_destaque boolean default false)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not public.batista_diagnostico_admin_ok(p_admin) then return null; end if;
  if p_id is null then
    insert into public.batista_entregaveis (cliente_slug, titulo, descricao, tipo, url, status,
      ordem, data_entrega, publicado, slug, categoria, resultado, destaque)
    values (p_slug, p_titulo, p_descricao, p_tipo, p_url, p_status, p_ordem, p_data, p_publicado,
      p_doc_slug, p_categoria, p_resultado, p_destaque)
    returning id into v_id;
  else
    update public.batista_entregaveis set
      titulo = p_titulo, descricao = p_descricao, tipo = p_tipo, url = p_url,
      status = p_status, ordem = p_ordem, data_entrega = p_data, publicado = p_publicado,
      slug = coalesce(p_doc_slug, slug), categoria = coalesce(p_categoria, categoria),
      resultado = coalesce(p_resultado, resultado), destaque = p_destaque
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.batista_trilha_salvar(
  p_admin text, p_slug text, p_titulo text, p_fonte text default null,
  p_url text default null, p_tipo text default 'canal', p_porque text default null,
  p_semana int default null, p_ordem int default 0, p_publicado boolean default true,
  p_id uuid default null, p_duracao text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not public.batista_diagnostico_admin_ok(p_admin) then return null; end if;
  if p_id is null then
    insert into public.batista_trilha (cliente_slug, titulo, fonte, url, tipo, porque, semana, ordem, publicado, duracao)
    values (p_slug, p_titulo, p_fonte, p_url, p_tipo, p_porque, p_semana, p_ordem, p_publicado, p_duracao)
    returning id into v_id;
  else
    update public.batista_trilha set
      titulo = p_titulo, fonte = p_fonte, url = p_url, tipo = p_tipo,
      porque = p_porque, semana = p_semana, ordem = p_ordem, publicado = p_publicado,
      duracao = coalesce(p_duracao, duracao)
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end;
$$;

grant execute on function public.batista_cliente_area, public.batista_entregavel_salvar,
  public.batista_trilha_salvar to anon;
