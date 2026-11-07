require "test_helper"

class Recordings::IngestTest < ActiveJob::TestCase
  class CleanClient
    def chat(parameters:)
      text = parameters[:messages].last[:content]
      { "choices" => [ { "message" => { "content" => text } } ] }
    end
  end

  setup do
    @persona = users(:one).personas.create!(name: "P")
    @recording = create_recording(@persona, status: "transcribing", audio: true)
    Recordings::SaveTranscript.call(@recording, Transcription::Fake.new.fetch("x"))
    me = @recording.speakers.find_by(label: "B")
    Recordings::Pipeline.after_confirm_handler = ->(_) { }
    Recordings::Confirm.call(@recording, speaker_id: me.id)
    @recording.reload
  end

  teardown { Recordings::Pipeline.after_confirm_handler = nil }

  test "creates speech contents with question context, timecodes and sources" do
    contents = Recordings::Ingest.call(@recording, ai_client: CleanClient.new)

    assert_equal contents.size, @persona.contents.speeches.count
    first = contents.first
    assert first.speech?
    assert_equal @recording.id, first.recording_id
    assert first.context_text.present?
    assert first.start_ms
    assert_equal "recording", first.sources.first["type"]
    assert_equal first.raw_body, first.body
    assert_enqueued_jobs contents.size, only: ProcessContentJob
  end

  test "is idempotent: rerun replaces earlier contents" do
    2.times { Recordings::Ingest.call(@recording, ai_client: CleanClient.new) }
    assert_equal Recordings::TurnBuilder.call(@recording).size, @persona.contents.speeches.count
  end

  test "confirmation enqueues ProcessRecordingJob only when a persona speaker exists" do
    Recordings::Pipeline.after_confirm_handler = nil
    assert_enqueued_with(job: ProcessRecordingJob, args: [ @recording.id ]) { Recordings::Pipeline.after_confirm(@recording) }
  end

  test "ProcessRecordingJob ignores unconfirmed recordings" do
    @recording.update!(status: "failed")
    assert_no_difference -> { Content.count } do
      ProcessRecordingJob.perform_now(@recording.id)
    end
  end

  test "deleting the recording removes its contents and chunks" do
    Recordings::Ingest.call(@recording, ai_client: CleanClient.new)
    content = @persona.contents.speeches.first
    content.chunks.create!(text: "x", position: 0)
    @recording.destroy!
    assert_equal 0, Content.speeches.count
    assert_equal 0, Chunk.count
  end
end
