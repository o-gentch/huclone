require "test_helper"

class Recordings::SaveAndConfirmTest < ActiveJob::TestCase
  setup do
    @persona = users(:one).personas.create!(name: "P")
    @recording = create_recording(@persona, status: "transcribing", audio: true)
    @link = @persona.persona_recordings.first
    @result = Transcription::Fake.new.fetch("x")
  end

  test "saves speakers and utterances, computes stats, is idempotent" do
    2.times { Recordings::SaveTranscript.call(@recording, @result) }
    @recording.reload

    assert @recording.transcribed?
    assert @link.reload.needs_speakers?
    assert_equal 2, @recording.speakers.count
    assert_equal 4, @recording.utterances.count # две реплики A склеены
    top = @recording.speakers.max_by(&:speech_ms)
    assert_equal "B", top.label # в фикстуре «A» говорит больше, но появляется вторым -> метка B
    assert_operator top.words_count, :>, 0
  end

  test "select speakers stores several speakers and names" do
    Recordings::SaveTranscript.call(@recording, @result)
    a, b = @recording.speakers.order(:label).to_a

    assert_enqueued_jobs 2, only: BuildSpeakerSpeechJob do
      PersonaRecordings::SelectSpeakers.call(@link, speaker_ids: [ a.id, b.id ], names: { b.id.to_s => "Я" })
    end

    assert @link.reload.ready?
    assert_equal [ a.id, b.id ].sort, @link.speaker_ids
    assert_equal "Я", b.reload.display_name
  end

  test "none means the person is not in the recording" do
    Recordings::SaveTranscript.call(@recording, @result)
    PersonaRecordings::SelectSpeakers.call(@link, speaker_ids: [])
    assert @link.reload.ready?
    assert_empty @link.speaker_ids
  end

  test "rejects a foreign speaker id and an untranscribed recording" do
    assert_raises(PersonaRecordings::SelectSpeakers::Invalid) { PersonaRecordings::SelectSpeakers.call(@link, speaker_ids: [ 1 ]) }
    Recordings::SaveTranscript.call(@recording, @result)
    assert_raises(PersonaRecordings::SelectSpeakers::Invalid) { PersonaRecordings::SelectSpeakers.call(@link.reload, speaker_ids: [ 0 ]) }
  end

  test "empty transcript is a permanent error" do
    empty = Transcription::Result.new(utterances: [ { speaker: "A", start_ms: 0, end_ms: 1, text: " ", confidence: 1 } ], duration_ms: 1)
    assert_raises(Transcription::PermanentError) { Recordings::SaveTranscript.call(@recording, empty) }
  end
end
