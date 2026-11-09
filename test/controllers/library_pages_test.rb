require "test_helper"

class LibraryPagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = users(:one)
    @persona = @owner.personas.create!(name: "Автор")
    sign_in_as @owner
  end

  test "content pages render with library-backed posts and removing a post only unlinks it from the DD" do
    other = @owner.personas.create!(name: "Другой")
    post_content = add_content(@persona, kind: "post", title: "Мой пост", body: "текст", status: "done", is_exemplar: true)
    PersonaContent.create!(persona: other, content: post_content, role: "knowledge")

    get persona_contents_path(@persona)
    assert_response :success
    assert_match "Мой пост", response.body
    assert_match "эталон", response.body

    delete persona_content_path(@persona, post_content)
    assert Content.exists?(post_content.id) # подключён к другому DD
    assert_equal 0, @persona.persona_contents.count

    delete persona_content_path(other, post_content)
    assert_not Content.exists?(post_content.id)
  end

  test "removing a voice post resets the personality map" do
    post_content = add_content(@persona, kind: "post", title: "p", body: "текст", status: "done", included_in_map: true)
    @persona.update!(personality_map: { "core_beliefs" => [ "x" ] }, personality_map_built_at: Time.current)

    assert_enqueued_with(job: Knowledge::BuildTopicTreeJob) do
      Personas::RemoveContents.call(@persona, [ post_content.id ])
    end
    assert_empty @persona.reload.personality_map
  end

  test "recordings page shows the speaker chooser and which other DD picked a speaker" do
    other = @owner.personas.create!(name: "Учитель")
    recording = create_recording(@persona, status: "transcribing", audio: true)
    Recordings::SaveTranscript.call(recording, Transcription::Fake.new.fetch("x"))
    speaker = recording.speakers.find_by(label: "A")
    PersonaRecordings::SelectSpeakers.call(PersonaRecordings::Connect.call(other, recording), speaker_ids: [ speaker.id ])

    get persona_recordings_path(@persona)
    assert_response :success
    assert_match "нужно выбрать спикера", response.body

    get persona_recording_path(@persona, recording)
    assert_response :success
    assert_match "выбран у: Учитель", response.body
    assert_match "speaker_ids[]", response.body
  end
end
