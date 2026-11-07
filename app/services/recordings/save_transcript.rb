module Recordings
  # Сохраняет нормализованную расшифровку. Повторный вызов пересоздаёт данные, не дублирует.
  class SaveTranscript
    def self.call(...) = new(...).call

    def initialize(recording, result)
      @recording = recording
      @result = result
    end

    def call
      utterances = Transcription::Normalizer.call(@result.utterances)
      raise Transcription::PermanentError, "В записи не найдено речи" if utterances.empty?

      now = Time.current
      Recording.transaction do
        @recording.utterances.delete_all
        @recording.speakers.delete_all

        speakers = utterances.group_by { |u| u[:speaker] }.sort.map do |label, list|
          @recording.speakers.create!(
            label: label,
            speech_ms: list.sum { |u| u[:end_ms] - u[:start_ms] },
            words_count: list.sum { |u| u[:text].split.size }
          )
        end.index_by(&:label)

        rows = utterances.each_with_index.map do |u, i|
          { recording_id: @recording.id, speaker_id: speakers.fetch(u[:speaker]).id, position: i,
            start_ms: u[:start_ms], end_ms: u[:end_ms], text: u[:text], confidence: u[:confidence],
            created_at: now, updated_at: now }
        end
        Utterance.insert_all!(rows)

        @recording.update!(duration_ms: @result.duration_ms.presence || @recording.duration_ms)
        @recording.advance!("awaiting_speaker_confirmation")
      end
    end
  end
end
