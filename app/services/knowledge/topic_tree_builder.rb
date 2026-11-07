module Knowledge
  # Строит дерево тем персоны (до 3 уровней) по резюме фрагментов речи.
  #
  # Стабильность (§5 #18): новые материалы сначала присоединяются к ближайшим существующим
  # листьям по центроиду; полная пересборка — по кнопке или когда новых материалов много.
  # При пересборке новые темы сопоставляются со старыми по центроиду и сохраняют id/slug/название.
  # Пересборка всего дерева на текущих объёмах (сотни фрагментов) дешёвая — это осознанно.
  class TopicTreeBuilder
    MODEL = "gpt-4o-mini"
    MAX_DEPTH = 3            # уровни тем: 0, 1, 2
    LEAF_SIZE = 8            # цель размера листа
    SPLIT_ABOVE = 14         # лист больше этого делится глубже
    MAX_TOP_TOPICS = 10
    ATTACH_MIN_SIMILARITY = 0.35
    MATCH_MIN_SIMILARITY = 0.85
    INCREMENTAL_MAX_SHARE = 0.25
    INCREMENTAL_MIN_ALLOWANCE = 5
    MAX_CONCURRENT = 4

    Item = Struct.new(:content, :vector)
    Node = Struct.new(:items, :children, :title, :summary, :centroid, :topic, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(persona, full: false, ai_client: Ai::Client.instance)
      @persona = persona
      @full = full
      @client = ai_client
    end

    def call
      items = load_items
      return if items.empty?

      if !@full && @persona.topics.exists? && attach_incrementally(items)
        return
      end

      rebuild(items)
    end

    private

    def load_items
      vectors = content_vectors
      Content.speeches.done.where(persona_id: @persona.id).where.not(summary: [ nil, "" ]).order(:id).filter_map do |c|
        Item.new(c, vectors[c.id]) if vectors[c.id]
      end
    end

    # Среднее эмбеддингов чанков фрагмента — одним SQL-запросом
    def content_vectors
      rows = Chunk.joins(:content)
                  .where(contents: { persona_id: @persona.id, kind: "speech", status: "done" })
                  .group(:content_id).pluck(:content_id, Arel.sql("AVG(chunks.embedding)::text"))
      rows.to_h { |id, text| [ id, JSON.parse(text) ] }
    end

    # ---- Инкрементальное присоединение -------------------------------------------------

    # true — всё присоединено без пересборки
    def attach_incrementally(items)
      attached_ids = Chunk.joins(:topic_chunks, :content).where(contents: { persona_id: @persona.id }).distinct.pluck(:content_id).to_set
      new_items = items.reject { |i| attached_ids.include?(i.content.id) }
      return true if new_items.empty?
      return false if new_items.size > [ INCREMENTAL_MIN_ALLOWANCE, (attached_ids.size * INCREMENTAL_MAX_SHARE).ceil ].max

      leaves = @persona.topics.where.not(centroid: nil).select(&:leaf?)
      return false if leaves.empty?

      placements = new_items.map do |item|
        leaf, sim = leaves.map { |t| [ t, Clusterer.cosine(item.vector, t.centroid) ] }.max_by(&:last)
        return false if sim < ATTACH_MIN_SIMILARITY
        [ item, leaf ]
      end

      Topic.transaction do
        placements.each do |item, leaf|
          rows = item.content.chunks.pluck(:id).map { |cid| { topic_id: leaf.id, chunk_id: cid } }
          TopicChunk.insert_all(rows, unique_by: %i[topic_id chunk_id]) if rows.any?
        end
        placements.group_by { |_, leaf| leaf }.each_key { |leaf| leaf.touch }
      end
      true
    end

    # ---- Полная пересборка --------------------------------------------------------------

    def rebuild(items)
      nodes = cluster_level(items, 0)
      name_nodes(nodes)
      persist(nodes)
    end

    def cluster_level(items, depth)
      k = if depth.zero?
        items.size <= 3 ? 1 : (items.size / 10.0).ceil.clamp(2, MAX_TOP_TOPICS)
      else
        (items.size / 7.0).ceil.clamp(2, 6)
      end

      groups = Clusterer.call(items.map(&:vector), k)
      groups.map do |idxs|
        members = idxs.map { |i| items[i] }
        node = Node.new(items: members, children: [], centroid: Clusterer.centroid(members.map(&:vector)))
        node.children = cluster_level(members, depth + 1) if members.size > SPLIT_ABOVE && depth + 1 < MAX_DEPTH
        node
      end.sort_by { |n| n.items.map { |i| i.content.id }.min }
    end

    # Листья — по резюме фрагментов, родители — по названиям и резюме детей
    def name_nodes(nodes)
      leaves = []
      collect_leaves(nodes, leaves)
      run_parallel(leaves) { |node| describe(node.items.map { |i| i.content.summary }.first(40), kind: "фрагментов выступлений") }
        .each_with_index { |(title, summary), i| leaves[i].title, leaves[i].summary = title, summary }
      name_parents(nodes)
    end

    def collect_leaves(nodes, acc)
      nodes.each { |n| n.children.empty? ? acc << n : collect_leaves(n.children, acc) }
    end

    def name_parents(nodes)
      nodes.each do |node|
        next if node.children.empty?
        name_parents(node.children)
        node.title, node.summary = describe(node.children.map { |c| "#{c.title}: #{c.summary}" }, kind: "подтем")
      end
    end

    def run_parallel(list)
      pool = Concurrent::FixedThreadPool.new(MAX_CONCURRENT)
      futures = list.map do |x|
        Concurrent::Future.execute(executor: pool) { ActiveRecord::Base.connection_pool.with_connection { yield x } }
      end
      futures.map(&:value).tap { futures.each { |f| raise f.reason if f.rejected? } }
    ensure
      pool&.shutdown
      pool&.wait_for_termination(10.minutes.to_i)
    end

    def describe(parts, kind:)
      raw = Ai::Chat.call(
        stage: "topic_naming", client: @client, model: MODEL, temperature: 0.2, response_format: { type: "json_object" },
        messages: [
          { role: "system", content: "Ты помогаешь структурировать материалы автора для книги. По списку #{kind} придумай название темы " \
                                     "(до 8 слов, без кавычек) и резюме (2–3 предложения). Верни JSON: {\"title\": \"...\", \"summary\": \"...\"}. Только факты из материалов." },
          { role: "user", content: parts.each_with_index.map { |p, i| "#{i + 1}. #{p.to_s.truncate(400)}" }.join("\n") }
        ]
      )
      data = JSON.parse(raw)
      [ data["title"].to_s.squish.presence || "Без названия", data["summary"].to_s.squish ]
    rescue JSON::ParserError
      [ "Без названия", "" ]
    end

    # ---- Сохранение со сопоставлением старых тем ----------------------------------------

    def persist(nodes)
      old = @persona.topics.to_a
      Topic.transaction do
        claimed = Set.new
        TopicChunk.where(topic_id: old.map(&:id)).delete_all
        save_level(nodes, nil, 0, old, claimed)
        Topic.where(id: old.map(&:id) - claimed.to_a).destroy_all
      end
    end

    def save_level(nodes, parent, depth, old, claimed)
      nodes.each_with_index do |node, position|
        match = old.reject { |t| claimed.include?(t.id) || t.depth != depth || t.centroid.nil? }
                   .map { |t| [ t, Clusterer.cosine(node.centroid, t.centroid) ] }
                   .select { |_, sim| sim >= MATCH_MIN_SIMILARITY }.max_by(&:last)&.first

        attrs = { parent: parent, summary: node.summary, position: position, depth: depth, centroid: node.centroid }
        topic = if match
          claimed << match.id # название и slug сохраняем — ссылки и экспорт не ломаются
          match.update!(attrs)
          match
        else
          @persona.topics.create!(attrs.merge(title: node.title))
        end

        if node.children.empty?
          chunk_ids = Chunk.where(content_id: node.items.map { |i| i.content.id }).pluck(:id)
          TopicChunk.insert_all(chunk_ids.map { |cid| { topic_id: topic.id, chunk_id: cid } }) if chunk_ids.any?
        else
          save_level(node.children, topic, depth + 1, old, claimed)
        end
      end
    end
  end
end
