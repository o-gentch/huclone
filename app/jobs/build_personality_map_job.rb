class BuildPersonalityMapJob < ApplicationJob
  queue_as :personality_map

  limits_concurrency to: 1, key: ->(persona_id) { "build_personality_map/#{persona_id}" }, duration: 30.minutes

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(persona_id)
    Personas::LinguisticsAnalyzer.call(persona_id)
    Personas::PersonalityMapBuilder.call(persona_id)
  end
end
