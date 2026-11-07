module Contents
  class Processor
    def self.call(...) = new(...).call

    def initialize(content_id, embeddings: ::Ai::Embeddings)
      @content = ::Content.find(content_id)
      @embeddings = embeddings
    end

    def call
      return if @content.done?

      @content.update!(status: "processing")

      texts = Contents::Chunker.chunk(sanitize_text(@content.body))
      vectors = @embeddings.fetch_many(texts)
      now = Time.current

      # Пересоздаём чанки атомарно: ретраи не плодят дубликаты
      ::Content.transaction do
        @content.chunks.delete_all
        rows = texts.each_with_index.map do |text, position|
          { content_id: @content.id, text: text, position: position,
            embedding: vectors[position], created_at: now, updated_at: now }
        end
        ::Chunk.insert_all!(rows) if rows.any?
        @content.update!(status: "done")
      end
    rescue => e
      @content&.update!(status: "pending")
      raise
    end

    def self.fail!(content_id)
      Content.find_by(id: content_id)&.update!(status: "failed")
    end

    private

    def sanitize_text(text)
      text
        .dup
        .force_encoding("UTF-8")
        .scrub("")
        .gsub(/[^\u0009\u000A\u000D -퟿-�]/, "")
    end
  end
end
