class PersonalityMapBuilder
  BATCH_SIZE = 25

  def self.build(persona_id)
    persona = Persona.find(persona_id)
    chunks = Chunk.joins(content: :persona)
                  .where(contents: { persona_id: persona_id, status: "done" })
                  .order(:id)

    return if chunks.empty?

    batch_observations = chunks.each_slice(BATCH_SIZE).map do |batch|
      extract_patterns_from_batch(batch)
    end

    personality_map = synthesize_personality_map(batch_observations, persona)

    persona.update!(
      personality_map: personality_map,
      personality_map_built_at: Time.current
    )

    select_exemplars(persona)
  end

  def self.extract_patterns_from_batch(chunks)
    texts = chunks.map.with_index(1) { |c, i| "#{i}. #{c.text}" }.join("\n\n")

    client.chat(
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

  def self.synthesize_personality_map(observations, persona)
    combined = observations.each_with_index.map { |o, i| "Батч #{i + 1}:\n#{o}" }.join("\n\n---\n\n")

    existing = persona.personality_map.presence

    response = client.chat(
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

  def self.select_exemplars(persona)
    done_contents = persona.contents.done.includes(:chunks)
    return if done_contents.empty?

    # pick up to 7 posts with broadest topic coverage
    exemplar_ids = done_contents
      .sort_by { |c| -c.chunks.size }
      .first(7)
      .map(&:id)

    persona.contents.where(is_exemplar: true).where.not(id: exemplar_ids).update_all(is_exemplar: false)
    persona.contents.where(id: exemplar_ids).update_all(is_exemplar: true)
  end

  def self.client
    @client ||= OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
  end
end
