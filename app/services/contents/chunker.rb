module Contents
  module Chunker
    CHUNK_SIZE = 1500
    CHUNK_OVERLAP = 200

    def self.chunk(text)
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
        break if finish >= text.length

        start = [ finish - CHUNK_OVERLAP, start + 1 ].max
        # Следующий чанк не должен начинаться посреди слова
        if start > 0 && text[start - 1] !~ /\s/ && (shift = text[start...finish].index(/\s/))
          start += shift + 1
        end
      end

      chunks
    end
  end
end
