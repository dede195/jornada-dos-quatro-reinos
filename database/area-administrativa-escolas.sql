-- Área Administrativa das Escolas — Jornada dos Saberes
-- Execute uma única vez no SQL Editor do Supabase.

create extension if not exists pgcrypto;

create table if not exists public.escolas (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(nome) between 2 and 100),
  codigo_acesso text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  ativa boolean not null default true,
  criado_em timestamptz not null default now()
);

create table if not exists public.membros_escola (
  escola_id uuid not null references public.escolas(id) on delete cascade,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  papel text not null check (papel in ('gestor','professor')),
  criado_em timestamptz not null default now(),
  primary key (escola_id, usuario_id)
);

alter table public.turmas
  add column if not exists escola_id uuid references public.escolas(id) on delete cascade;

create index if not exists membros_escola_usuario_idx on public.membros_escola(usuario_id);
create index if not exists turmas_escola_idx on public.turmas(escola_id);

alter table public.escolas enable row level security;
alter table public.membros_escola enable row level security;

create or replace function public.usuario_na_escola(p_escola uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.membros_escola
    where escola_id = p_escola and usuario_id = auth.uid()
  );
$$;

create or replace function public.usuario_gestor(p_escola uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.membros_escola
    where escola_id = p_escola and usuario_id = auth.uid() and papel = 'gestor'
  );
$$;

create or replace function public.pode_acessar_turma(p_turma uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.turmas t
    where t.id = p_turma
      and (t.professora_id = auth.uid() or public.usuario_gestor(t.escola_id))
  );
$$;

create or replace function public.criar_escola(p_nome text)
returns public.escolas
language plpgsql security definer
set search_path = public
as $$
declare nova_escola public.escolas;
begin
  if auth.uid() is null then raise exception 'Login necessário'; end if;
  insert into public.escolas(nome) values (trim(p_nome)) returning * into nova_escola;
  insert into public.membros_escola(escola_id, usuario_id, papel)
  values (nova_escola.id, auth.uid(), 'gestor');
  return nova_escola;
end;
$$;

create or replace function public.entrar_na_escola(p_codigo text)
returns public.escolas
language plpgsql security definer
set search_path = public
as $$
declare escola_encontrada public.escolas;
begin
  if auth.uid() is null then raise exception 'Login necessário'; end if;
  select * into escola_encontrada from public.escolas
  where codigo_acesso = upper(trim(p_codigo)) and ativa = true;
  if escola_encontrada.id is null then raise exception 'Código da escola não encontrado'; end if;
  insert into public.membros_escola(escola_id, usuario_id, papel)
  values (escola_encontrada.id, auth.uid(), 'professor')
  on conflict (escola_id, usuario_id) do nothing;
  return escola_encontrada;
end;
$$;

drop policy if exists "Membros consultam a escola" on public.escolas;
create policy "Membros consultam a escola" on public.escolas
for select to authenticated using (public.usuario_na_escola(id));

drop policy if exists "Gestores atualizam a escola" on public.escolas;
create policy "Gestores atualizam a escola" on public.escolas
for update to authenticated using (public.usuario_gestor(id)) with check (public.usuario_gestor(id));

drop policy if exists "Membros consultam colegas" on public.membros_escola;
create policy "Membros consultam colegas" on public.membros_escola
for select to authenticated using (public.usuario_na_escola(escola_id));

drop policy if exists "Gestores administram membros" on public.membros_escola;
create policy "Gestores administram membros" on public.membros_escola
for update to authenticated using (public.usuario_gestor(escola_id)) with check (public.usuario_gestor(escola_id));

drop policy if exists "Escola consulta perfis de membros" on public.perfis;
create policy "Escola consulta perfis de membros" on public.perfis
for select to authenticated using (
  id = auth.uid() or exists (
    select 1 from public.membros_escola m
    where m.usuario_id = perfis.id and public.usuario_na_escola(m.escola_id)
  )
);

drop policy if exists "Escola consulta turmas autorizadas" on public.turmas;
create policy "Escola consulta turmas autorizadas" on public.turmas
for select to authenticated using (
  professora_id = auth.uid() or public.usuario_gestor(escola_id)
);

drop policy if exists "Gestor cria turmas da escola" on public.turmas;
create policy "Gestor cria turmas da escola" on public.turmas
for insert to authenticated with check (
  professora_id = auth.uid() or public.usuario_gestor(escola_id)
);

drop policy if exists "Gestor atualiza turmas da escola" on public.turmas;
create policy "Gestor atualiza turmas da escola" on public.turmas
for update to authenticated using (
  professora_id = auth.uid() or public.usuario_gestor(escola_id)
) with check (
  professora_id = auth.uid() or public.usuario_gestor(escola_id)
);

drop policy if exists "Equipe consulta alunos autorizados" on public.alunos;
create policy "Equipe consulta alunos autorizados" on public.alunos
for select to authenticated using (public.pode_acessar_turma(turma_id));

drop policy if exists "Equipe cadastra alunos autorizados" on public.alunos;
create policy "Equipe cadastra alunos autorizados" on public.alunos
for insert to authenticated with check (public.pode_acessar_turma(turma_id));

drop policy if exists "Equipe consulta progresso autorizado" on public.progresso;
create policy "Equipe consulta progresso autorizado" on public.progresso
for select to authenticated using (
  exists (select 1 from public.alunos a where a.id = progresso.aluno_id and public.pode_acessar_turma(a.turma_id))
);

drop policy if exists "Equipe consulta tentativas autorizadas" on public.tentativas;
create policy "Equipe consulta tentativas autorizadas" on public.tentativas
for select to authenticated using (
  exists (select 1 from public.alunos a where a.id = tentativas.aluno_id and public.pode_acessar_turma(a.turma_id))
);

grant select, update on public.escolas to authenticated;
grant select, update on public.membros_escola to authenticated;
grant execute on function public.criar_escola(text) to authenticated;
grant execute on function public.entrar_na_escola(text) to authenticated;
