class BuildPersonalityMapJob < ApplicationJob
  queue_as :default

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(persona_id)
    Persona::PersonalityMapBuilder.call(persona_id)
  end
end
