require "test_helper"

class Personas::PersonalityMapBuilderTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(map) = (@map = map; @calls = [])

    def chat(parameters:)
      @calls << parameters
      content = parameters[:model] == "gpt-4o" ? @map.to_json : "наблюдения"
      { "choices" => [ { "message" => { "content" => content } } ] }
    end
  end

  MAP = {
    "core_beliefs" => [ "a" ], "main_topics" => [ "b" ], "speech_style" => {},
    "spoken_style" => { "typical_phrases" => [ "ну смотрите" ] },
    "verbatim_examples" => [ { "text" => "Пост-цитата", "source" => "post" }, { "text" => "Речь-цитата", "source" => "speech" } ]
  }.freeze

  setup { @persona = users(:one).personas.create!(name: "P") }

  def add(kind, body, **attrs)
    add_content(@persona, **{ kind: kind, title: "t", body: body, status: "done" }.merge(attrs))
  end

  test "builds a map with spoken_style and sourced quotes; speech prompt carries the question" do
    add "post", "Пост про маятник."
    add "speech", "Очищенный ответ.", raw_body: "Ну вот сырой ответ.", context_text: "Как вы начинали?"
    client = FakeClient.new(MAP)

    Personas::PersonalityMapBuilder.call(@persona.id, ai_client: client)

    map = @persona.reload.personality_map
    assert_equal [ "ну смотрите" ], map.dig("spoken_style", "typical_phrases")
    assert_equal %w[post speech], map["verbatim_examples"].map { |e| e["source"] }
    prompt = client.calls.first[:messages].last[:content]
    assert_includes prompt, "УСТНАЯ РЕЧЬ"
    assert_includes prompt, "Как вы начинали?"
    assert_includes prompt, "сырой ответ" # стиль берётся из сырого текста
    assert_not_includes prompt, "Очищенный ответ"
    assert PersonaContent.all.all?(&:included_in_map)
  end

  test "old maps (string quotes, no spoken_style) are normalized" do
    old = { "core_beliefs" => [], "main_topics" => [], "speech_style" => {}, "verbatim_examples" => [ "старая цитата" ] }
    normalized = Personas::PersonalityMapBuilder.normalize_map(old)
    assert_equal [ { "text" => "старая цитата", "source" => "post" } ], normalized["verbatim_examples"]
    assert_equal({}, normalized["spoken_style"])
  end

  test "batches by text volume, not only by count" do
    big = Array.new(5) { |i| Content.new(body: "x" * 30_000, kind: "post", id: i + 1) }
    batches = Personas::PersonalityMapBuilder.size_batches(big, max_items: 25, max_chars: 60_000)
    assert_equal [ 2, 2, 1 ], batches.map(&:size)

    small = Array.new(30) { |i| Content.new(body: "x", kind: "post", id: i + 1) }
    assert_equal [ 25, 5 ], Personas::PersonalityMapBuilder.size_batches(small).map(&:size)
  end

  test "exemplars and written linguistics ignore speech" do
    post = add "post", "Короткий пост. Ещё предложение."
    add "speech", "Очень длинный устный ответ. " * 200, raw_body: "Ну вот. " * 50

    Personas::ExemplarSelector.call(@persona)
    assert_equal [ post.id ], @persona.persona_contents.exemplars.pluck(:content_id)

    Personas::LinguisticsAnalyzer.call(@persona.id)
    l = @persona.reload.linguistics
    assert_equal 1, l["avg_post_words"] / 4 # 4 слова в единственном посте
    assert l["spoken"]["fillers_per_100_words"].positive?
  end
end
