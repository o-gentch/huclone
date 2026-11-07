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
        personality_section,
        linguistics_section,
        exemplars_section,
        mode_section,
        intent_section
      ].compact.join("\n\n---\n\n")
    end

    private

    def personality_section
      map = @persona.personality_map
      return nil if map.blank?

      "## Карта личности автора\n#{map.to_json}"
    end

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

      exemplars = @persona.contents.exemplars.limit(3)
      return nil if exemplars.empty?

      posts = exemplars.map.with_index(1) { |c, i| "### Пост #{i}\n#{c.body.truncate(EXEMPLAR_MAX_CHARS)}" }.join("\n\n")
      "## Примеры постов автора\n\n#{posts}"
    end

    def mode_section
      @mode == "strict" ? STRICT_INSTRUCTION : IDEAS_INSTRUCTION
    end

    def intent_section
      INTENT_INSTRUCTIONS[@intent]
    end
  end
end
