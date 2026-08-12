-- Central de consultoria do batista.growth: uma área por cliente (/gaud, /<slug>...)
-- Mesmo padrão do painel do /diagnostico: nada é lido direto, tudo passa por RPC
-- security definer com a senha. Senha NUNCA vive no repo (é hash bcrypt no banco).
create extension if not exists pgcrypto;

-- ---------- tabelas ----------

create table if not exists public.batista_clientes (
  slug            text primary key,
  nome            text not null,
  senha_hash      text not null,
  ativo           boolean not null default true,
  mostrar_trilha  boolean not null default false,   -- o "School": só acende quando tiver conteúdo
  bem_vindo       text,                             -- linha de contexto no topo da área
  criado_em       timestamptz not null default now()
);
alter table public.batista_clientes enable row level security;

create table if not exists public.batista_entregaveis (
  id            uuid primary key default gen_random_uuid(),
  cliente_slug  text not null references public.batista_clientes(slug) on delete cascade,
  ordem         int not null default 0,
  titulo        text not null,
  descricao     text,
  tipo          text not null default 'documento',  -- documento | painel | roteiro | planilha | video | link
  url           text,
  status        text not null default 'entregue',   -- entregue | producao | previsto
  data_entrega  date,
  publicado     boolean not null default true,
  criado_em     timestamptz not null default now()
);
alter table public.batista_entregaveis enable row level security;
create index if not exists batista_entregaveis_cliente_idx on public.batista_entregaveis (cliente_slug, ordem);

-- a trilha de estudo (canais de referência, cursos indicados, cronograma)
create table if not exists public.batista_trilha (
  id            uuid primary key default gen_random_uuid(),
  cliente_slug  text not null references public.batista_clientes(slug) on delete cascade,
  ordem         int not null default 0,
  semana        int,                                -- null = sem cronograma, só recomendação
  titulo        text not null,
  fonte         text,                               -- "YouTube · nome do canal", "Curso X"
  url           text,
  tipo          text not null default 'canal',      -- canal | curso | leitura | ferramenta
  porque        text,                               -- por que isso está aqui
  publicado     boolean not null default true
);
alter table public.batista_trilha enable row level security;

-- saber se o cliente abriu o material é informação de consultoria
create table if not exists public.batista_cliente_acessos (
  id            bigserial primary key,
  cliente_slug  text not null,
  evento        text not null,                      -- entrou | abriu
  ref           text,
  criado_em     timestamptz not null default now()
);
alter table public.batista_cliente_acessos enable row level security;
create index if not exists batista_cliente_acessos_idx on public.batista_cliente_acessos (cliente_slug, criado_em desc);

-- Nenhuma policy em nenhuma das quatro: anon e authenticated não leem nem escrevem
-- direto. O acesso é exclusivamente pelas functions abaixo.

-- ---------- leitura pelo cliente ----------

create or replace function public.batista_cliente_ok(p_slug text, p_senha text)
returns boolean language sql security definer set search_path = public, extensions as $$
  select exists(
    select 1 from public.batista_clientes
    where slug = p_slug and ativo and senha_hash = crypt(p_senha, senha_hash)
  );
$$;

create or replace function public.batista_cliente_area(p_slug text, p_senha text)
returns json language sql security definer set search_path = public, extensions as $$
  select case when not public.batista_cliente_ok(p_slug, p_senha) then null else (
    select json_build_object(
      'nome',           c.nome,
      'bemVindo',       c.bem_vindo,
      'mostrarTrilha',  c.mostrar_trilha,
      'entregaveis', (
        select coalesce(json_agg(json_build_object(
          'id', e.id, 'titulo', e.titulo, 'descricao', e.descricao, 'tipo', e.tipo,
          'url', e.url, 'status', e.status, 'data', e.data_entrega
        ) order by e.ordem, e.criado_em), '[]'::json)
        from public.batista_entregaveis e
        where e.cliente_slug = c.slug and e.publicado
      ),
      'trilha', (
        select coalesce(json_agg(json_build_object(
          'id', t.id, 'semana', t.semana, 'titulo', t.titulo, 'fonte', t.fonte,
          'url', t.url, 'tipo', t.tipo, 'porque', t.porque
        ) order by t.semana nulls last, t.ordem), '[]'::json)
        from public.batista_trilha t
        where t.cliente_slug = c.slug and t.publicado
      )
    )
    from public.batista_clientes c where c.slug = p_slug
  ) end;
