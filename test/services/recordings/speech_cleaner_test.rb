require "test_helper"

class Recordings::SpeechCleanerTest < ActiveSupport::TestCase
  class FakeClient
    def initialize(reply) = @reply = reply
    def chat(parameters:) = { "choices" => [ { "message" => { "content" => @reply } } ], "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 } }
  end

  RAW = "Ну вот, значит, в общем, я считаю, что регулярность важнее вдохновения, и в 2020 году я написал 365 постов, вот".freeze

  def clean(reply) = Recordings::SpeechCleaner.call(RAW, ai_client: FakeClient.new(reply))

  test "accepts a faithful cleanup" do
    good = "Я считаю, что регулярность важнее вдохновения, и в 2020 году я написал 365 постов"
    assert_equal good, clean(good)
  end

  test "rejects output that is too short, too long or empty" do
    assert_equal RAW, clean("Регулярность.")
    assert_equal RAW, clean(RAW * 2)
    assert_equal RAW, clean("")
  end

  test "rejects output that changed numbers" do
    assert_equal RAW, clean("Я считаю, что регулярность важнее вдохновения, и в 2021 году я написал 100 постов")
  end

  test "rejects a paraphrase that loses key words" do
    assert_equal RAW, clean("Главное для успеха — делать что-то каждый день без исключений, не дожидаясь настроения и озарений")
  end

  test "api failure falls back to raw text" do
    failing = Object.new
    def failing.chat(**) = raise(Faraday::ConnectionFailed, "down")
    assert_equal RAW, Recordings::SpeechCleaner.call(RAW, ai_client: failing)
  end
end
