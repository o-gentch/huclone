require "test_helper"

class Transcription::AssemblyAiTest < ActiveSupport::TestCase
  def provider(&stubs)
    conn = Faraday.new(url: "https://api.assemblyai.com") { |f| f.adapter :test, Faraday::Adapter::Test::Stubs.new(&stubs) }
    Transcription::AssemblyAi.new(api_key: "k", connection: conn)
  end

  test "submit uploads then creates a transcript with diarization in Russian" do
    sent = nil
    p = provider do |s|
      s.post("/v2/upload") { [ 200, {}, { upload_url: "https://cdn/x" }.to_json ] }
      s.post("/v2/transcript") { |env| sent = JSON.parse(env.body); [ 200, {}, { id: "abc" }.to_json ] }
    end
    assert_equal "abc", p.submit(StringIO.new("data"), expected_speakers: 2)
    assert_equal "ru", sent["language_code"]
    assert_equal true, sent["speaker_labels"]
    assert_equal 2, sent["speakers_expected"]
  end

  test "fetch maps statuses and utterances" do
    p = provider do |s|
      s.get("/v2/transcript/q") { [ 200, {}, { status: "processing" }.to_json ] }
      s.get("/v2/transcript/ok") { [ 200, {}, { status: "completed", audio_duration: 12.5, utterances: [ { speaker: "A", start: 0, end: 900, text: "Привет", confidence: 0.9 } ] }.to_json ] }
      s.get("/v2/transcript/bad") { [ 200, {}, { status: "error", error: "no audio" }.to_json ] }
    end
    assert_equal :pending, p.fetch("q")
    result = p.fetch("ok")
    assert_equal 12_500, result.duration_ms
    assert_equal "Привет", result.utterances.first[:text]
    assert_raises(Transcription::PermanentError) { p.fetch("bad") }
  end

  test "429 and 5xx are transient, 4xx are permanent" do
    p = provider do |s|
      s.get("/v2/transcript/a") { [ 429, {}, "{}" ] }
      s.get("/v2/transcript/b") { [ 503, {}, "{}" ] }
      s.get("/v2/transcript/c") { [ 400, {}, "{}" ] }
    end
    assert_raises(Transcription::TransientError) { p.fetch("a") }
    assert_raises(Transcription::TransientError) { p.fetch("b") }
    assert_raises(Transcription::PermanentError) { p.fetch("c") }
  end

  test "missing api key is a permanent error" do
    ENV.delete("ASSEMBLYAI_API_KEY")
    assert_raises(Transcription::PermanentError) { Transcription::AssemblyAi.new(api_key: "").submit(StringIO.new("x")) }
  end
end
