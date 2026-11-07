class ProcessContentJob < ApplicationJob
  queue_as :content_processing

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  after_discard do |job, _exception|
    content_id = job.arguments.first
    Contents::Processor.fail!(content_id)
    ProcessContentJob.signal_completion(content_id)
  end

  def perform(content_id)
    Contents::Processor.call(content_id)
    ProcessContentJob.signal_completion(content_id)
  end

  def self.signal_completion(content_id)
    content = Content.find_by(id: content_id)
    return unless content

    still_pending = Content
      .where(persona_id: content.persona_id, status: %w[pending processing])
      .exists?
    return if still_pending

    # Все фрагменты записи готовы — можно строить резюме и дерево тем
    if content.recording_id && !Content.where(recording_id: content.recording_id, status: %w[pending processing]).exists?
      Knowledge::SummarizeRecordingJob.perform_later(content.recording_id)
    end

    content.persona.schedule_map_build!
  end
end
