require "test_helper"

class Contents::ChunkerSpeechTest < ActiveSupport::TestCase
  test "splits on sentence boundaries with interpolated timecodes" do
    text = ([ "Это предложение про важную тему и ещё немного слов для объёма." ] * 60).join(" ")
    chunks = Contents::Chunker.chunk_speech(text, start_ms: 10_000, end_ms: 110_000)

    assert_operator chunks.size, :>, 1
    assert chunks.all? { |c| c[:text].length <= Contents::Chunker::SPEECH_CHUNK_SIZE }
    assert chunks.all? { |c| c[:text].end_with?(".") }
    assert_equal 10_000, chunks.first[:start_ms]
    assert_equal chunks.map { |c| c[:start_ms] }, chunks.map { |c| c[:start_ms] }.sort
    assert_operator chunks.last[:start_ms], :<, 110_000
  end

  test "short text is one chunk; blank text is none" do
    assert_equal 1, Contents::Chunker.chunk_speech("Короткий ответ.", start_ms: 0, end_ms: 1000).size
    assert_empty Contents::Chunker.chunk_speech("  ", start_ms: 0, end_ms: 0)
  end
end
