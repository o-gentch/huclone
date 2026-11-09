require "test_helper"

class Knowledge::SummarizeTest < ActiveJob::TestCase
  setup do
    @persona = users(:one).personas.create!(name: "Автор")
    @recording = create_recording(@persona, status: "confirmed", title: "Лекция")
    3.times { |i| create_speech(@persona, @recording, 0, i + 1, summary: nil) }
  end

  test "summarizes fragments then the whole recording" do
    client = NamingClient.new
    Knowledge::RecordingSummarizer.call(@persona.persona_recordings.find_by(recording: @recording), ai_client: client)
    assert @persona.contents.speeches.all? { |c| c.reload.summary.present? }
    assert @persona.persona_recordings.first.reload.summary.present?
    assert_equal 4, client.calls # 3 фрагмента + 1 свёртка
  end

  test "already summarized fragments are not re-summarized" do
    Content.update_all(summary: "уже есть")
    client = NamingClient.new
    Knowledge::RecordingSummarizer.call(@persona.persona_recordings.find_by(recording: @recording), ai_client: client)
    assert_equal 1, client.calls
  end

  test "completion of the last fragment triggers summarization and a debounced map build" do
    Content.speeches.update_all(status: "done")
    content = Content.speeches.first
    assert_enqueued_with(job: Knowledge::SummarizeRecordingJob, args: [ @persona.persona_recordings.first.id ]) do
      ProcessContentJob.signal_completion(content.id)
    end
    assert_enqueued_jobs 1, only: BuildPersonalityMapJob

    assert_no_enqueued_jobs(only: BuildPersonalityMapJob) { ProcessContentJob.signal_completion(content.id) } # дебаунс
    BuildPersonalityMapJob.perform_now(@persona.id) rescue nil
    assert_nil @persona.reload.map_build_scheduled_at
  end

  test "pending fragments postpone summarization and map build" do
    Content.speeches.update_all(status: "done")
    Content.speeches.first.update!(status: "pending")
    assert_no_enqueued_jobs { ProcessContentJob.signal_completion(Content.speeches.last.id) }
  end
end
