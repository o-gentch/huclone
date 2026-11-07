module Ai
  module Embeddings
    MODEL = "text-embedding-3-small"
    BATCH_SIZE = 64

    def self.fetch(text)
      fetch_many([ text ]).first
    end

    # Один HTTP-запрос на пачку текстов; порядок результатов соответствует входу.
    def self.fetch_many(texts)
      texts.each_slice(BATCH_SIZE).flat_map { |slice| request(slice) }
    end

    def self.request(texts)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Ai::Client.instance.embeddings(parameters: { model: MODEL, input: texts })
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      Rails.logger.info(
        "[AI::Embeddings] model=#{MODEL} " \
        "inputs=#{texts.size} " \
        "input_chars=#{texts.sum(&:length)} " \
        "tokens=#{response.dig("usage", "total_tokens")} " \
        "ms=#{elapsed}"
      )

      response.fetch("data").sort_by { |d| d["index"] }.map { |d| d["embedding"] }
    rescue => e
      Rails.logger.error("[AI::Embeddings] error=#{e.class} message=#{e.message.truncate(120)}")
      raise
    end
    private_class_method :request
  end
end
