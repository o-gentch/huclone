require "test_helper"

class Recordings::SaveAndConfirmTest < ActiveSupport::TestCase
  setup do
    @persona = users(:one).personas.create!(name: "P")
    @recording = create_recording(@persona, status: "transcribing", audio: true)
    @result = Transcription::Fake.new.fetch("x")
  end

  test "saves speakers and utterances, computes stats, is idempotent" do
    2.times { Recordings::SaveTranscript.call(@recording, @result) }
    @recording.reload

    assert @recording.awaiting_speaker_confirmation?
    assert_equal 2, @recording.speakers.count
    assert_equal 4, @recording.utterances.count # две реплики A склеены
    top = @recording.speakers.max_by(&:speech_ms)
    assert_equal "B", top.label # в фикстуре «A» говорит больше, но появляется вторым -> метка B
    assert_operator top.words_count, :>, 0
  end

  test "confirm marks exactly one persona speaker and moves to confirmed" do
    Recordings::SaveTranscript.call(@recording, @result)
    me = @recording.speakers.find_by(label: "B")
    called = []
    Recordings::Pipeline.after_confirm_handler = ->(r) { called << r.id }

    Recordings::Confirm.call(@recording, speaker_id: me.id, names: { me.id.to_s => "Я" })

    assert @recording.reload.confirmed?
    assert_equal [ me.id ], @recording.speakers.where(is_persona: true).pluck(:id)
    assert_equal "Я", me.reload.display_name
    assert_equal [ @recording.id ], called
  ensure
    Recordings::Pipeline.after_confirm_handler = nil
  end

  test "confirm with none leaves no persona speaker" do
    Recordings::SaveTranscript.call(@recording, @result)
    Recordings::Confirm.call(@recording, speaker_id: nil)
    assert @recording.reload.confirmed?
    assert_equal 0, @recording.speakers.where(is_persona: true).count
  end

  test "confirm rejects a foreign speaker id and wrong status" do
    Recordings::SaveTranscript.call(@recording, @result)
    assert_raises(Recordings::Confirm::Invalid) { Recordings::Confirm.call(@recording, speaker_id: 0) }
    Recordings::Confirm.call(@recording, speaker_id: nil)
    assert_raises(Recordings::Confirm::Invalid) { Recordings::Confirm.call(@recording, speaker_id: nil) }
  end

  test "empty transcript is a permanent error" do
    empty = Transcription::Result.new(utterances: [ { speaker: "A", start_ms: 0, end_ms: 1, text: " ", confidence: 1 } ], duration_ms: 1)
    assert_raises(Transcription::PermanentError) { Recordings::SaveTranscript.call(@recording, empty) }
  end
end
