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

      chunks = Contents::Chunker.chunk(@content.body)
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
  end
end
