-- Обновление 1: история занятий, минуты и слабые ноты для профиля.
-- Supabase → SQL Editor → New query → вставить → Run. Запускать можно повторно.
alter table public.progress add column if not exists meta jsonb not null default '{}'::jsonb;

-- Сделать себя администратором (впиши свою почту, с которой регистрировался на сайте):
-- update public.profiles set is_admin = true where email = 'твоя@почта';
