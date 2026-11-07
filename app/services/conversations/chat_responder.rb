module Conversations
  class ChatResponder
    BROADCAST_INTERVAL = 0.08

    ERROR_TEXT = "Произошла ошибка. Попробуйте ещё раз.".freeze

    def self.call(...) = new(...).call

    def self.show_error_for(assistant_message)
      assistant_message.update!(body: ERROR_TEXT)
      Turbo::StreamsChannel.broadcast_update_to(
        assistant_message.conversation,
        target: "message_#{assistant_message.id}_body",
        html: "<p class=\"mb-2 last:mb-0\">#{ERROR_TEXT}</p>"
      )
    end

    def initialize(conversation, user_message, assistant_message)
      @conversation      = conversation
      @persona           = conversation.persona
      @user_message      = user_message
      @assistant_message = assistant_message
    end

    def call
      # Классификация и поиск по эмбеддингам независимы — запускаем параллельно
      intent_thread = Thread.new { Conversations::IntentClassifier.call(@user_message.body) }
      chunks = Ai::RagSearch.call(@persona.id, @user_message.body).to_a
      intent = intent_thread.value
      messages = build_messages(chunks, intent)

      accumulated = ""
      last_broadcast = 0.0

      Ai::Client.instance.chat(
        parameters: {
          model: "gpt-4o",
          messages: messages,
          temperature: 0.7,
          stream: proc do |chunk, _|
            delta = chunk.dig("choices", 0, "delta", "content")
            next unless delta

            accumulated += delta

            # Не чаще раза в BROADCAST_INTERVAL, иначе каждый токен = запись в Solid Cable
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if now - last_broadcast >= BROADCAST_INTERVAL
              broadcast(accumulated, streaming: true)
              last_broadcast = now
            end
          end
        }
      )

      @assistant_message.update!(body: accumulated)
      broadcast(accumulated, streaming: false)
    rescue OpenAI::Error, Faraday::Error
      # Временный сбой API — отдаём управление ретраю джоба, UI остаётся в состоянии «печатает»
      raise
    rescue => e
      Rails.logger.error("[ChatResponder] #{e.class}: #{e.message}")
      self.class.show_error_for(@assistant_message)
    end

    private

    def build_messages(chunks, intent)
      system_prompt = Conversations::ContextBuilder.build_system(@persona, @user_message.mode, intent)
      history_limit = Conversations::IntentClassifier::HISTORY_LIMITS.fetch(intent, 6)

      history = @conversation.messages
        .where.not(id: [ @user_message.id, @assistant_message.id ])
        .chronological
        .last(history_limit)
        .map { |m| { role: m.role, content: m.body } }

      user_content = @user_message.body
      if chunks.any?
        rag_context = chunks.map.with_index(1) { |c, i| "Фрагмент #{i}:\n#{c.text}" }.join("\n\n")
        user_content = "#{user_content}\n\n---\nРелевантные фрагменты из текстов автора:\n#{rag_context}"
      end

      [
        { role: "system", content: system_prompt },
        *history,
        { role: "user", content: user_content }
      ]
    end

    def broadcast(text, streaming:)
      Turbo::StreamsChannel.broadcast_update_to(
        @conversation,
        target: "message_#{@assistant_message.id}_body",
        html: render_body(text, streaming: streaming)
      )
    end

    def render_body(text, streaming:)
      paragraphs = text.gsub(/\r\n?/, "\n")
        .split("\n\n")
        .map { |para| "<p class=\"mb-2 last:mb-0\">#{CGI.escapeHTML(para).gsub("\n", "<br>")}</p>" }
        .join

      return paragraphs unless streaming

      paragraphs + "<span class=\"inline-block w-1 h-4 bg-gray-400 animate-pulse ml-0.5 rounded-sm align-middle\"></span>"
    end
  end
end
