require "test_helper"

class DigitalDoublesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = users(:one)
    @persona = @owner.personas.create!(name: "Маркетинг")
    @other = @owner.personas.create!(name: "Английский")
    sign_in_as @owner
  end

  test "sidebar lists every Digital Double and the settings page edits instructions" do
    get persona_contents_path(@other)
    assert_response :success
    assert_match "Маркетинг", response.body
    assert_match "＋ Новый Digital Double", response.body

    get edit_persona_path(@persona)
    assert_response :success
    patch persona_path(@persona), params: { persona: { name: "Маркетолог", system_prompt: "Отвечай кратко" } }
    assert_redirected_to edit_persona_path(@persona)
    assert_equal "Отвечай кратко", @persona.reload.system_prompt
  end

  test "instructions reach the system prompt" do
    @persona.update!(system_prompt: "Ты учитель английского")
    assert_includes Conversations::ContextBuilder.build_system(@persona, "strict", "answer_question"), "Ты учитель английского"
  end

  test "deleting a Digital Double keeps library materials" do
    content = add_content(@persona, kind: "post", title: "p", body: "b", status: "done")
    delete persona_path(@persona)
    assert Content.exists?(content.id)
    assert_equal 0, PersonaContent.count
  end

  test "other users' Digital Doubles are not editable" do
    foreign = users(:two).personas.create!(name: "X")
    get edit_persona_path(foreign)
    assert_response :not_found
  end

  test "manual exemplar choice survives automatic selection" do
    short = add_content(@persona, kind: "post", title: "s", body: "коротко", status: "done")
    8.times { |i| add_content(@persona, kind: "post", title: "l#{i}", body: "длинный " * (50 + i), status: "done") }

    post toggle_exemplar_persona_content_path(@persona, short)
    Personas::ExemplarSelector.call(@persona)

    links = @persona.persona_contents
    assert links.find_by(content: short).is_exemplar
    assert_equal 7, links.where(is_exemplar: true).count

    post toggle_exemplar_persona_content_path(@persona, short)
    Personas::ExemplarSelector.call(@persona)
    assert_not links.find_by(content: short).is_exemplar
  end

  test "failed posts can be retried" do
    content = add_content(@persona, kind: "post", title: "p", body: "b", status: "failed")
    assert_enqueued_with(job: ProcessContentJob, args: [ content.id ]) do
      post retry_persona_content_path(@persona, content)
    end
    assert content.reload.pending?
  end

  test "chats can be deleted" do
    conversation = @persona.conversations.create!
    delete persona_conversation_path(@persona, conversation)
    assert_equal 0, Conversation.count
  end

  test "telegram re-import does not duplicate and connects known posts to another DD" do
    text = "Это достаточно длинный пост для импорта из телеграма, " * 4
    json = { "name" => "Канал", "messages" => [ { "id" => 7, "type" => "message", "date" => "2026-01-01", "text" => text } ] }.to_json
    file = ->(io = json) { StringIO.new(io) }

    assert_equal 1, Imports::Telegram.call(persona: @persona, file: file.call)[:imported]
    assert_equal 0, Imports::Telegram.call(persona: @persona, file: file.call)[:imported]
    assert_equal 0, Imports::Telegram.call(persona: @other, file: file.call)[:imported]
    assert_equal 1, Content.count
    assert_equal 2, PersonaContent.count
  end
end
