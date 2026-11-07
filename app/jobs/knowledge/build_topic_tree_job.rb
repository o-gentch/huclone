module Knowledge
  class BuildTopicTreeJob < ApplicationJob
    queue_as :personality_map

    limits_concurrency to: 1, key: ->(persona_id, *) { "topic_tree/#{persona_id}" }, duration: 30.minutes

    retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 5
    retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    MAX_RUNTIME = 15.minutes

    def perform(persona_id, full = false)
      persona = Persona.find(persona_id)
      Timeout.timeout(MAX_RUNTIME.to_i) { Knowledge::TopicTreeBuilder.call(persona, full: full) }
    end
  end
end
