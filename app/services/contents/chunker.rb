module Contents
  module Chunker
    CHUNK_SIZE = 1500
    CHUNK_OVERLAP = 200

    SPEECH_CHUNK_SIZE = 1200

    # Режим для речи: границы предложений, чанки ~1000–1500 символов.
    # Возвращает [{text:, start_ms:}] — таймкод начала интерполируется по позиции в тексте.
    def self.chunk_speech(text, start_ms: 0, end_ms: 0, max_size: SPEECH_CHUNK_SIZE)
      sentences = text.scan(/[^.!?…]+[.!?…]*\s*/).map(&:strip).reject(&:empty?)
      total = [ sentences.sum { |s| s.length + 1 }, 1 ].max
      chunks = []
      current = +""
      offset = 0
      chunk_offset = 0

      flush = lambda do
        next if current.strip.empty?
        chunks << { text: current.strip, start_ms: start_ms + ((end_ms - start_ms) * chunk_offset / total) }
        current = +""
      end

      sentences.each do |sentence|
        if current.present? && current.length + sentence.length + 1 > max_size
          flush.call
          chunk_offset = offset
        end
        current << " " unless current.empty?
        current << sentence
        offset += sentence.length + 1
      end
      flush.call
      chunks
    end

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
