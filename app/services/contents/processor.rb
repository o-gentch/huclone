module Contents
  class Processor
    MAX_QUESTION_CHARS = 300

    def self.call(...) = new(...).call

    def initialize(content_id, embeddings: ::Ai::Embeddings)
      @content = ::Content.find(content_id)
      @embeddings = embeddings
    end

    def call
      return if @content.done?

      @content.update!(status: "processing")

      pieces = build_pieces(sanitize_text(@content.body))
      # Для речи вопрос включается в эмбеддинг: ответ находится по формулировке вопроса
      vectors = @embeddings.fetch_many(pieces.map { |p| embedding_input(p[:text]) })
      now = Time.current

      # Пересоздаём чанки атомарно: ретраи не плодят дубликаты
      ::Content.transaction do
        @content.chunks.delete_all
        rows = pieces.each_with_index.map do |piece, position|
          { content_id: @content.id, text: piece[:text], position: position, start_ms: piece[:start_ms],
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

    def build_pieces(text)
      if @content.speech?
        Contents::Chunker.chunk_speech(text, start_ms: @content.start_ms.to_i, end_ms: @content.end_ms.to_i)
      else
        Contents::Chunker.chunk(text).map { |t| { text: t, start_ms: nil } }
      end
    end

    def embedding_input(text)
      return text unless @content.speech? && @content.context_text.present?

      "Вопрос: #{@content.context_text.truncate(MAX_QUESTION_CHARS)}\nОтвет: #{text}"
    end

    def sanitize_text(text)
      text
        .dup
        .force_encoding("UTF-8")
        .scrub("")
        .gsub(/[^\u0009\u000A\u000D -퟿-�]/, "")
    end
  end
end
