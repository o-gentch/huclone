require "test_helper"

class Contents::ProcessorTest < ActiveSupport::TestCase
  class FakeEmbeddings
    def self.fetch_many(texts) = texts.map { Array.new(1536) { 0.1 } }
  end

  setup do
    @persona = users(:one).personas.create!(name: "Test")
    @content = @persona.contents.create!(title: "t", body: ([ "слово" ] * 1000).join(" "), sources: [], status: "pending")
  end

  test "creates chunks and marks content done" do
    Contents::Processor.new(@content.id, embeddings: FakeEmbeddings).call

    assert @content.reload.done?
    assert_equal (0...@content.chunks.count).to_a, @content.chunks.ordered.pluck(:position)
  end

  test "reprocessing does not duplicate chunks" do
    Contents::Processor.new(@content.id, embeddings: FakeEmbeddings).call
    count = @content.chunks.count
    @content.update!(status: "pending")
    Contents::Processor.new(@content.id, embeddings: FakeEmbeddings).call

    assert_equal count, @content.chunks.count
  end

  test "failure resets status to pending" do
    failing = Class.new { def self.fetch_many(_) = raise("boom") }

    assert_raises(RuntimeError) { Contents::Processor.new(@content.id, embeddings: failing).call }
    assert @content.reload.pending?
  end
end
