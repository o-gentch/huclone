class ProcessRecordingJob < ApplicationJob
  queue_as :content_processing

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(recording_id)
    recording = Recording.find(recording_id)
    return unless recording.confirmed?

    Recordings::Ingest.call(recording)
  end
end
