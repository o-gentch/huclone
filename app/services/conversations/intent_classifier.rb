module Conversations
  class IntentClassifier
    INTENTS = %w[write_post generate_ideas structure_knowledge casual_chat answer_question].freeze

    HISTORY_LIMITS = {
      "write_post"          => 2,
      "generate_ideas"      => 4,
      "structure_knowledge" => 8,
      "answer_question"     => 8,
      "casual_chat"         => 6
    }.freeze

    def self.call(message_body) = new(message_body).call

    def initialize(message_body)
      @message_body = message_body
    end

    def call
      response = Ai::Client.instance.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: <<~PROMPT
                Определи тип запроса. Верни строго одно слово из списка ниже — без пояснений, без кавычек.

                write_post           — просит написать пост, текст, публикацию, историю
                generate_ideas       — просит идеи, темы, варианты для чего угодно (посты, курс, книга, путешествие и т.д.)
                structure_knowledge  — просит структурировать, систематизировать, оглавление, mind map
                casual_chat          — приветствие, small talk, личные вопросы ("как дела", "расскажи о себе")
                answer_question      — любой другой вопрос, анализ, объяснение

                Только одно слово.
              PROMPT
            },
            { role: "user", content: @message_body }
          ],
          temperature: 0,
          max_tokens: 10
        }
      )

      result = response.dig("choices", 0, "message", "content").to_s.strip.downcase
      INTENTS.include?(result) ? result : "answer_question"
    rescue => e
      Rails.logger.error("[IntentClassifier] failed: #{e.message}")
      "answer_question"
    end
  end
end
