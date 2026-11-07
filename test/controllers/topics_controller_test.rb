require "test_helper"

class TopicsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @persona = users(:one).personas.create!(name: "Автор")
    @recording = create_recording(@persona, status: "confirmed", title: "Конференция")
    n = 0
    2.times { |c| 8.times { create_speech(@persona, @recording, c, n += 1) } }
    Knowledge::TopicTreeBuilder.call(@persona, ai_client: NamingClient.new)
  end

  test "requires sign in and ownership" do
    get persona_topics_path(@persona)
    assert_redirected_to new_session_path
    sign_in_as users(:two)
    get persona_topics_path(@persona)
    assert_response :not_found
  end

  test "owner sees the tree with fragment links, can export and rebuild" do
    sign_in_as users(:one)
    get persona_topics_path(@persona)
    assert_response :success
    assert_match "Тема", response.body
    assert_match "#t=", response.body

    get export_persona_topics_path(@persona)
    assert_response :success
    assert_match "text/markdown", response.content_type
    assert_match "# Оглавление", response.body

    assert_enqueued_with(job: Knowledge::BuildTopicTreeJob, args: [ @persona.id, true ]) do
      post rebuild_persona_topics_path(@persona)
    end
  end

  test "empty state" do
    sign_in_as users(:two)
    other = users(:two).personas.create!(name: "Пусто")
    get persona_topics_path(other)
    assert_match "Тем пока нет", response.body
  end
end
