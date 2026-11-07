module Recordings
  # Подтверждение спикера. speaker_id = nil — «меня нет в этой записи».
  class Confirm
    class Invalid < StandardError; end

    def self.call(...) = new(...).call

    def initialize(recording, speaker_id:, names: {})
      @recording = recording
      @speaker_id = speaker_id.presence
      @names = names || {}
    end

    def call
      raise Invalid, "Запись не ожидает подтверждения" unless @recording.awaiting_speaker_confirmation?

      Recording.transaction do
        speakers = @recording.speakers.to_a
        if @speaker_id && speakers.none? { |s| s.id.to_s == @speaker_id.to_s }
          raise Invalid, "Спикер не найден"
        end

        speakers.each do |s|
          name = @names[s.id.to_s].to_s.squish.first(60).presence
          s.update!(display_name: name, is_persona: s.id.to_s == @speaker_id.to_s)
        end
        @recording.advance!("confirmed")
      end

      Pipeline.after_confirm(@recording)
      @recording
    end
  end
end
