module Knowledge
  class SummarizeRecordingJob < ApplicationJob
    queue_as :personality_map

    limits_concurrency to: 1, key: ->(recording_id) { "summarize_recording/#{recording_id}" }, duration: 30.minutes

    retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 5
    retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    def perform(recording_id)
      recording = Recording.find(recording_id)
      Knowledge::RecordingSummarizer.call(recording)
      Knowledge::BuildTopicTreeJob.perform_later(recording.persona_id)
    end
  end
end
