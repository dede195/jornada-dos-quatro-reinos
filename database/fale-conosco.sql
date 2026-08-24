-- Fale Conosco — Jornada dos Saberes
-- Execute uma única vez no SQL Editor do Supabase.

create extension if not exists pgcrypto;

create table if not exists public.contatos (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(trim(nome)) between 2 and 80),
  email text not null check (char_length(trim(email)) between 5 and 160),
  whatsapp text check (whatsapp is null or char_length(trim(whatsapp)) between 8 and 30),
  instituicao text check (instituicao is null or char_length(trim(instituicao)) <= 120),
  assunto text not null check (assunto in ('demonstracao','planos','suporte','parceria','outro')),
  mensagem text not null check (char_length(trim(mensagem)) between 10 and 1500),
  consentimento boolean not null default false check (consentimento = true),
  status text not null default 'novo' check (status in ('novo','em_atendimento','respondido','arquivado')),
  criado_em timestamptz not null default now()
);

create index if not exists contatos_criado_em_idx on public.contatos(criado_em desc);
create index if not exists contatos_status_idx on public.contatos(status);

alter table public.contatos enable row level security;

drop policy if exists "Visitante envia contato" on public.contatos;
create policy "Visitante envia contato" on public.contatos
for insert to anon, authenticated
with check (
  consentimento = true
  and char_length(trim(nome)) between 2 and 80
  and char_length(trim(email)) between 5 and 160
  and char_length(trim(mensagem)) between 10 and 1500
);

revoke all on public.contatos from anon, authenticated;
grant insert on public.contatos to anon, authenticated;

-- Por segurança, as mensagens não podem ser consultadas pelo site público.
-- Consulte-as inicialmente em: Supabase > Table Editor > contatos.
