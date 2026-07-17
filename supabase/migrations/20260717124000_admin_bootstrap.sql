-- bootstrap: primeira senha pode ser definida quando a tabela está vazia
create or replace function public.batista_diagnostico_admin_troca_senha(p_atual text, p_nova text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if length(coalesce(p_nova,'')) < 8 then return false; end if;
  if not exists (select 1 from public.batista_diagnostico_admin where id = 1) then
    insert into public.batista_diagnostico_admin (id, senha_hash) values (1, crypt(p_nova, gen_salt('bf')));
    return true;
  end if;
  if not public.batista_diagnostico_admin_ok(p_atual) then return false; end if;
  update public.batista_diagnostico_admin set senha_hash = crypt(p_nova, gen_salt('bf')) where id = 1;
  return true;
end;
$$;
