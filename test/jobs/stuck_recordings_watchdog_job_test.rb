require "test_helper"

class StuckRecordingsWatchdogJobTest < ActiveJob::TestCase
  setup { @persona = users(:one).personas.create!(name: "P") }

  test "restarts a stale transcribing recording and fails an overdue one" do
    stale = create_recording(@persona, status: "transcribing", audio: true, provider_job_id: "j")
    stale.update_columns(updated_at: 30.minutes.ago)
    overdue = create_recording(@persona, status: "transcribing", audio: true)
    overdue.update_columns(updated_at: 2.hours.ago, status_changed_at: 2.hours.ago)
    fresh = create_recording(@persona, status: "transcribing", audio: true)

    assert_enqueued_with(job: TranscribeRecordingJob, args: [ stale.id ]) { StuckRecordingsWatchdogJob.perform_now }

    assert overdue.reload.failed?
    assert fresh.reload.transcribing?
  end

  test "restarts stale extraction" do
    r = create_recording(@persona, status: "extracting_audio", source: true)
    r.update_columns(status_changed_at: 1.hour.ago)
    assert_enqueued_with(job: ExtractAudioJob, args: [ r.id ]) { StuckRecordingsWatchdogJob.perform_now }
  end
end
