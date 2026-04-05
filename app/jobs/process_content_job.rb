class ProcessContentJob < ApplicationJob
  queue_as :default

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(content_id)
    Content::Processor.call(content_id)
  end
end
