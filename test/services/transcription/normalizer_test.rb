require "test_helper"

class Transcription::NormalizerTest < ActiveSupport::TestCase
  def u(speaker, start, finish, text, conf = 0.9)
    { speaker: speaker, start_ms: start, end_ms: finish, text: text, confidence: conf }
  end

  test "merges consecutive utterances of one speaker with a short pause" do
    result = Transcription::Normalizer.call([ u("X", 0, 1000, "Привет"), u("X", 1500, 2500, "мир") ])
    assert_equal 1, result.size
    assert_equal "Привет мир", result.first[:text]
    assert_equal 2500, result.first[:end_ms]
  end

  test "does not merge across a long pause or different speakers" do
    result = Transcription::Normalizer.call([ u("X", 0, 1000, "Раз"), u("X", 5000, 6000, "Два"), u("Y", 6100, 7000, "Три") ])
    assert_equal 3, result.size
  end

  test "drops blank utterances and relabels speakers A, B in order of appearance" do
    result = Transcription::Normalizer.call([ u("spk_9", 0, 1000, "Привет"), u("spk_2", 2000, 3000, " "), u("spk_2", 4000, 5000, "Ответ") ])
    assert_equal %w[A B], result.map { |r| r[:speaker] }
  end

  test "confidence is weighted by text length and nil-safe" do
    result = Transcription::Normalizer.call([ u("A", 0, 1000, "aaaa", 1.0), u("A", 1100, 2000, "bb", 0.4) ])
    assert_in_delta 0.8, result.first[:confidence], 0.001
    assert_nil Transcription::Normalizer.call([ u("A", 0, 1, "x", nil) ]).first[:confidence]
  end
end
