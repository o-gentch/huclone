module Personas
  class PersonalityMapBuilder
    BATCH_SIZE = 25
    INTERMEDIATE_GROUP_SIZE = 10
    MAX_CONCURRENT = 5

    def self.call(...) = new(...).call

    def initialize(persona_id, ai_client: Ai::Client.instance)
      @persona = ::Persona.find(persona_id)
      @ai_client = ai_client
    end

    def call
      contents = Content
        .where(persona_id: @persona.id, status: "done")
        .order(:id)

      return if contents.empty?

      observations = extract_observations_in_parallel(contents)
      return if observations.empty?

      intermediate = if observations.size > INTERMEDIATE_GROUP_SIZE
        observations.each_slice(INTERMEDIATE_GROUP_SIZE).map do |group|
          synthesize_intermediate(group)
        end.compact
      else
        observations
      end

      personality_map = synthesize_personality_map(intermediate)

      @persona.update!(
        personality_map: personality_map,
        personality_map_built_at: Time.current
      )

      Personas::ExemplarSelector.call(@persona)
    end

    private

    def extract_observations_in_parallel(contents)
      pool = Concurrent::FixedThreadPool.new(MAX_CONCURRENT)
      futures = []

      # Материализуем батчи в основном потоке — DB-запросы не уходят в треды
      contents.in_batches(of: BATCH_SIZE) do |batch|
        batch_array = batch.to_a
        futures << Concurrent::Future.execute(executor: pool) do
          extract_patterns_from_batch(batch_array)
        end
      end

      futures.filter_map do |f|
        result = f.value  # блокируемся до завершения каждого
        Rails.logger.error("[PersonalityMapBuilder] batch failed: #{f.reason}") if f.rejected?
        result
      end
    ensure
      pool.shutdown
      pool.wait_for_termination(5.minutes.to_i)
    end

    def extract_patterns_from_batch(contents)
      texts = contents.map.with_index(1) { |c, i| "#{i}. #{sanitize_text(c.body)}" }.join("\n\n")

      @ai_client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: <<~PROMPT
                Ты анализируешь тексты автора. Выдели паттерны:
                - убеждения и ценности
                - повторяющиеся метафоры и образы
                - главные темы
                - особенности стиля речи (длина предложений, тон, типичные обороты, начала и концовки постов)
                - фразы-маркеры автора (signature phrases)
                - структура аргументации
                - как обращается к читателю (audience relationship)
                - как выражает эмоции (emotional range)
                - 3–5 дословных цитат из текстов (важно: дословно, без изменений)
                Отвечай кратко, по пунктам, на том же языке что и тексты.
              PROMPT
            },
            { role: "user", content: texts }
          ],
          temperature: 0.3
        }
      ).dig("choices", 0, "message", "content")
    end

    # Промежуточная свёртка нескольких строковых наблюдений в одну строку.
    # Возвращает строку (не JSON) — используется как вход для финального синтеза.
    def synthesize_intermediate(observations)
      combined = observations.each_with_index
                              .map { |o, i| "Группа #{i + 1}:\n#{o}" }
                              .join("\n\n---\n\n")

      @ai_client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: <<~PROMPT
                На основе нескольких групп наблюдений собери промежуточный портрет автора.
                Выдели повторяющиеся паттерны: убеждения, темы, стиль, метафоры.
                Verbatim-цитаты переноси дословно, не сжимай и не перефразируй.
                Отвечай кратко, по пунктам, на том же языке что и тексты.
              PROMPT
            },
            { role: "user", content: combined }
          ],
          temperature: 0.3
        }
      ).dig("choices", 0, "message", "content")
    end

    # Финальная свёртка в JSON-карту. Принимает массив строк.
    def synthesize_personality_map(observations)
      combined = observations.each_with_index
                              .map { |o, i| "Блок #{i + 1}:\n#{o}" }
                              .join("\n\n---\n\n")

      response = @ai_client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            {
              role: "system",
              content: <<~PROMPT
                На основе наблюдений собери единую карту личности автора.
                Верни строго валидный JSON следующей структуры:
                {
                  "core_beliefs": ["убеждение или ценность автора"],
                  "recurring_metaphors": ["повторяющийся образ или метафора"],
                  "main_topics": ["тема"],
                  "speech_style": {
                    "register": "тон и регистр (напр. вдохновляющий, деловой)",
                    "sentence_length": "описание (напр. длинные развёрнутые / рубленые)",
                    "typical_openers": ["типичное начало поста"],
                    "typical_closers": ["типичное завершение поста"],
                    "signature_phrases": ["фраза-маркер автора"],
                    "punctuation_habits": "особенности пунктуации (многоточия, тире, капслок)",
                    "paragraph_structure": "как строит абзац",
                    "never_says": ["слова/обороты которые автор не использует"]
                  },
                  "argument_structure": "как строит аргументацию",
                  "audience_relationship": "как обращается к читателю",
                  "emotional_range": "как выражает эмоции",
                  "what_never_writes_about": ["табуированная тема"],
                  "verbatim_examples": ["минимум 10 дословных цитат из текстов, без изменений"]
                }
                Только JSON, без пояснений.
              PROMPT
            },
            { role: "user", content: combined }
          ],
          temperature: 0.2,
          response_format: { type: "json_object" }
        }
      ).dig("choices", 0, "message", "content")

      JSON.parse(response)
    end

    def sanitize_text(text)
      text
        .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        .gsub("\u0000", "")
    end
  end
end
