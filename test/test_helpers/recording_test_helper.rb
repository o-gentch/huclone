module RecordingTestHelper
  # Минимальный валидный WAV (тишина)
  def wav_data(seconds: 1, rate: 8000)
    samples = "\0\0".b * (rate * seconds)
    header = [ "RIFF", 36 + samples.bytesize, "WAVE", "fmt ", 16, 1, 1, rate, rate * 2, 2, 16, "data", samples.bytesize ]
                .pack("a4Va4a4VvvVVvva4V")
    header + samples
  end

  def create_recording(persona, status: "uploaded", audio: false, source: false, **attrs)
    status = "transcribed" if status == "confirmed" || status == "awaiting_speaker_confirmation"
    recording = persona.user.recordings.create!({ title: "Тест", status: status, duration_ms: 120_000 }.merge(attrs))
    PersonaRecordings::Connect.call(persona, recording)
    recording.audio_file.attach(io: StringIO.new(wav_data), filename: "a.wav", content_type: "audio/wav") if audio
    recording.source_file.attach(io: StringIO.new(wav_data), filename: "s.wav", content_type: "audio/wav") if source
    recording
  end
end

ActiveSupport.on_load(:active_support_test_case) { include RecordingTestHelper }
