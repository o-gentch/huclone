require "test_helper"

class Knowledge::TopicTreeBuilderTest < ActiveSupport::TestCase
  setup do
    @persona = users(:one).personas.create!(name: "Автор")
    @recording = create_recording(@persona, status: "confirmed")
    @n = 0
    3.times { |c| 10.times { add(c) } }
  end

  def add(cluster)
    create_speech(@persona, @recording, cluster, @n += 1)
  end

  def build(full: false, client: @client ||= NamingClient.new)
    Knowledge::TopicTreeBuilder.call(@persona, full: full, ai_client: client)
  end

  test "builds a tree grouping similar fragments and linking their chunks" do
    build
    roots = @persona.topics.roots
    assert_equal 3, roots.size
    assert roots.all? { |t| t.title.start_with?("Тема") && t.slug.start_with?("t-") }
    assert_equal 30, TopicChunk.count
    # каждая тема содержит фрагменты только одного «кластера»
    roots.each do |t|
      axes = t.subtree_chunk_scope.map { |c| c.embedding.each_with_index.max[1] }.uniq
      assert_equal 1, axes.size
    end
  end

  test "rebuild keeps ids, slugs and titles of matching topics" do
    build
    before = @persona.topics.pluck(:id, :slug, :title).sort
    build(full: true)
    assert_equal before, @persona.topics.pluck(:id, :slug, :title).sort
    assert_equal 30, TopicChunk.count
  end

  test "new similar fragments attach to existing topics without renaming or LLM calls" do
    build
    calls = @client.calls
    ids = @persona.topics.pluck(:id).sort

    fresh = add(1)
    build

    assert_equal calls, @client.calls
    assert_equal ids, @persona.topics.pluck(:id).sort
    assert TopicChunk.exists?(chunk_id: fresh.chunks.first.id)
  end

  test "a very different fragment triggers a rebuild" do
    build
    calls = @client.calls
    add(7)
    build
    assert_operator @client.calls, :>, calls
    assert_equal 31, TopicChunk.count
  end

  test "nothing to build without summarized speech" do
    Content.update_all(summary: nil)
    build
    assert_equal 0, Topic.count
  end

  test "large clusters are split into subtopics (up to three levels)" do
    Content.destroy_all
    Topic.delete_all
    @n = 0
    # 150 фрагментов при максимум 10 верхних темах: по принципу Дирихле хотя бы одна тема больше SPLIT_ABOVE
    150.times { create_speech(@persona, @recording, 0, @n += 1) }
    build
    assert_operator @persona.topics.maximum(:depth), :>=, 1
    assert_operator @persona.topics.maximum(:depth), :<, Knowledge::TopicTreeBuilder::MAX_DEPTH
  end
end
