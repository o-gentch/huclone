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
      intent_thread = Thread.new { classify_intent }
      first_pass = Ai::RagSearch.call(@persona.id, @user_message.body).to_a
      intent = intent_thread.value
      chunks, outline = gather_context(intent, first_pass)
      messages = build_messages(chunks, intent, outline)

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

      sources = unique_sources(chunks)
      @assistant_message.update!(body: accumulated, sources: sources)
      broadcast(accumulated, streaming: false)
      broadcast_sources
    rescue OpenAI::Error, Faraday::Error
      # Временный сбой API — отдаём управление ретраю джоба, UI остаётся в состоянии «печатает»
      raise
    rescue => e
      Rails.logger.error("[ChatResponder] #{e.class}: #{e.message}")
      self.class.show_error_for(@assistant_message)
    end

    private

    def classify_intent
      return "book" if @user_message.mode == "book"

      Conversations::IntentClassifier.call(@user_message.body)
    end

    # Для структурных запросов берём больше фрагментов; режим «книга» идёт через дерево тем.
    # Возвращает [chunks, outline_text]
    def gather_context(intent, first_pass)
      if intent == "book"
        ctx = Knowledge::BookContext.call(@persona, @user_message.body)
        return [ ctx.chunks, ctx.outline ] if ctx.outline.present?
      end

      top_k = Ai::RagSearch.top_k_for(intent)
      chunks = top_k > Ai::RagSearch::TOP_K ? Ai::RagSearch.call(@persona.id, @user_message.body, top_k: top_k).to_a : first_pass
      [ Ai::RagSearch.within_budget(chunks), nil ]
    end

    def unique_sources(chunks)
      chunks.map(&:source_reference).uniq { |s| [ s["recording_id"], s["content_id"], s["start_ms"] ] }
    end

    def build_messages(chunks, intent, outline = nil)
      system_prompt = Conversations::ContextBuilder.build_system(@persona, @user_message.mode, intent)
      history_limit = Conversations::IntentClassifier::HISTORY_LIMITS.fetch(intent, 6)

      history = @conversation.messages
        .where.not(id: [ @user_message.id, @assistant_message.id ])
        .chronological
        .last(history_limit)
        .map { |m| { role: m.role, content: m.body } }
      history = trim_history(history)

      user_content = @user_message.body
      user_content = "#{user_content}\n\n---\nСтруктура материалов автора (дерево тем):\n#{outline}" if outline.present?
      if chunks.any?
        rag_context = chunks.map.with_index(1) { |c, i| format_chunk(c, i) }.join("\n\n")
        user_content = "#{user_content}\n\n---\nРелевантные фрагменты из материалов автора " \
                       "(ссылайся на источник в скобках, например «(из выступления «…», 12:30)», когда опираешься на фрагмент):\n#{rag_context}"
      end

      log_prompt_size(system_prompt, history, user_content)
      [
        { role: "system", content: system_prompt },
        *history,
        { role: "user", content: user_content }
      ]
    end

    HISTORY_MAX_CHARS = 8_000

    # Бюджет промпта: история обрезается с начала
    def trim_history(history)
      total = 0
      kept = history.reverse.take_while { |m| (total += m[:content].to_s.length) <= HISTORY_MAX_CHARS }
      kept.reverse
    end

    def format_chunk(chunk, index)
      header = "Фрагмент #{index} [#{chunk.source_label}]"
      question = chunk.content.speech? && chunk.content.context_text.present? ? "Вопрос собеседника: #{chunk.content.context_text}\nОтвет автора: " : ""
      "#{header}:\n#{question}#{chunk.text}"
    end

    def log_prompt_size(system_prompt, history, user_content)
      Rails.logger.info("[ChatResponder] prompt_chars system=#{system_prompt.length} " \
                        "history=#{history.sum { |m| m[:content].to_s.length }} user=#{user_content.length}")
    end

    def broadcast_sources
      html = ApplicationController.render(partial: "conversations/sources", locals: { message: @assistant_message, persona: @persona })
      Turbo::StreamsChannel.broadcast_update_to(@conversation, target: "message_#{@assistant_message.id}_sources", html: html)
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
