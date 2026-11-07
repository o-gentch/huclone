module Recordings
  # Хук после подтверждения спикера: запускает превращение речи в знания.
  module Pipeline
    class << self
      # Переопределяется в тестах
      attr_writer :after_confirm_handler

      def after_confirm(recording)
        if @after_confirm_handler
          @after_confirm_handler.call(recording)
        elsif recording.persona_speaker
          ProcessRecordingJob.perform_later(recording.id)
        end
      end
    end
  end
end
