-- Обновление 2: свои песни пользователей, оценки и отзывы, рейтинг авторов.
-- Уже применено к базе. Файл нужен для истории и для новой базы.

alter table public.profiles add column if not exists song_credits integer not null default 2 check (song_credits >= 0); -- задел под оплату

create table if not exists public.songs (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 80),
  artist text check (char_length(artist) <= 80),
  phrases jsonb not null check (jsonb_typeof(phrases) = 'array' and pg_column_size(phrases) < 30000),
  tempo integer not null default 100 check (tempo between 40 and 240),
  source text not null default 'mp3' check (source in ('mp3','mic','manual','ai')),
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists songs_owner_idx on public.songs(owner);
create index if not exists songs_public_idx on public.songs(is_public) where is_public;

create table if not exists public.song_ratings (
  song_id uuid not null references public.songs(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  stars integer not null check (stars between 1 and 5),
  comment text check (char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  primary key (song_id, user_id)
);
create index if not exists song_ratings_user_idx on public.song_ratings(user_id);

alter table public.songs enable row level security;
alter table public.song_ratings enable row level security;

-- Сколько песен у меня (для лимита 100 песен на человека)
create or replace function public.my_song_count() returns int
language sql stable security definer set search_path = public as $fn$
  select count(*)::int from public.songs where owner = auth.uid()
$fn$;
revoke execute on function public.my_song_count() from public, anon;
grant execute on function public.my_song_count() to authenticated;

create policy "songs read" on public.songs for select to authenticated
  using (owner = (select auth.uid()) or is_public or (select public.is_admin()));
create policy "songs insert own" on public.songs for insert to authenticated
  with check (owner = (select auth.uid()) and (select public.my_song_count()) < 100);
create policy "songs update own" on public.songs for update to authenticated
  using (owner = (select auth.uid()) or (select public.is_admin()))
  with check (owner = (select auth.uid()) or (select public.is_admin()));
create policy "songs delete own" on public.songs for delete to authenticated
  using (owner = (select auth.uid()) or (select public.is_admin()));

create policy "ratings read" on public.song_ratings for select to authenticated
  using (exists (select 1 from public.songs s where s.id = song_id));
create policy "ratings insert own" on public.song_ratings for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.songs s where s.id = song_id and s.owner <> (select auth.uid())));
create policy "ratings update own" on public.song_ratings for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "ratings delete own" on public.song_ratings for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

revoke all on public.songs, public.song_ratings from anon, authenticated;
grant select, delete on public.songs to authenticated;
grant insert (title, artist, phrases, tempo, source, is_public) on public.songs to authenticated;
grant update (title, artist, phrases, tempo, is_public) on public.songs to authenticated;
grant select, delete on public.song_ratings to authenticated;
grant insert (song_id, stars, comment) on public.song_ratings to authenticated;
grant update (stars, comment) on public.song_ratings to authenticated;

-- Списки: песни (свои и открытые), отзывы к песне, рейтинг авторов
create or replace function public.song_list()
returns table (id uuid, title text, artist text, phrases jsonb, tempo int, source text, is_public boolean, created_at timestamptz,
               author text, is_mine boolean, avg_stars numeric, votes int, my_stars int)
language sql stable security definer set search_path = public as $fn$
  select s.id, s.title, s.artist, s.phrases, s.tempo, s.source, s.is_public, s.created_at,
         p.name, s.owner = auth.uid(),
         round(avg(r.stars)::numeric, 1), count(r.stars)::int,
         max(case when r.user_id = auth.uid() then r.stars end)::int
  from public.songs s join public.profiles p on p.id = s.owner
  left join public.song_ratings r on r.song_id = s.id
  where auth.uid() is not null and (s.is_public or s.owner = auth.uid() or public.is_admin())
  group by s.id, p.name
  order by s.created_at desc
  limit 300
$fn$;

create or replace function public.song_reviews(sid uuid)
returns table (author text, stars int, comment text, created_at timestamptz, is_me boolean)
language sql stable security definer set search_path = public as $fn$
  select p.name, r.stars, r.comment, r.created_at, r.user_id = auth.uid()
  from public.song_ratings r join public.profiles p on p.id = r.user_id
  join public.songs s on s.id = r.song_id
  where r.song_id = sid and auth.uid() is not null and (s.is_public or s.owner = auth.uid() or public.is_admin())
  order by r.created_at desc
  limit 100
$fn$;

create or replace function public.song_authors()
returns table (author text, songs int, votes int, avg_stars numeric, score int, is_me boolean)
language sql stable security definer set search_path = public as $fn$
  select p.name, count(distinct s.id)::int, count(r.stars)::int, round(avg(r.stars)::numeric, 1),
         coalesce(sum(r.stars), 0)::int, p.id = auth.uid()
  from public.songs s join public.profiles p on p.id = s.owner
  left join public.song_ratings r on r.song_id = s.id
  where s.is_public and auth.uid() is not null
  group by p.id, p.name
  order by 5 desc, 2 desc
  limit 100
$fn$;

revoke execute on function public.song_list(), public.song_reviews(uuid), public.song_authors() from public, anon;
grant execute on function public.song_list(), public.song_reviews(uuid), public.song_authors() to authenticated;
