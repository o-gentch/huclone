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

      body = sanitize_text(@content.body)
      chunks = Contents::Chunker.chunk(body)
      chunks.each_with_index do |text, position|
        @content.chunks.create!(
          text: text,
          position: position,
          embedding: @embeddings.fetch(text)
        )
        sleep(0.1) unless position == chunks.size - 1
      end

      @content.update!(status: "done")
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
        .force_encoding("UTF-8")
        .scrub("")
        .gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD]/, "")
    end
  end
end
