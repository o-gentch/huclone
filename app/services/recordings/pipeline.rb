module Recordings
  # Хук после подтверждения спикера. В Задаче 2 здесь запускается ProcessRecordingJob.
  module Pipeline
    class << self
      attr_writer :after_confirm_handler

      def after_confirm(recording)
        @after_confirm_handler&.call(recording)
      end
    end
  end
end
