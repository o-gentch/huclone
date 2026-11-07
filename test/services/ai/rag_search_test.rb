require "test_helper"

class Ai::RagSearchTest < ActiveSupport::TestCase
  setup do
    @persona = users(:one).personas.create!(name: "Автор")
    @rec1 = create_recording(@persona, status: "confirmed", title: "Первая")
    @rec2 = create_recording(@persona, status: "confirmed", title: "Вторая")
    @speech1 = create_speech(@persona, @rec1, 0, 1)
    @speech2 = create_speech(@persona, @rec2, 0, 2)
    @post = @persona.contents.create!(kind: "post", title: "Пост", body: "п", status: "done", sources: [])
    @post.chunks.create!(text: "п", position: 0, embedding: cluster_vector(0, 99))
  end

  def search(**opts)
    original = Ai::Embeddings.method(:fetch)
    vector = cluster_vector(0)
    Ai::Embeddings.define_singleton_method(:fetch) { |_text| vector }
    Ai::RagSearch.call(@persona.id, "вопрос", **opts).to_a
  ensure
    Ai::Embeddings.define_singleton_method(:fetch, original)
  end

  test "returns chunks with source metadata" do
    chunk = search.find { |c| c.content_id == @speech1.id }
    assert_equal @rec1.id, chunk.content.recording_id
    assert_equal @speech1.start_ms, chunk.start_ms
    assert_match(/Из выступления «Первая», 0:10/, chunk.source_label)
    assert_equal "Вопрос 1?", chunk.content.context_text
  end

  test "filters by recording and by kind" do
    assert_equal [ @speech2.id ], search(recording_id: @rec2.id).map(&:content_id)
    assert_equal [ @post.id ], search(kind: "post").map(&:content_id)
    assert search(kind: "speech").none? { |c| c.content_id == @post.id }
  end

  test "top_k depends on intent and context is capped" do
    assert_equal 5, Ai::RagSearch.top_k_for("answer_question")
    assert_operator Ai::RagSearch.top_k_for("structure_knowledge"), :>, 5
    chunks = Array.new(10) { |i| create_speech(@persona, @rec1, 0, 10 + i, text: "x" * 3_000).chunks.first }
    kept = Ai::RagSearch.within_budget(chunks, max_chars: 10_000)
    assert_operator kept.size, :<, 10
    assert_operator kept.size, :>=, 1
    assert_equal 1, Ai::RagSearch.within_budget(chunks, max_chars: 10).size # хотя бы один фрагмент остаётся
  end

  test "sources reference recordings with timestamps for UI links" do
    ref = search.find { |c| c.content_id == @speech1.id }.source_reference
    assert_equal @rec1.id, ref["recording_id"]
    assert_equal 10_000, ref["start_ms"]
  end
end
