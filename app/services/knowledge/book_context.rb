module Knowledge
  # Контекст режима «книга»: оглавление из дерева тем + (для вопроса про конкретную главу)
  # фрагменты ближайшей темы. Структурные запросы идут через дерево, а не через плоский RAG (§5 #19).
  class BookContext
    Result = Struct.new(:outline, :chunks, :topic, keyword_init: true)

    TOC_ONLY = /оглавлени|содержани|структур[ауы]\s+книг|план\s+книг|список\s+глав/i
    MIN_TOPIC_SIMILARITY = 0.4
    CHUNKS_LIMIT = 10

    def self.call(...) = new(...).call

    def initialize(persona, query, embeddings: Ai::Embeddings)
      @persona = persona
      @query = query
      @embeddings = embeddings
    end

    def call
      outline = Outline.prompt_text(@persona)
      return Result.new(outline: nil, chunks: []) if outline.blank?
      return Result.new(outline: outline, chunks: []) if @query.match?(TOC_ONLY)

      topic = best_topic
      chunks = topic ? chapter_chunks(topic) : []
      Result.new(outline: outline, chunks: Ai::RagSearch.within_budget(chunks), topic: topic)
    rescue OpenAI::Error, Faraday::Error => e
      Rails.logger.warn("[BookContext] chapter lookup failed: #{e.class}")
      Result.new(outline: outline, chunks: [])
    end

    private

    def query_vector = @query_vector ||= @embeddings.fetch(@query)

    def best_topic
      topic, sim = @persona.topics.where.not(centroid: nil).map { |t| [ t, Clusterer.cosine(query_vector, t.centroid) ] }.max_by(&:last)
      topic if topic && sim >= MIN_TOPIC_SIMILARITY
    end

    def chapter_chunks(topic)
      topic.subtree_chunk_scope
           .includes(content: :recording)
           .nearest_neighbors(:embedding, query_vector, distance: "cosine")
           .limit(CHUNKS_LIMIT).to_a
    end
  end
end
