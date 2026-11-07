module Recordings
  # Подтверждённая запись → Content(kind: speech) на каждый ход диалога.
  # Идемпотентно: повторный запуск заменяет прежние материалы этой записи.
  class Ingest
    MAX_CONCURRENT = 4

    def self.call(...) = new(...).call

    def initialize(recording, ai_client: Ai::Client.instance)
      @recording = recording
      @ai_client = ai_client
    end

    def call
      turns = TurnBuilder.call(@recording)
      cleaned = clean_all(turns)
      now = Time.current

      contents = Content.transaction do
        Content.where(recording_id: @recording.id).destroy_all
        @recording.contents.reset
        turns.each_with_index.map do |turn, i|
          @recording.persona.contents.create!(
            kind: "speech", recording: @recording, status: "pending",
            title: "#{@recording.title}, #{Recording.format_ms(turn.start_ms)}",
            body: cleaned[i], raw_body: turn.text,
            context_text: turn.context_text, speaker_name: turn.speaker_name,
            start_ms: turn.start_ms, end_ms: turn.end_ms,
            sources: [ { type: "recording", recording_id: @recording.id, start_ms: turn.start_ms, end_ms: turn.end_ms } ],
            created_at: now
          )
        end
      end

      contents.each { |c| ProcessContentJob.perform_later(c.id) }
      contents
    end

    private

    def clean_all(turns)
      pool = Concurrent::FixedThreadPool.new(MAX_CONCURRENT)
      futures = turns.map do |turn|
        Concurrent::Future.execute(executor: pool) do
          ActiveRecord::Base.connection_pool.with_connection { SpeechCleaner.call(turn.text, ai_client: @ai_client) }
        end
      end
      futures.each_with_index.map { |f, i| f.value.presence || turns[i].text }
    ensure
      pool&.shutdown
      pool&.wait_for_termination(10.minutes.to_i)
    end
  end
end
