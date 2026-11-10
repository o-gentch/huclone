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
    @me = @recording.speakers.find_by(label: "B")
    @recording.reload
  end

  def ingest = Recordings::Ingest.call(@recording, speaker: @me, ai_client: CleanClient.new)

  test "creates speech contents for the speaker with question context, timecodes and sources" do
    contents = ingest

    assert_equal contents.size, Content.speeches.where(recording: @recording).count
    first = contents.first
    assert first.speech?
    assert_equal @me.id, first.speaker_id
    assert_equal @recording.user_id, first.user_id
    assert first.context_text.present?
    assert first.start_ms
    assert_equal "recording", first.sources.first["type"]
    assert_equal first.raw_body, first.body
    assert_enqueued_jobs contents.size, only: ProcessContentJob
  end

  test "is idempotent: rerun replaces earlier contents" do
    2.times { ingest }
    assert_equal Recordings::TurnBuilder.call(@recording, speaker: @me).size, Content.speeches.where(recording: @recording).count
  end

  test "selecting a speaker builds speech once and syncs it to every Digital Double" do
    other = users(:one).personas.create!(name: "Q")
    other_link = PersonaRecordings::Connect.call(other, @recording)
    link = @persona.persona_recordings.first

    assert_enqueued_jobs 1, only: BuildSpeakerSpeechJob do
      PersonaRecordings::SelectSpeakers.call(link, speaker_ids: [ @me.id ])
      PersonaRecordings::SelectSpeakers.call(other_link, speaker_ids: [ @me.id ])
    end
    assert_equal "building", @me.reload.speech_state

    Recordings::Ingest.call(@recording, speaker: @me, ai_client: CleanClient.new)
    Recordings::SpeakerSpeech.finished!(@me)

    assert_equal "ready", @me.reload.speech_state
    count = Content.speeches.where(recording: @recording).count
    assert_operator count, :>, 0
    assert_equal count, @persona.contents.speeches.count
    assert_equal count, other.contents.speeches.count

    # третий DD выбирает уже готового спикера — обработка не запускается
    third = users(:one).personas.create!(name: "R")
    third_link = PersonaRecordings::Connect.call(third, @recording)
    assert_no_enqueued_jobs only: BuildSpeakerSpeechJob do
      PersonaRecordings::SelectSpeakers.call(third_link, speaker_ids: [ @me.id ])
    end
    assert_equal count, third.contents.speeches.count
    assert_equal count, Content.speeches.count
  end

  test "changing the selection removes the speaker's fragments from that DD only" do
    other = users(:one).personas.create!(name: "Q")
    other_link = PersonaRecordings::Connect.call(other, @recording)
    link = @persona.persona_recordings.first
    [ link, other_link ].each { |l| PersonaRecordings::SelectSpeakers.call(l, speaker_ids: [ @me.id ]) }
    Recordings::Ingest.call(@recording, speaker: @me, ai_client: CleanClient.new)
    Recordings::SpeakerSpeech.finished!(@me)

    PersonaRecordings::SelectSpeakers.call(link, speaker_ids: [])
    assert_equal 0, @persona.contents.speeches.count
    assert_operator other.contents.speeches.count, :>, 0
    assert link.reload.ready?
  end

  test "deleting the recording removes its contents, links and chunks" do
    ingest
    content = Content.speeches.first
    content.chunks.create!(text: "x", position: 0)
    @recording.destroy!
    assert_equal 0, Content.speeches.count
    assert_equal 0, Chunk.count
    assert_equal 0, PersonaContent.count
  end
end
