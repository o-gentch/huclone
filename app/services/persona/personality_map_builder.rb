module Persona
  class PersonalityMapBuilder
    BATCH_SIZE = 25

    def self.call(...) = new(...).call

    def initialize(persona_id, ai_client: AI::Client.instance)
      @persona = ::Persona.find(persona_id)
      @ai_client = ai_client
    end

    def call
      chunks = Chunk.joins(content: :persona)
                    .where(contents: { persona_id: @persona.id, status: "done" })
                    .order(:id)

      return if chunks.empty?

      batch_observations = chunks.each_slice(BATCH_SIZE).map do |batch|
        extract_patterns_from_batch(batch)
      end

      personality_map = synthesize_personality_map(batch_observations)

      @persona.update!(
        personality_map: personality_map,
        personality_map_built_at: Time.current
      )

      Persona::ExemplarSelector.call(@persona)
    end

    private

    def extract_patterns_from_batch(chunks)
      texts = chunks.map.with_index(1) { |c, i| "#{i}. #{c.text}" }.join("\n\n")

      @ai_client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            {
              role: "system",
              content: <<~PROMPT
                Ты анализируешь тексты автора. Выдели паттерны:
                - убеждения и ценности
                - повторяющиеся метафоры и образы
                - главные темы
                - особенности стиля речи (длина предложений, тон, типичные обороты)
                - структура аргументации
                Отвечай кратко, по пунктам, на том же языке что и тексты.
              PROMPT
            },
            { role: "user", content: texts }
          ],
          temperature: 0.3
        }
      ).dig("choices", 0, "message", "content")
    end

    def synthesize_personality_map(observations)
      combined = observations.each_with_index.map { |o, i| "Батч #{i + 1}:\n#{o}" }.join("\n\n---\n\n")

      existing = @persona.personality_map.presence

      response = @ai_client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            {
              role: "system",
              content: <<~PROMPT
                На основе наблюдений из нескольких батчей собери единую карту личности автора.
                Верни строго валидный JSON следующей структуры:
                {
                  "core_beliefs": ["..."],
                  "recurring_metaphors": ["..."],
                  "main_topics": ["..."],
                  "speech_style": {
                    "sentence_length": "...",
                    "register": "...",
                    "typical_openers": ["..."],
                    "never_says": ["..."]
                  },
                  "argument_structure": "...",
                  "verbatim_examples": ["..."]
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
