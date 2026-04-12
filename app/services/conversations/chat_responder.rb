module Conversations
  class ChatResponder
    def self.call(...) = new(...).call

    def initialize(conversation, user_message, assistant_message)
      @conversation     = conversation
      @persona          = conversation.persona
      @user_message     = user_message
      @assistant_message = assistant_message
    end

    def call
      chunks   = Ai::RagSearch.call(@persona.id, @user_message.body)
      messages = build_messages(chunks)

      accumulated = ""

      Ai::Client.instance.chat(
        parameters: {
          model: "gpt-4o",
          messages: messages,
          temperature: 0.7,
          stream: proc do |chunk, _|
            delta = chunk.dig("choices", 0, "delta", "content")
            next unless delta

            accumulated += delta
            broadcast(accumulated, streaming: true)
          end
        }
      )

      @assistant_message.update!(body: accumulated)
      broadcast(accumulated, streaming: false)
    rescue => e
      error_text = "Произошла ошибка. Попробуйте ещё раз."
      @assistant_message.update!(body: error_text)
      broadcast(error_text, streaming: false)
      raise
    end

    private

    def build_messages(chunks)
      system_prompt = Conversations::ContextBuilder.build_system(@persona, @user_message.mode)

      history = @conversation.messages
        .where.not(id: [ @user_message.id, @assistant_message.id ])
        .chronological
        .last(10)
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
