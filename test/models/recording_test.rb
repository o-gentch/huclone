require "test_helper"

class RecordingTest < ActiveSupport::TestCase
  setup { @persona = users(:one).personas.create!(name: "P") }

  test "status is constrained at the database level" do
    recording = create_recording(@persona)
    assert_raises(ActiveRecord::StatementInvalid) { recording.update_columns(status: "bogus") }
  end

  test "destroying a persona keeps library materials but drops the links" do
    recording = create_recording(@persona)
    @persona.destroy!
    assert Recording.exists?(recording.id)
    assert_equal 0, PersonaRecording.count
  end

  test "destroying a recording leaves no orphaned data" do
    recording = create_recording(@persona, status: "transcribing", audio: true)
    Recordings::SaveTranscript.call(recording, Transcription::Fake.new.fetch("x"))
    UsageEvent.create!(user: users(:one), recording: recording, kind: "transcription", quantity: 2)

    perform_enqueued = -> { ActiveStorage::Blob.where(id: recording.audio_file.blob.id).exists? }
    assert perform_enqueued.call

    recording.destroy!
    assert_equal 0, Recording.count
    assert_equal 0, PersonaRecording.count
    assert_equal 0, Speaker.count
    assert_equal 0, Utterance.count
    # учёт использования остаётся, чтобы квоту нельзя было обнулить удалением
    assert_equal 1, UsageEvent.where(recording_id: nil).count
  end

  test "formats timecodes" do
    assert_equal "1:05", Recording.format_ms(65_000)
    assert_equal "1:01:01", Recording.format_ms(3_661_000)
  end
end
