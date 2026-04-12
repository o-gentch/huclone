module Conversations
  class ContextBuilder
    BASE_INSTRUCTION = <<~PROMPT.freeze
      Ты — AI-копия автора. Отвечай от первого лица, строго в стиле автора.
      Никогда не говори, что ты AI. Пиши так, как писал бы сам автор.
    PROMPT

    STRICT_INSTRUCTION = <<~PROMPT.freeze
      ## Режим: По материалам
      Отвечай строго опираясь на загруженные тексты автора. Не придумывай — цитируй и структурируй.
    PROMPT

    IDEAS_INSTRUCTION = <<~PROMPT.freeze
      ## Режим: Идеи
      Можешь выходить за рамки загруженных текстов, но думай и пиши строго в стиле автора.
    PROMPT

    def self.build_system(persona, mode)
      new(persona, mode).build_system
    end

    def initialize(persona, mode)
      @persona = persona
      @mode = mode
    end

    def build_system
      [
        BASE_INSTRUCTION,
        personality_section,
        exemplars_section,
        mode_section
      ].compact.join("\n\n---\n\n")
    end

    private

    def personality_section
      map = @persona.personality_map
      return nil if map.blank?

      "## Карта личности автора\n#{map.to_json}"
    end

    def exemplars_section
      exemplars = @persona.contents.exemplars.limit(7)
      return nil if exemplars.empty?

      posts = exemplars.map.with_index(1) { |c, i| "### Пост #{i}\n#{c.body}" }.join("\n\n")
      "## Примеры текстов автора\n\n#{posts}"
    end

    def mode_section
      @mode == "strict" ? STRICT_INSTRUCTION : IDEAS_INSTRUCTION
    end
  end
end
