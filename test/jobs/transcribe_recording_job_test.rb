require "test_helper"

class TranscribeRecordingJobTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @persona = @user.personas.create!(name: "P")
    @recording = create_recording(@persona, status: "transcribing", audio: true)
    @fake = Transcription::Fake.new
    Transcription.provider = @fake
  end

  teardown { Transcription.reset! }

  test "submits once, stores speakers and moves to awaiting confirmation" do
    TranscribeRecordingJob.perform_now(@recording.id)
    @recording.reload
    assert @recording.awaiting_speaker_confirmation?
    assert_equal "fake-1", @recording.provider_job_id
    assert_equal 2, @recording.speakers.count
    assert_equal 1, @fake.submit_count
    assert_equal 1, UsageEvent.where(user: @user, recording: @recording).count
  end

  test "pending result reschedules polling and never resubmits audio" do
    @fake.pending_polls = 1
    assert_enqueued_with(job: TranscribeRecordingJob, args: [ @recording.id, 1 ]) do
      TranscribeRecordingJob.perform_now(@recording.id)
    end
    assert @recording.reload.transcribing?

    TranscribeRecordingJob.perform_now(@recording.id, 1)
    assert @recording.reload.awaiting_speaker_confirmation?
    assert_equal 1, @fake.submit_count
    assert_equal 1, UsageEvent.count
  end

  test "rerun after completion does nothing" do
    TranscribeRecordingJob.perform_now(@recording.id)
    assert_no_difference -> { Speaker.count } do
      TranscribeRecordingJob.perform_now(@recording.id)
    end
  end

  test "permanent provider error fails the recording" do
    @fake.submit_error = Transcription::PermanentError.new("Файл повреждён")
    TranscribeRecordingJob.perform_now(@recording.id)
    @recording.reload
    assert @recording.failed?
    assert_equal "Файл повреждён", @recording.error_message
  end

  test "transient error is retried, then fails with a clear message once attempts are exhausted" do
    @fake.fetch_error = Transcription::TransientError.new("503")
    @recording.update!(provider_job_id: "x")
    job = TranscribeRecordingJob.new(@recording.id)
    6.times do
      begin
        job.perform_now
      rescue Transcription::TransientError
        nil
      end
    end
    assert @recording.reload.failed?
    assert_match(/временно недоступен/, @recording.error_message)
  end

  test "quota exceeded fails before sending audio to the provider" do
    @user.usage_events.create!(kind: "transcription", quantity: 299)
    TranscribeRecordingJob.perform_now(@recording.id)
    assert @recording.reload.failed?
    assert_match(/квот/, @recording.error_message)
    assert_equal 0, @fake.submit_count
  end

  test "concurrency limit postpones submission" do
    ENV["TRANSCRIPTION_MAX_CONCURRENT"] = "1"
    other = create_recording(@persona, status: "transcribing", audio: true, provider_job_id: "busy")
    assert_enqueued_with(job: TranscribeRecordingJob) { TranscribeRecordingJob.perform_now(@recording.id) }
    assert_equal 0, @fake.submit_count
    assert other.reload.transcribing?
  ensure
    ENV.delete("TRANSCRIPTION_MAX_CONCURRENT")
  end

  test "ignores recordings that are not transcribing" do
    @recording.update!(status: "failed")
    TranscribeRecordingJob.perform_now(@recording.id)
    assert_equal 0, @fake.submit_count
  end
end
