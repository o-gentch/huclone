module Knowledge
  # Резюме по фрагментам записи (map) → резюме записи (reduce). Модель дешёвая, всё идёт пачками.
  class RecordingSummarizer
    MODEL = "gpt-4o-mini"
    MAX_CONCURRENT = 4
    REDUCE_GROUP = 40
    MAX_INPUT_CHARS = 6_000

    def self.call(...) = new(...).call

    def initialize(persona_recording, ai_client: Ai::Client.instance)
      @persona_recording = persona_recording
      @recording = persona_recording.recording
      @client = ai_client
    end

    def call
      contents = @persona_recording.contents.speeches.done.order(:start_ms).to_a
      return if contents.empty?

      summarize_contents(contents.select { |c| c.summary.blank? })
      summaries = contents.map { |c| c.reload.summary }.compact_blank
      return if summaries.empty?

      @persona_recording.update!(summary: reduce(summaries))
    end

    private

    def summarize_contents(contents)
      pool = Concurrent::FixedThreadPool.new(MAX_CONCURRENT)
      futures = contents.map do |content|
        Concurrent::Future.execute(executor: pool) do
          ActiveRecord::Base.connection_pool.with_connection do
            text = Ai::Chat.call(
              stage: "content_summary", client: @client, model: MODEL, temperature: 0.2,
              messages: [
                { role: "system", content: "Сделай резюме фрагмента выступления в 2–3 предложениях: о чём говорит автор и главная мысль. Только факты из текста, на русском." },
                { role: "user", content: [ content.context_text.presence && "Вопрос: #{content.context_text}", content.body.truncate(MAX_INPUT_CHARS) ].compact.join("\n\n") }
              ]
            ).strip
            content.update!(summary: text) if text.present?
          end
        end
      end
      futures.each(&:value)
      futures.each { |f| raise f.reason if f.rejected? }
    ensure
      pool&.shutdown
      pool&.wait_for_termination(10.minutes.to_i)
    end

    def reduce(summaries)
      while summaries.size > 1
        groups = summaries.each_slice(REDUCE_GROUP).to_a
        summaries = groups.map { |g| reduce_group(g) }
        break if groups.size == 1
      end
      summaries.first
    end

    def reduce_group(group)
      return group.first if group.size == 1

      Ai::Chat.call(
        stage: "recording_summary", client: @client, model: MODEL, temperature: 0.2,
        messages: [
          { role: "system", content: "Объедини резюме частей выступления «#{@recording.title}» в одно связное резюме (5–8 предложений): основные темы и выводы автора. Только факты из резюме." },
          { role: "user", content: group.each_with_index.map { |s, i| "#{i + 1}. #{s}" }.join("\n") }
        ]
      ).strip
    end
  end
end