$$;

create or replace function public.batista_cliente_log(p_slug text, p_senha text, p_evento text, p_ref text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.batista_cliente_ok(p_slug, p_senha) then return; end if;
  insert into public.batista_cliente_acessos (cliente_slug, evento, ref)
  values (p_slug, left(coalesce(p_evento, 'entrou'), 20), left(p_ref, 200));
end;
$$;

-- ---------- administração ----------
-- Reusa a senha do admin que já existe (batista_diagnostico_admin), então não
-- nasce um segundo segredo para guardar. Adicionar entregável não exige deploy.

create or replace function public.batista_cliente_salvar(
  p_admin text, p_slug text, p_nome text,
  p_senha text default null, p_mostrar_trilha boolean default null, p_bem_vindo text default null)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.batista_diagnostico_admin_ok(p_admin) then return false; end if;
  insert into public.batista_clientes (slug, nome, senha_hash, mostrar_trilha, bem_vindo)
  values (p_slug, p_nome, crypt(coalesce(p_senha, gen_random_uuid()::text), gen_salt('bf')),
          coalesce(p_mostrar_trilha, false), p_bem_vindo)
  on conflict (slug) do update set
    nome           = excluded.nome,
    senha_hash     = case when p_senha is null then public.batista_clientes.senha_hash else excluded.senha_hash end,
    mostrar_trilha = coalesce(p_mostrar_trilha, public.batista_clientes.mostrar_trilha),
    bem_vindo      = coalesce(p_bem_vindo, public.batista_clientes.bem_vindo);
  return true;
end;
$$;

create or replace function public.batista_entregavel_salvar(
  p_admin text, p_slug text, p_titulo text, p_descricao text default null,
  p_tipo text default 'documento', p_url text default null, p_status text default 'entregue',
  p_ordem int default 0, p_data date default null, p_publicado boolean default true,
  p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not public.batista_diagnostico_admin_ok(p_admin) then return null; end if;
  if p_id is null then
    insert into public.batista_entregaveis (cliente_slug, titulo, descricao, tipo, url, status, ordem, data_entrega, publicado)
    values (p_slug, p_titulo, p_descricao, p_tipo, p_url, p_status, p_ordem, p_data, p_publicado)
    returning id into v_id;
  else
    update public.batista_entregaveis set
      titulo = p_titulo, descricao = p_descricao, tipo = p_tipo, url = p_url,
      status = p_status, ordem = p_ordem, data_entrega = p_data, publicado = p_publicado
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.batista_trilha_salvar(
  p_admin text, p_slug text, p_titulo text, p_fonte text default null,
  p_url text default null, p_tipo text default 'canal', p_porque text default null,
  p_semana int default null, p_ordem int default 0, p_publicado boolean default true,
  p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid;
begin
  if not public.batista_diagnostico_admin_ok(p_admin) then return null; end if;
  if p_id is null then
    insert into public.batista_trilha (cliente_slug, titulo, fonte, url, tipo, porque, semana, ordem, publicado)
    values (p_slug, p_titulo, p_fonte, p_url, p_tipo, p_porque, p_semana, p_ordem, p_publicado)
    returning id into v_id;
  else
    update public.batista_trilha set
      titulo = p_titulo, fonte = p_fonte, url = p_url, tipo = p_tipo,
      porque = p_porque, semana = p_semana, ordem = p_ordem, publicado = p_publicado
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.batista_cliente_relatorio(p_admin text, p_slug text default null)
returns json language sql security definer set search_path = public, extensions as $$
  select case when not public.batista_diagnostico_admin_ok(p_admin) then null else (
    select coalesce(json_agg(a order by a.criado_em desc), '[]'::json)
    from (
      select cliente_slug, evento, ref, criado_em
      from public.batista_cliente_acessos
      where p_slug is null or cliente_slug = p_slug
      order by criado_em desc limit 300
    ) a
  ) end;
$$;

grant execute on function
  public.batista_cliente_ok, public.batista_cliente_area, public.batista_cliente_log,
  public.batista_cliente_salvar, public.batista_entregavel_salvar,
  public.batista_trilha_salvar, public.batista_cliente_relatorio to anon;
