require "test_helper"

class LibraryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @persona = @owner.personas.create!(name: "Маркетинг")
    @other = @owner.personas.create!(name: "Английский")
    @video = create_recording(@persona, status: "transcribing", audio: true, title: "Вебинар про воронки")
    Recordings::SaveTranscript.call(@video, Transcription::Fake.new.fetch("x"))
    @post = @owner.contents.create!(title: "Пост про охваты", body: "Алгоритмы любят вовлечённость", status: "done",
                                    sources: [ { type: "telegram", channel: "Канал X" } ])
    @free = @owner.contents.create!(title: "Свободный", body: "ничей", status: "done", sources: [ { type: "manual" } ])
    sign_in_as @owner
  end

  test "lists videos and posts with their connections" do
    get library_path
    assert_response :success
    assert_match "Вебинар про воронки", response.body
    assert_match "Пост про охваты", response.body
    assert_match "Маркетинг", response.body
    assert_match "Telegram · Канал X · 1", response.body
  end

  test "filters by text, type, source and connection" do
    PersonaContent.create!(persona: @persona, content: @post)

    get library_path(q: "вовлечённость")
    assert_match "Пост про охваты", response.body
    assert_no_match "Вебинар про воронки", response.body

    get library_path(type: "video")
    assert_match "Вебинар", response.body
    assert_no_match "Пост про охваты", response.body

    get library_path(source: "telegram:Канал X")
    assert_match "Пост про охваты", response.body
    assert_no_match "Свободный", response.body

    get library_path(dd: "none")
    assert_match "Свободный", response.body
    assert_no_match "Пост про охваты", response.body

    get library_path(dd: @persona.id)
    assert_match "Пост про охваты", response.body
    assert_no_match "Свободный", response.body
  end

  test "paginates by 50" do
    55.times { |i| @owner.contents.create!(title: "Много #{i}", body: "b", status: "done", sources: []) }
    get library_path
    assert_match "Страница 1 из 2", response.body
    get library_path(page: 2)
    assert_response :success
  end

  test "bulk connect posts as knowledge and videos, then delete" do
    post connect_library_path, params: { persona_id: @other.id, role: "knowledge", items: [ "content_#{@post.id}", "recording_#{@video.id}" ] }
    assert_equal "knowledge", PersonaContent.find_by(persona: @other, content: @post).role
    assert PersonaRecording.exists?(persona: @other, recording: @video)

    post delete_library_path, params: { items: [ "content_#{@post.id}", "recording_#{@video.id}" ] }
    assert_not Content.exists?(@post.id)
    assert_not Recording.exists?(@video.id)
    assert_equal 0, PersonaRecording.count
  end

  test "recording page shows connections; disconnect keeps the recording" do
    get library_recording_path(@video)
    assert_response :success
    assert_match "Маркетинг", response.body

    delete library_recording_persona_path(@video, @persona)
    assert Recording.exists?(@video.id)
    assert_equal 0, PersonaRecording.count
  end

  test "other users' items are untouchable" do
    foreign = users(:two).contents.create!(title: "Чужое", body: "b", status: "done", sources: [])
    post delete_library_path, params: { items: [ "content_#{foreign.id}" ] }
    assert Content.exists?(foreign.id)

    get library_recording_path(create_recording(users(:two).personas.create!(name: "X")))
    assert_response :not_found
  end
end
