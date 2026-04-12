module Ai
  class RagSearch
    TOP_K = 5

    def self.call(...) = new(...).call

    def initialize(persona_id, query)
      @persona_id = persona_id
      @query = query
    end

    def call
      query_embedding = Ai::Embeddings.fetch(@query)

      Chunk
        .joins(content: :persona)
        .where(contents: { persona_id: @persona_id, status: "done" })
        .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(TOP_K)
    end
  end
end
