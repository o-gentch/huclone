class ContentProcessor
  CHUNK_SIZE = 1500
  CHUNK_OVERLAP = 200

  def self.process(content_id)
    content = Content.find(content_id)
    return if content.done?

    content.update!(status: "processing")

    chunks = split_into_chunks(content.source)
    chunks.each_with_index do |chunk_text, position|
      content.chunks.create!(
        text: chunk_text,
        embedding: fetch_embedding(chunk_text),
        position: position
      )
    end

    content.update!(status: "done")
    BuildPersonalityMapJob.perform_later(content.persona_id)
  rescue => e
    content&.update!(status: "pending")
    raise e
  end

  def self.split_into_chunks(text)
    chunks = []
    start = 0

    while start < text.length
      finish = start + CHUNK_SIZE
      chunk = text[start...finish]

      # avoid cutting mid-word — back up to last whitespace
      if finish < text.length && (boundary = chunk.rindex(/\s/))
        chunk = chunk[0..boundary].rstrip
        finish = start + boundary + 1
      end

      chunks << chunk unless chunk.strip.empty?
      start = [ finish - CHUNK_OVERLAP, start + 1 ].max
    end

    chunks
  end

  def self.fetch_embedding(text)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
    response = client.embeddings(
      parameters: {
        model: "text-embedding-3-small",
        input: text
      }
    )
    response.dig("data", 0, "embedding")
  end
end
