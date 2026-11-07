require "test_helper"

class Contents::ChunkerTest < ActiveSupport::TestCase
  test "short text yields a single chunk" do
    assert_equal [ "hello world" ], Contents::Chunker.chunk("hello world")
  end

  test "long text is split with overlap and nothing is lost" do
    text = ([ "слово" ] * 1000).join(" ")
    chunks = Contents::Chunker.chunk(text)

    assert_operator chunks.size, :>, 1
    assert(chunks.all? { |c| c.length <= Contents::Chunker::CHUNK_SIZE })
    assert_equal text.split.uniq, chunks.flat_map(&:split).uniq
  end

  test "blank text yields no chunks" do
    assert_empty Contents::Chunker.chunk("   ")
  end
end
