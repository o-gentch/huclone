require "test_helper"

class ExtractAudioJobTest < ActiveJob::TestCase
  setup { @persona = users(:one).personas.create!(name: "P") }

  test "fails when the source file is missing" do
    recording = create_recording(@persona)
    ExtractAudioJob.perform_now(recording.id)
    assert recording.reload.failed?
  end

  test "if audio already exists it just moves on" do
    recording = create_recording(@persona, audio: true)
    assert_enqueued_with(job: TranscribeRecordingJob, args: [ recording.id ]) { ExtractAudioJob.perform_now(recording.id) }
    assert recording.reload.transcribing?
  end

  test "extracts audio, stores duration, drops the original" do
    skip "ffmpeg не установлен" unless Media::Command.available?("ffmpeg") && Media::Command.available?("ffprobe")
    recording = create_recording(@persona, source: true, duration_ms: nil)
    assert_enqueued_with(job: TranscribeRecordingJob) { ExtractAudioJob.perform_now(recording.id) }
    recording.reload
    assert recording.transcribing?
    assert recording.audio_file.attached?
    assert_not recording.source_file.attached?
    assert_in_delta 1000, recording.duration_ms, 200
  end

  test "garbage file is rejected with a clear message" do
    skip "ffmpeg не установлен" unless Media::Command.available?("ffprobe")
    recording = create_recording(@persona)
    recording.source_file.attach(io: StringIO.new("not media at all"), filename: "x.mp4", content_type: "video/mp4")
    ExtractAudioJob.perform_now(recording.id)
    assert recording.reload.failed?
    assert_match(/не удалось прочитать/, recording.error_message)
  end
end
