module AI
  module Embeddings
    MODEL = "text-embedding-3-small"

    def self.fetch(text)
      AI::Client.instance.embeddings(parameters: { model: MODEL, input: text })
        .dig("data", 0, "embedding")
    end
  end
end
