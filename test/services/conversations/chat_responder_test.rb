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
end
