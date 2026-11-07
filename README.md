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
| `ASSEMBLYAI_API_KEY` | ключ AssemblyAI для распознавания видео (либо `credentials.assemblyai.api_key`) |
| `TRANSCRIPTION_PROVIDER` | провайдер ASR, по умолчанию `assemblyai` |
| `RECORDING_MINUTES_QUOTA` | месячная квота минут распознавания на пользователя (300) |
| `TRANSCRIPTION_MAX_CONCURRENT` | сколько записей одновременно может обрабатываться у провайдера (5) |
| `ACTIVE_STORAGE_SERVICE` | `local` (по умолчанию) или `s3` |
| `S3_BUCKET`, `S3_REGION`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_FORCE_PATH_STYLE` | параметры S3-совместимого хранилища (при `ACTIVE_STORAGE_SERVICE=s3`) |

## Пользователи

Аутентификация — Rails authentication (сессии в cookie). Публичной регистрации нет, пользователь создаётся командой:

```bash
bin/rails "users:create[you@example.com,пароль]"
```

Команда также привязывает к новому пользователю персоны без владельца (остались от версии без аккаунтов). Панель `/jobs` доступна любому вошедшему пользователю.

## Видео и аудио

Пункт «Видео»: загрузка записи (прямая загрузка из браузера) → `ExtractAudioJob` (очередь `media`, ffmpeg → mono/16 кГц/mp3 48 кбит/с, оригинал удаляется) → `TranscribeRecordingJob` (очередь `transcription`, AssemblyAI, диаризация, опрос с перепланированием) → пользователь выбирает «это я» → запись `confirmed`. Подключение к карте личности и поиску — отдельная задача.

- **ffmpeg/ffprobe:** в Docker-образе уже есть; локально `brew install ffmpeg`. Без них тесты извлечения аудио пропускаются.
- **Хранилище:** по умолчанию локальный диск (`storage/`), загрузка идёт через Puma, поэтому лимит файла — 500 МБ. Для продакшена с большими файлами используйте S3-совместимое хранилище (`ACTIVE_STORAGE_SERVICE=s3`, см. `config/storage.yml`): тогда лимит 2 ГБ и загрузка идёт мимо Rails (нужны CORS-правила бакета, см. `docs/SETUP_CHECKLIST.md`).
- **Доступ к файлам:** стандартные публичные ссылки Active Storage отключены; аудио отдаётся только владельцу через `RecordingsController#audio`.
- **Квоты и стоимость:** минуты распознавания считаются в `usage_events`; по умолчанию 300 мин/мес на пользователя.
- **Зависшие записи:** `StuckRecordingsWatchdogJob` раз в 10 минут перезапускает потерянные стадии.
- В тестах используется `Transcription::Fake` (JSON-фикстуры в `test/fixtures/files/transcripts`), реальные вызовы не выполняются.

## Пайплайн

1. Текст → `ProcessContentJob` → чанки (1500 симв.) → эмбеддинги батчем → `chunks` (HNSW-индекс).
2. Когда все материалы персоны обработаны → `BuildPersonalityMapJob`: лингвистика + map-reduce карта личности (инкрементальная).
3. Сообщение в чат → `ChatResponseJob`: intent + RAG параллельно → gpt-4o со стримингом через Turbo Streams.

Аудит и известные ограничения: [AUDIT.md](AUDIT.md).

## Тесты

```bash
bin/rails test
```
