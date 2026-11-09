module Ai
  class RagSearch
    TOP_K = 5
    # structure_knowledge просит охват, поэтому берём больше фрагментов (ограничено MAX_CONTEXT_CHARS)
    TOP_K_BY_INTENT = { "structure_knowledge" => 12, "book" => 12 }.freeze
    MAX_CONTEXT_CHARS = 12_000

    def self.call(...) = new(...).call

    def self.top_k_for(intent) = TOP_K_BY_INTENT.fetch(intent, TOP_K)

    # recording_id — искать только в одной записи; kind — "post" или "speech"
    def initialize(persona_id, query, top_k: TOP_K, recording_id: nil, kind: nil)
      @persona_id = persona_id
      @query = query
      @top_k = top_k
      @recording_id = recording_id
      @kind = kind
    end

    # Возвращает чанки с content (и recording) — для цитирования источника
    def call
      query_embedding = Ai::Embeddings.fetch(@query)
      enable_iterative_scan

      # Сначала сужаем до материалов пользователя, затем присоединяем связь с DD (HNSW фильтрует уже после выборки соседей)
      scope = Chunk
        .joins(content: :persona_contents)
        .where(persona_contents: { persona_id: @persona_id }, contents: { status: "done" })
      scope = scope.where(contents: { recording_id: @recording_id }) if @recording_id
      scope = scope.where(contents: { kind: @kind }) if @kind

      scope
        .includes(content: :recording)
        .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
        .limit(@top_k)
    end

    # pgvector ≥ 0.8: если фильтр по DD отсеивает часть соседей, индекс продолжает сканирование
    def enable_iterative_scan
      Chunk.connection.execute("SET hnsw.iterative_scan = relaxed_order")
    rescue ActiveRecord::StatementInvalid
      nil # старый pgvector без итеративного сканирования
    end

    # Обрезает набор фрагментов по суммарному размеру
    def self.within_budget(chunks, max_chars: MAX_CONTEXT_CHARS)
      total = 0
      chunks.take_while do |c|
        total += c.text.length + c.content.context_text.to_s.length
        total <= max_chars || total == c.text.length + c.content.context_text.to_s.length
      end
    end
  end
end
