module Personas
  class PersonalityMapBuilder
    BATCH_SIZE = 25
    INTERMEDIATE_GROUP_SIZE = 10

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

      observations = [].tap do |obs|
        contents.in_batches(of: BATCH_SIZE) do |batch|
          result = extract_patterns_from_batch(batch.to_a)
          obs << result if result.present?
        end
      end

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

    def extract_patterns_from_batch(contents)
      texts = contents.map.with_index(1) { |c, i| "#{i}. #{c.body}" }.join("\n\n")

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
  end
end
