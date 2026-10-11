-- Пианино с нуля: база данных для Supabase.
-- Как применить: Supabase → SQL Editor → New query → вставить весь файл → Run.

-- Профили: имя в рейтинге и флаг администратора
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'Пианист' check (char_length(name) between 1 and 30),
  email text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- Прогресс: опыт, звёзды по каждому уроку, серия дней
create table if not exists public.progress (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  xp integer not null default 0 check (xp >= 0 and xp < 1000000),
  stars jsonb not null default '{}'::jsonb,
  total_stars integer not null default 0 check (total_stars between 0 and 1000),
  streak integer not null default 0,
  last_day text,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.progress enable row level security;

-- Проверка «я администратор» (без рекурсии в политиках)
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- Профили: видишь свой (админ видит все), менять можешь только имя
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select using (id = auth.uid() or public.is_admin());
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated, anon;
grant update (name) on public.profiles to authenticated;

-- Прогресс: читаешь и пишешь только свой (админ читает все)
drop policy if exists "progress read" on public.progress;
create policy "progress read" on public.progress for select using (user_id = auth.uid() or public.is_admin());
drop policy if exists "progress insert own" on public.progress;
create policy "progress insert own" on public.progress for insert with check (user_id = auth.uid());
drop policy if exists "progress update own" on public.progress;
create policy "progress update own" on public.progress for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Профиль создаётся автоматически при регистрации
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, coalesce(nullif(left(new.raw_user_meta_data->>'name', 30), ''), 'Пианист'), new.email)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Публичный рейтинг: только имя и результаты, без почты и id
create or replace view public.leaderboard as
  select p.name, pr.xp, pr.total_stars, pr.stars, pr.streak, pr.updated_at,
         (pr.user_id = auth.uid()) as is_me
  from public.progress pr join public.profiles p on p.id = pr.user_id;
grant select on public.leaderboard to anon, authenticated;

-- Данные для админки (вернёт пусто, если ты не администратор)
create or replace function public.admin_users()
returns table (id uuid, name text, email text, created_at timestamptz, xp int, total_stars int, streak int, stars jsonb, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, p.created_at,
         coalesce(pr.xp, 0), coalesce(pr.total_stars, 0), coalesce(pr.streak, 0),
         coalesce(pr.stars, '{}'::jsonb), pr.updated_at
  from public.profiles p left join public.progress pr on pr.user_id = p.id
  where public.is_admin()
  order by pr.xp desc nulls last
$$;
grant execute on function public.admin_users() to authenticated;

-- Сделать себя администратором (подставь свою почту и выполни отдельно после регистрации):
-- update public.profiles set is_admin = true where email = 'твоя@почта.ru';
