require "test_helper"

class RecordingsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = users(:one)
    @persona = @owner.personas.create!(name: "P")
    Transcription.provider = Transcription::Fake.new
  end

  teardown { Transcription.reset! }

  def blob(content_type: "audio/wav", data: wav_data, filename: "talk.wav")
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(data), filename: filename, content_type: content_type)
  end

  test "anonymous user is redirected, foreign persona is 404" do
    get persona_recordings_path(@persona)
    assert_redirected_to new_session_path

    sign_in_as users(:two)
    get persona_recordings_path(@persona)
    assert_response :not_found
  end

  test "owner sees the list and the upload form" do
    sign_in_as @owner
    get persona_recordings_path(@persona)
    assert_response :success
    get new_persona_recording_path(@persona)
    assert_response :success
  end

  test "create attaches the uploaded blob and enqueues audio extraction" do
    sign_in_as @owner
    assert_enqueued_with(job: ExtractAudioJob) do
      post persona_recordings_path(@persona), params: { recording: { title: "Выступление", source_file: blob.signed_id, expected_speakers: "2" } }
    end
    recording = @persona.recordings.last
    assert_redirected_to persona_recording_path(@persona, recording)
    assert_equal "uploaded", recording.status
    assert_equal 2, recording.expected_speakers
    assert recording.source_file.attached?
    assert recording.source_checksum.present?
  end

  test "rejects unsupported content type" do
    sign_in_as @owner
    assert_no_difference -> { Recording.count } do
      post persona_recordings_path(@persona), params: { recording: { source_file: blob(content_type: "application/pdf", filename: "x.pdf", data: "%PDF-1.4 hello").signed_id } }
    end
    assert_response :unprocessable_entity
  end

  test "rejects missing and oversized files" do
    sign_in_as @owner
    post persona_recordings_path(@persona), params: { recording: { title: "x" } }
    assert_response :unprocessable_entity

    big = blob
    big.update_columns(byte_size: Recording.max_upload_bytes + 1)
    post persona_recordings_path(@persona), params: { recording: { source_file: big.signed_id } }
    assert_response :unprocessable_entity
    assert_equal 0, Recording.count
  end

  test "duplicate upload reuses the library recording and connects it to the DD" do
    sign_in_as @owner
    post persona_recordings_path(@persona), params: { recording: { source_file: blob.signed_id } }
    assert_equal 1, Recording.count

    dup = blob
    post persona_recordings_path(@persona), params: { recording: { source_file: dup.signed_id } }
    assert_redirected_to persona_recording_path(@persona, Recording.first)
    assert_equal 1, Recording.count

    second = @owner.personas.create!(name: "Second")
    post persona_recordings_path(second), params: { recording: { source_file: blob.signed_id } }
    assert_equal 1, Recording.count
    assert_equal 2, PersonaRecording.where(recording: Recording.first).count
  end

  test "exhausted quota blocks new uploads" do
    sign_in_as @owner
    @owner.usage_events.create!(kind: "transcription", quantity: 300)
    post persona_recordings_path(@persona), params: { recording: { source_file: blob.signed_id } }
    assert_response :unprocessable_entity
  end

  test "owner confirms the speaker" do
    sign_in_as @owner
    recording = create_recording(@persona, status: "transcribing", audio: true)
    Recordings::SaveTranscript.call(recording, Transcription::Fake.new.fetch("x"))

    get persona_recording_path(@persona, recording)
    assert_response :success
    assert_match "Кто из говорящих", response.body

    me = recording.speakers.find_by(label: "B")
    post confirm_persona_recording_path(@persona, recording), params: { speaker_ids: [ me.id ], names: { me.id => "Автор" } }
    assert_redirected_to persona_recording_path(@persona, recording)
    link = @persona.persona_recordings.find_by(recording: recording)
    assert link.ready?
    assert_equal [ me.id ], link.speaker_ids
  end

  test "confirm for a foreign persona's recording is 404" do
    other_persona = users(:two).personas.create!(name: "Other")
    recording = create_recording(other_persona, status: "transcribed")
    sign_in_as @owner
    post confirm_persona_recording_path(@persona, recording), params: { none: "1" }
    assert_response :not_found
  end

  test "audio is only served to the owner and supports ranges" do
    recording = create_recording(@persona, audio: true)
    get audio_persona_recording_path(@persona, recording)
    assert_redirected_to new_session_path

    sign_in_as users(:two)
    get audio_persona_recording_path(@persona, recording)
    assert_response :not_found

    sign_in_as @owner
    get audio_persona_recording_path(@persona, recording)
    assert_response :success
    assert_equal wav_data.bytesize, response.body.bytesize

    get audio_persona_recording_path(@persona, recording), headers: { "Range" => "bytes=0-99" }
    assert_response :partial_content
    assert_equal 100, response.body.bytesize
    assert_equal "bytes 0-99/#{wav_data.bytesize}", response.headers["Content-Range"]
  end

  test "retry re-enqueues the right stage; reprocess resets speakers" do
    sign_in_as @owner
    failed = create_recording(@persona, status: "failed", audio: true, provider_job_id: "keep")
    assert_enqueued_with(job: TranscribeRecordingJob, args: [ failed.id ]) do
      post retry_persona_recording_path(@persona, failed)
    end
    assert failed.reload.transcribing?
    assert_equal "keep", failed.provider_job_id # повторной отправки (и оплаты) нет

    no_files = create_recording(@persona, status: "failed")
    post retry_persona_recording_path(@persona, no_files)
    assert no_files.reload.failed?

    done = create_recording(@persona, status: "transcribing", audio: true)
    Recordings::SaveTranscript.call(done, Transcription::Fake.new.fetch("x"))
    assert_enqueued_with(job: TranscribeRecordingJob) do
      post reprocess_persona_recording_path(@persona, done), params: { expected_speakers: 3 }
    end
    done.reload
    assert done.transcribing?
    assert_equal 3, done.expected_speakers
    assert_equal 0, done.speakers.count
  end

  test "destroy removes the recording" do
    sign_in_as @owner
    recording = create_recording(@persona, audio: true)
    delete persona_recording_path(@persona, recording)
    assert_redirected_to persona_recordings_path(@persona)
    assert_not Recording.exists?(recording.id)
  end

  test "direct uploads require sign in and a valid type and size" do
    post rails_direct_uploads_path, params: { blob: { filename: "a.mp4", content_type: "video/mp4", byte_size: 10, checksum: "x" } }, as: :json
    assert_response :redirect

    sign_in_as @owner
    post rails_direct_uploads_path, params: { blob: { filename: "a.exe", content_type: "application/x-msdownload", byte_size: 10, checksum: "x" } }, as: :json
    assert_response :unprocessable_entity
    post rails_direct_uploads_path, params: { blob: { filename: "a.mp4", content_type: "video/mp4", byte_size: Recording.max_upload_bytes + 1, checksum: "x" } }, as: :json
    assert_response :unprocessable_entity
    post rails_direct_uploads_path, params: { blob: { filename: "a.mp4", content_type: "video/mp4", byte_size: 10, checksum: Base64.strict_encode64(Digest::MD5.digest("x")) } }, as: :json
    assert_response :success
  end

  test "default blob routes are not exposed" do
    blob = blob()
    get "/rails/active_storage/blobs/redirect/#{blob.signed_id}/talk.wav"
    assert_response :not_found
  end
end
