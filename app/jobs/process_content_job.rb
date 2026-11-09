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
    PersonaContent.where(content_id: content_id).includes(:persona).map(&:persona).uniq.each do |persona|
      Personas::ContentReady.call(persona)
    end
  end
end
