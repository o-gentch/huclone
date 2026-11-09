module Personas
  # Убирает фрагменты из знаний DD (материал остаётся в библиотеке):
  # чистит связи и привязки к темам; если ушёл «голосовой» материал — карта и темы пересобираются.
  module RemoveContents
    module_function

    def call(persona, content_ids)
      content_ids = Array(content_ids)
      return if content_ids.empty?

      links = persona.persona_contents.where(content_id: content_ids)
      voice_removed = links.voice.exists?
      return unless links.exists?

      topic_ids = persona.topics.select(:id)
      chunk_ids = Chunk.where(content_id: content_ids).select(:id)
      TopicChunk.where(topic_id: topic_ids, chunk_id: chunk_ids).delete_all
      links.delete_all
      persona.reset_derived_knowledge! if voice_removed
    end
  end
end
