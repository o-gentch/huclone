module Personas
  class PersonalityMapBuilder
    class InvalidMapError < StandardError; end

    BATCH_SIZE = 25
    MAX_BATCH_CHARS = 60_000 # речевые фрагменты крупнее постов — батчим по объёму текста
    INTERMEDIATE_GROUP_SIZE = 10
    MAX_CONCURRENT = 5

    def self.call(...) = new(...).call

    def initialize(persona_id, ai_client: Ai::Client.instance)
      @persona = ::Persona.find(persona_id)
      @ai_client = ai_client
    end

    def call
      all_done     = @persona.contents.merge(PersonaContent.voice).where(status: "done").order(:id)
      new_contents = all_done.merge(PersonaContent.not_in_map)

      return if all_done.empty?
      return if new_contents.empty? && @persona.personality_map.present?

      if @persona.personality_map.blank?
        full_build(all_done)
      else
        delta_build(new_contents)
      end
    end

    private

    def full_build(contents)
      observations, covered_ids = extract_observations_in_parallel(contents)
      return if observations.empty?

      intermediate = collapse_intermediates(observations)
      personality_map = synthesize_personality_map(intermediate)

      @persona.update!(
        personality_map: personality_map,
        personality_map_built_at: Time.current
      )
      @persona.persona_contents.where(content_id: covered_ids).update_all(included_in_map: true)

      Personas::ExemplarSelector.call(@persona)
    end

    def delta_build(new_contents)
      new_observations, covered_ids = extract_observations_in_parallel(new_contents)
      return if new_observations.empty?

      intermediate = collapse_intermediates(new_observations)
      personality_map = merge_with_existing_map(intermediate)

      @persona.update!(
        personality_map: personality_map,
        personality_map_built_at: Time.current
      )
      @persona.persona_contents.where(content_id: covered_ids).update_all(included_in_map: true)

      Personas::ExemplarSelector.call(@persona)
    end

    def collapse_intermediates(observations)
      return observations if observations.size <= INTERMEDIATE_GROUP_SIZE

      observations.each_slice(INTERMEDIATE_GROUP_SIZE).map do |group|
        synthesize_intermediate(group)
      end.compact
    end

    # Возвращает [observations, covered_content_ids]; упавшие батчи не попадают
    # в covered_ids и будут обработаны при следующей сборке.
    def extract_observations_in_parallel(contents)
      pool = Concurrent::FixedThreadPool.new(MAX_CONCURRENT)
      futures = []

      self.class.size_batches(contents).each do |batch_array|
        future = Concurrent::Future.execute(executor: pool) do
          ActiveRecord::Base.connection_pool.with_connection { extract_patterns_from_batch(batch_array) }
        end
        futures << [ batch_array.map(&:id), future ]
      end

      observations = []
      covered_ids  = []
      futures.each do |ids, future|
        result = future.value
        if future.rejected? || result.blank?
          Rails.logger.error("[PersonalityMapBuilder] batch failed: #{future.reason}")
        else
          observations << result
          covered_ids.concat(ids)
        end
      end

      [ observations, covered_ids ]
    ensure
      pool.shutdown
      pool.wait_for_termination(5.minutes.to_i)
    end

    # Батчи ограничены и числом материалов, и суммарным объёмом текста
    def self.size_batches(contents, max_items: BATCH_SIZE, max_chars: MAX_BATCH_CHARS)
      batches = [ [] ]
      chars = 0
      contents.each do |content|
        size = content.style_text.to_s.length + content.context_text.to_s.length
        if batches.last.any? && (batches.last.size >= max_items || chars + size > max_chars)
          batches << []
          chars = 0
        end
        batches.last << content
        chars += size
      end
      batches.reject(&:empty?)
    end

    def format_for_extraction(content, index)
      text = sanitize_text(content.style_text.to_s.dup)
      return "#{index}. #{text}" unless content.speech?

      question = content.context_text.present? ? "Вопрос собеседника (только контекст, его стиль не анализируй): #{content.context_text}\n" : ""
      "#{index}. [УСТНАЯ РЕЧЬ автора]\n#{question}Ответ автора: #{text}"
    end

    def extract_patterns_from_batch(contents)
      texts = contents.map.with_index(1) { |c, i| format_for_extraction(c, i) }.join("\n\n")

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
                Часть материалов может быть помечена [УСТНАЯ РЕЧЬ] — это расшифровка выступлений. Для неё отдельно выдели:
                любимые разговорные обороты, как автор объясняет сложное, юмор, реакции на аудиторию, структуру ответа
                на вопрос, слова-паразиты. Цитаты из устной речи помечай «(речь)», из текстов — «(пост)».
                Отвечай кратко, по пунктам, на том же языке что и тексты.
              PROMPT
            },
            { role: "user", content: texts }
          ],
          temperature: 0.3
        }
      ).dig("choices", 0, "message", "content")
    end

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

    def synthesize_personality_map(observations)
      combined = observations.each_with_index
                              .map { |o, i| "Блок #{i + 1}:\n#{o}" }
                              .join("\n\n---\n\n")

      response = @ai_client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            { role: "system", content: personality_map_schema_prompt },
            { role: "user", content: combined }
          ],
          temperature: 0.2,
          response_format: { type: "json_object" }
        }
      ).dig("choices", 0, "message", "content")

      parse_map!(response)
    end

    # Merges an existing personality_map with observations from newly added content.
    # Sends the current map as JSON + new observations, asks GPT to produce an updated map.
    def merge_with_existing_map(new_observations)
      new_combined = new_observations.each_with_index
                                     .map { |o, i| "Блок #{i + 1}:\n#{o}" }
                                     .join("\n\n---\n\n")

      response = @ai_client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            {
              role: "system",
              content: <<~PROMPT
                У автора уже есть карта личности, построенная по предыдущим текстам.
                Ниже — новые наблюдения из недавно добавленных текстов.

                Обнови карту: добавь новые паттерны, уточни существующие, не теряй старое.
                Если новые наблюдения противоречат старым — сохрани оба варианта.
                Verbatim-цитаты из обеих частей переноси дословно.

                #{personality_map_schema_prompt}
              PROMPT
            },
            {
              role: "user",
              content: "## Существующая карта:\n#{@persona.personality_map.to_json}\n\n---\n\n## Новые наблюдения:\n#{new_combined}"
            }
          ],
          temperature: 0.2,
          response_format: { type: "json_object" }
        }
      ).dig("choices", 0, "message", "content")

      parse_map!(response)
    end

    REQUIRED_MAP_KEYS = %w[core_beliefs main_topics speech_style verbatim_examples].freeze

    def parse_map!(response)
      map = JSON.parse(response)
      missing = REQUIRED_MAP_KEYS - map.keys
      raise InvalidMapError, "missing keys: #{missing.join(", ")}" if missing.any?

      self.class.normalize_map(map)
    end

    # Обратная совместимость: старые карты хранили цитаты строками и не имели spoken_style
    def self.normalize_map(map)
      map = map.deep_dup
      map["verbatim_examples"] = Array(map["verbatim_examples"]).filter_map do |ex|
        if ex.is_a?(Hash)
          text = ex["text"].to_s
          { "text" => text, "source" => %w[post speech].include?(ex["source"]) ? ex["source"] : "post" } if text.present?
        elsif ex.present?
          { "text" => ex.to_s, "source" => "post" }
        end
      end
      map["spoken_style"] = {} unless map["spoken_style"].is_a?(Hash)
      map
    end

    def personality_map_schema_prompt
      <<~PROMPT
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
          "spoken_style": {
            "filler_habits": "слова-паразиты и как автор их использует",
            "explanation_patterns": ["как автор объясняет сложное: примеры, аналогии, структура"],
            "typical_phrases": ["любимые разговорные обороты"],
            "humor": "какой юмор и как шутит",
            "audience_interaction": "как реагирует на слушателей и вопросы"
          },
          "verbatim_examples": [{"text": "дословная цитата без изменений", "source": "post или speech"}]
        }
        verbatim_examples — минимум 10 цитат; source = "speech" для цитат из устной речи, "post" для письменных.
        Если устной речи в наблюдениях нет — spoken_style оставь пустым объектом {}; если есть — заполни.
        Только JSON, без пояснений.
      PROMPT
    end

    def sanitize_text(text)
      text
        .force_encoding("UTF-8")
        .scrub("")
        .gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD]/, "")
    end
  end
end
