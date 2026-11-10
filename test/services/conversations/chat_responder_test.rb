require "test_helper"

class Conversations::ChatResponderTest < ActiveSupport::TestCase
  class FakeChat
    attr_reader :prompts
    def initialize = @prompts = []

    def chat(parameters:)
      if parameters[:stream]
        @prompts << parameters[:messages]
        parameters[:stream].call({ "choices" => [ { "delta" => { "content" => "Ответ автора." } } ] }, nil)
        return {}
      end
      { "choices" => [ { "message" => { "content" => "answer_question" } } ] }
    end
  end

  setup do
    @persona = users(:one).personas.create!(name: "Автор")
    @recording = create_recording(@persona, status: "confirmed", title: "Конференция")
    n = 0
    2.times { |c| 8.times { create_speech(@persona, @recording, c, n += 1) } }
    Knowledge::TopicTreeBuilder.call(@persona, ai_client: NamingClient.new)

    @conversation = @persona.conversations.create!
    @fake = FakeChat.new
    @original_client = Ai::Client.instance
    Ai::Client.instance_variable_set(:@instance, @fake)
    @orig_fetch = Ai::Embeddings.method(:fetch)
    vector = cluster_vector_for_test
    Ai::Embeddings.define_singleton_method(:fetch) { |_t| vector }
  end

  teardown do
    Ai::Client.instance_variable_set(:@instance, @original_client)
    Ai::Embeddings.define_singleton_method(:fetch, @orig_fetch)
  end

  def cluster_vector_for_test = Array.new(1536) { |i| i == 1 ? 1.0 : 0.0 }

  def respond(body, mode)
    user = @conversation.messages.create!(role: "user", body: body, mode: mode)
    assistant = @conversation.messages.create!(role: "assistant", body: "", mode: mode)
    Conversations::ChatResponder.call(@conversation, user, assistant)
    [ assistant.reload, @fake.prompts.last ]
  end

  test "plain answer labels fragments with their source and stores sources on the message" do
    assistant, prompt = respond("Как вы начинали?", "strict")
    user_content = prompt.last[:content]
    assert_match(/Из выступления «Конференция», \d+:\d\d/, user_content)
    assert_includes user_content, "Вопрос собеседника:"
    assert_equal "Ответ автора.", assistant.body
    assert assistant.sources.any?
    assert_equal @recording.id, assistant.sources.first["recording_id"]
  end

  test "book mode feeds the topic tree outline and chapter fragments" do
    assistant, prompt = respond("Составь оглавление книги по всем выступлениям", "book")
    user_content = prompt.last[:content]
    assert_match(/дерево тем/, user_content)
    assert_match(/^1\. Тема/, user_content)
    assert_match(/Задача: книга/, prompt.first[:content])
    assert_equal "Ответ автора.", assistant.body
  end

  test "book mode without a tree falls back to ordinary retrieval" do
    Topic.delete_all
    assistant, prompt = respond("Составь оглавление книги", "book")
    assert_no_match(/дерево тем/, prompt.last[:content])
    assert_equal "Ответ автора.", assistant.body
  end

  test "message sources render as links to the recording moment" do
    assistant, _ = respond("Как вы начинали?", "strict")
    html = ApplicationController.render(partial: "conversations/sources", locals: { message: assistant, persona: @persona })
    assert_includes html, "#t="
    assert_includes html, "Конференция"
  end

  test "irrelevant fragments are not sent to the model" do
    Ai::Embeddings.define_singleton_method(:fetch) { |_t| Array.new(1536) { |i| i == 1000 ? 1.0 : 0.0 } }
    _assistant, prompt = respond("Совсем другая тема", "ideas")
    assert_no_match(/Релевантные фрагменты/, prompt.last[:content])
  end

  test "outside strict mode only cited fragments are shown as sources" do
    assistant, _ = respond("Как вы начинали?", "ideas")
    assert_empty assistant.sources # модель ни на что не сослалась

    retrieved, _ = respond("Как вы начинали?", "strict")
    cited_ms = retrieved.sources.first["start_ms"]
    stamp = Recording.format_ms(cited_ms)

    @fake.define_singleton_method(:chat) do |parameters:|
      if parameters[:stream]
        parameters[:stream].call({ "choices" => [ { "delta" => { "content" => "Так было (из выступления «Конференция», #{stamp})." } } ] }, nil)
        return {}
      end
      { "choices" => [ { "message" => { "content" => "answer_question" } } ] }
    end
    assistant, _ = respond("Как вы начинали?", "ideas")
    assert_equal [ cited_ms ], assistant.sources.map { |s| s["start_ms"] }.uniq
  end

  test "ideas answer with markers renders materials as a collapsed block and the rest as the main text" do
    html = Conversations::BodyRenderer.call("[[МАТЕРИАЛЫ]]\nАвтор говорил про деньги.\n[[НОВОЕ]]\nА ещё есть инфляция.")
    assert_match(/<details class="from-materials"><summary>Что есть в ваших материалах<\/summary><p[^>]*>Автор говорил про деньги\./, html)
    assert_match(/<\/details><p[^>]*>А ещё есть инфляция\./, html)
    assert_not_includes html, "[["

    streaming = Conversations::BodyRenderer.call("[[МАТЕРИАЛЫ]]\nТекст\n[[НО", streaming: true)
    assert_not_includes streaming, "[["
    assert_equal "<p class=\"mb-3 last:mb-0\">Просто ответ.</p>", Conversations::BodyRenderer.call("Просто ответ.")
  end

  test "ideas prompt asks for the markers on answer-like intents only" do
    %w[answer_question casual_chat structure_knowledge].each do |intent|
      assert_includes Conversations::ContextBuilder.build_system(@persona, "ideas", intent), "[[НОВОЕ]]", intent
    end
    assert_not_includes Conversations::ContextBuilder.build_system(@persona, "ideas", "write_post"), "[[НОВОЕ]]"
    assert_not_includes Conversations::ContextBuilder.build_system(@persona, "strict", "answer_question"), "[[НОВОЕ]]"
  end
end
