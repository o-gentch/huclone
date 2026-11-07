# Huclone

AI-клон автора: загружаете свои тексты (вручную или экспортом Telegram-канала), система строит «карту личности» и количественный профиль стиля, а чат отвечает от первого лица в голосе автора, опираясь на ваши материалы (RAG).

Стек: Rails 8.1, PostgreSQL + pgvector, Solid Queue/Cable/Cache, Hotwire, Tailwind, OpenAI API.

## Запуск

```bash
bundle install
bin/rails db:prepare   # нужен PostgreSQL с расширением pgvector
bin/dev
```

## Конфигурация

| Переменная | Назначение |
|---|---|
| `OPENAI_ACCESS_TOKEN` | ключ OpenAI (либо `credentials.openai.access_token`) |
| `APP_USERNAME` / `APP_PASSWORD` | HTTP Basic для всего приложения и `/jobs`. В production без них доступ закрыт (403); в development/test открыт |

## Пайплайн

1. Текст → `ProcessContentJob` → чанки (1500 симв.) → эмбеддинги батчем → `chunks` (HNSW-индекс).
2. Когда все материалы персоны обработаны → `BuildPersonalityMapJob`: лингвистика + map-reduce карта личности (инкрементальная).
3. Сообщение в чат → `ChatResponseJob`: intent + RAG параллельно → gpt-4o со стримингом через Turbo Streams.

Аудит и известные ограничения: [AUDIT.md](AUDIT.md).

## Тесты

```bash
bin/rails test
```
