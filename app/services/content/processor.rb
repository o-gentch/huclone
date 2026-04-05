module Content
  class Processor
    def self.call(...) = new(...).call

    def initialize(content_id, embeddings: AI::Embeddings)
      @content = ::Content.find(content_id)
      @embeddings = embeddings
    end

    def call
      return if @content.done?

      @content.update!(status: "processing")

      Content::Chunker.chunk(@content.body).each_with_index do |text, position|
        @content.chunks.create!(
          text: text,
          position: position,
          embedding: @embeddings.fetch(text)
        )
      end

      @content.update!(status: "done")
      BuildPersonalityMapJob.perform_later(@content.persona_id)
    rescue => e
      @content&.update!(status: "pending")
      raise
    end
  end
end
