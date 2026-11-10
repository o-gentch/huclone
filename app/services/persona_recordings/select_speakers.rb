module PersonaRecordings
  # Выбор спикеров для пары DD–запись. speaker_ids пусто — «этого человека в записи нет».
  # Речь спикера обрабатывается один раз (при первом выборе любым DD), дальше переиспользуется.
  class SelectSpeakers
    class Invalid < StandardError; end

    def self.call(...) = new(...).call

    def initialize(persona_recording, speaker_ids:, names: {})
      @pr = persona_recording
      @speaker_ids = Array(speaker_ids).reject(&:blank?).map(&:to_i).uniq.sort
      @names = names || {}
    end

    def call
      recording = @pr.recording
      raise Invalid, "Запись ещё не расшифрована" unless recording.transcribed?

      speakers = recording.speakers.to_a
      raise Invalid, "Спикер не найден" unless (@speaker_ids - speakers.map(&:id)).empty?

      PersonaRecording.transaction do
        @pr.lock!
        speakers.each do |s|
          name = @names[s.id.to_s].to_s.squish.first(60).presence
          s.update!(display_name: name) if @names.key?(s.id.to_s)
        end
        @pr.update!(speaker_ids: @speaker_ids, status: "ready")
      end

      speakers.select { |s| @speaker_ids.include?(s.id) }.each { |s| Recordings::SpeakerSpeech.request!(s) }
      Sync.call(@pr)
      @pr
    end
  end
end
