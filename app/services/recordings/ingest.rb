module Recordings
  # Речь одного спикера → Content(kind: speech) на каждый ход диалога.
  # Идемпотентно: повторный запуск заменяет прежние фрагменты этого спикера.
  class Ingest
    MAX_CONCURRENT = 4

    def self.call(...) = new(...).call

    def initialize(recording, speaker:, ai_client: Ai::Client.instance)
      @recording = recording
      @speaker = speaker
      @ai_client = ai_client
    end

    def call
      turns = TurnBuilder.call(@recording, speaker: @speaker)
      cleaned = clean_all(turns)
      now = Time.current

      contents = Content.transaction do
        Content.where(recording_id: @recording.id, speaker_id: @speaker.id).destroy_all
        turns.each_with_index.map do |turn, i|
          Content.create!(
            user_id: @recording.user_id, kind: "speech", recording: @recording, speaker: @speaker, status: "pending",
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
