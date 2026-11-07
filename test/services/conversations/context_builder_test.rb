require "test_helper"

class Conversations::ContextBuilderTest < ActiveSupport::TestCase
  setup do
    @persona = users(:one).personas.create!(
      name: "P",
      personality_map: {
        "core_beliefs" => [], "main_topics" => [], "speech_style" => {},
        "spoken_style" => { "humor" => "ирония" },
        "verbatim_examples" => [ { "text" => "ПИСЬМО", "source" => "post" }, { "text" => "РЕЧЬ", "source" => "speech" } ]
      }
    )
    @persona.contents.create!(kind: "post", title: "t", body: "Образец поста", status: "done", is_exemplar: true, sources: [])
    @persona.contents.create!(kind: "speech", title: "s", body: "Образец речи", status: "done", is_exemplar: true, sources: [])
  end

  test "write_post uses the written voice, post exemplars and no spoken material" do
    prompt = Conversations::ContextBuilder.build_system(@persona, "strict", "write_post")
    assert_includes prompt, "ПИСЬМО"
    assert_not_includes prompt, "РЕЧЬ"
    assert_not_includes prompt, "spoken_style\":{"
    assert_includes prompt, "Образец поста"
    assert_not_includes prompt, "Образец речи"
    assert_includes prompt, "Голос: письменный"
  end

  test "dialogue intents include the spoken style and speech quotes" do
    %w[casual_chat answer_question structure_knowledge generate_ideas].each do |intent|
      prompt = Conversations::ContextBuilder.build_system(@persona, "strict", intent)
      assert_includes prompt, "ирония", intent
      assert_includes prompt, "РЕЧЬ", intent
      assert_includes prompt, "Голос: устная речь", intent
    end
  end

  test "legacy map without spoken_style still works" do
    @persona.update!(personality_map: { "core_beliefs" => [], "main_topics" => [], "speech_style" => {}, "verbatim_examples" => [ "цитата" ] })
    prompt = Conversations::ContextBuilder.build_system(@persona, "strict", "answer_question")
    assert_includes prompt, "цитата"
    assert_not_includes prompt, "Голос: устная речь"
  end
end
