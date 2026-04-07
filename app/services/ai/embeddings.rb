module Ai
  module Embeddings
    MODEL = "text-embedding-3-small"

    def self.fetch(text)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Ai::Client.instance.embeddings(parameters: { model: MODEL, input: text })
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      Rails.logger.info(
        "[AI::Embeddings] model=#{MODEL} " \
        "input_chars=#{text.length} " \
        "tokens=#{response.dig("usage", "total_tokens")} " \
        "ms=#{elapsed}"
      )

      response.dig("data", 0, "embedding")
    rescue => e
      Rails.logger.error("[AI::Embeddings] error=#{e.class} message=#{e.message.truncate(120)}")
      raise
    end
  end
end
