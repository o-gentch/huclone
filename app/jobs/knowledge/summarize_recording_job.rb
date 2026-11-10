module Knowledge
  class SummarizeRecordingJob < ApplicationJob
    queue_as :personality_map

    limits_concurrency to: 1, key: ->(persona_recording_id) { "summarize_recording/#{persona_recording_id}" }, duration: 30.minutes

    retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 5
    retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    def perform(persona_recording_id)
      pr = PersonaRecording.find(persona_recording_id)
      return if pr.summary.present?

      Knowledge::RecordingSummarizer.call(pr)
      Knowledge::BuildTopicTreeJob.perform_later(pr.persona_id)
    end
  end
end
