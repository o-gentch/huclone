module Conversations
  class ContextBuilder
    BASE_INSTRUCTION = <<~PROMPT.freeze
      Ты — AI-копия автора. Говори от первого лица, думай и рассуждай как автор.
      Никогда не говори, что ты AI. Никогда не повторяй структуру или формулировки предыдущих ответов в этом диалоге.

      Формат ответа определяется запросом:
      - Просят написать пост → пиши пост в стиле автора
      - Просят идеи или список → отвечай списком, коротко и конкретно, не пиши сами посты
      - Просят структурировать → заголовки и подпункты, без лирики
      - Задают вопрос → отвечай по существу, разговорно
      - Small talk → коротко и по-человечески
    PROMPT

    STRICT_INSTRUCTION = <<~PROMPT.freeze
      ## Режим: По материалам
      Отвечай строго опираясь на загруженные тексты автора. Не придумывай — цитируй и структурируй.
    PROMPT

    IDEAS_INSTRUCTION = <<~PROMPT.freeze
      ## Режим: Идеи
      Можешь выходить за рамки загруженных текстов, но думай и пиши строго в стиле автора.
    PROMPT

    EXEMPLAR_MAX_CHARS = 3_000

    INTENT_INSTRUCTIONS = {
      "write_post" => <<~PROMPT,
        ## Задача: написать пост
        Напиши пост в полном стиле автора. Используй примеры текстов ниже как образец голоса и формата.
      PROMPT
      "generate_ideas" => <<~PROMPT,
        ## Задача: идеи
        Предложи идеи нумерованным списком под конкретный запрос (посты, курс, книга, путешествие — что бы ни спросили).
        Для каждой идеи — одно-два предложения, конкретно и по существу.
        Не пиши готовые тексты — только идеи. Думай в духе автора: его темы, углы, ценности.
      PROMPT
      "structure_knowledge" => <<~PROMPT,
        ## Задача: структурировать знания
        Выдели ключевые темы и подтемы из материалов автора.
        Отвечай структурированно: заголовки, подпункты. Не пиши как пост.
      PROMPT
      "casual_chat" => <<~PROMPT,
        ## Задача: диалог
        Отвечай коротко и по-человечески, в голосе автора. Это разговор, не публикация.
      PROMPT
      "book" => <<~PROMPT,
        ## Задача: книга
        Ты помогаешь автору собрать книгу из его выступлений. Опирайся на дерево тем (оглавление) и фрагменты ниже.
        Оглавление — иерархический нумерованный список глав и подглав с краткой аннотацией каждой.
        Раскрытие главы — связный текст в голосе автора строго по приведённым фрагментам.
        Не придумывай то, чего нет в материалах; ссылайся на источники: (из выступления «…», 12:30).
      PROMPT
      "answer_question" => <<~PROMPT
        ## Задача: ответить на вопрос
        Отвечай по существу, в голосе автора. Формат — ответ, не пост.
      PROMPT
    }.freeze

    def self.build_system(persona, mode, intent = "answer_question")
      new(persona, mode, intent).build_system
    end

    def initialize(persona, mode, intent = "answer_question")
      @persona = persona
      @mode    = mode
      @intent  = intent
    end

    def build_system
      [
        BASE_INSTRUCTION,
        instructions_section,
        personality_section,
        linguistics_section,
        exemplars_section,
        mode_section,
        intent_section
      ].compact.join("\n\n---\n\n")
    end

    private

    SPOKEN_INSTRUCTION = <<~PROMPT.freeze
      ## Голос: устная речь
      Отвечай так, как автор говорит вслух: используй раздел spoken_style карты (обороты, манеру объяснять, юмор)
      и устные цитаты. Письменные штампы постов не переноси.
    PROMPT

    WRITTEN_INSTRUCTION = <<~PROMPT.freeze
      ## Голос: письменный
      Пиши письменным голосом автора — по его постам. Манеру устной речи (spoken_style, разговорные цитаты) не используй.
    PROMPT

    # Выбор голоса по intent: write_post — письменный, остальное — с учётом устного стиля
    def personality_section
      map = @persona.personality_map
      return nil if map.blank?

      map = Personas::PersonalityMapBuilder.normalize_map(map)
      if written_voice?
        map = map.except("spoken_style")
        map["verbatim_examples"] = map["verbatim_examples"].select { |e| e["source"] == "post" }
      end

      voice = written_voice? ? WRITTEN_INSTRUCTION : (SPOKEN_INSTRUCTION if map["spoken_style"].present?)
      [ "## Карта личности автора\n#{map.to_json}", voice ].compact.join("\n\n")
    end

    def instructions_section
      text = @persona.system_prompt.to_s.strip
      "## Инструкции владельца (роль и поведение)\n#{text.truncate(2_000)}" if text.present?
    end

    def written_voice? = @intent == "write_post"

    def linguistics_section
      l = @persona.linguistics
      return nil if l.blank?

      top = (l["top_words"] || {}).keys.first(20).join(", ")
      lines = [
        "Средняя длина предложения: #{l["avg_sentence_words"]} слов (медиана #{l["median_sentence_words"]})",
        "Короткие предложения (<8 слов): #{l["short_sentences_pct"]}%, длинные (>20): #{l["long_sentences_pct"]}%",
        "Средняя длина поста: #{l["avg_post_words"]} слов, абзацев в посте: #{l["avg_paragraphs_per_post"]}",
        "Эмодзи: #{l["emoji_usage"]}",
        "Восклицаний на 100 предложений: #{l["exclamation_pct"]}, вопросов: #{l["question_pct"]}, многоточий: #{l["ellipsis_pct"]}",
        ("Частые слова: #{top}" if top.present?)
      ].compact

      "## Количественные характеристики стиля\n#{lines.join("\n")}"
    end

    def exemplars_section
      return nil unless @intent == "write_post"

      exemplars = @persona.contents.posts.merge(PersonaContent.exemplars).limit(3)
      return nil if exemplars.empty?

      posts = exemplars.map.with_index(1) { |c, i| "### Пост #{i}\n#{c.body.truncate(EXEMPLAR_MAX_CHARS)}" }.join("\n\n")
      "## Примеры постов автора\n\n#{posts}"
    end

    def mode_section
      @mode == "ideas" ? IDEAS_INSTRUCTION : STRICT_INSTRUCTION
    end

    def intent_section
      INTENT_INSTRUCTIONS[@intent]
    end
  end
end
