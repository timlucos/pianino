# Пианино с нуля

Тренажёр игры на пианино: подсвечивает нужную клавишу, слушает микрофон (или пианино по USB) и переходит к следующей ноте.

- `index.html` — всё приложение (51 урок и песня, 6 шагов курса, рейтинг, админка)
- `config.js` — адрес и публичный ключ Supabase (аккаунты и база)
- `schema.sql` — таблицы, правила доступа, рейтинг и функция для админки

## Запуск сервера (Supabase, бесплатно)
1. supabase.com → New project.
2. SQL Editor → вставить `schema.sql` → Run.
3. Project Settings → API: скопировать Project URL и anon public key в `config.js`.
4. Authentication → Providers → Email: при желании выключить «Confirm email», чтобы вход был сразу.
5. После своей регистрации выполнить в SQL Editor:
   `update public.profiles set is_admin = true where email = 'твоя@почта';`

## Хостинг
GitHub Pages из ветки `main`, корень репозитория. Свой домен: файл `CNAME` с именем домена и DNS-записи на GitHub Pages.
