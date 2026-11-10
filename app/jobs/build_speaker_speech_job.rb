class BuildSpeakerSpeechJob < ApplicationJob
  queue_as :content_processing

  limits_concurrency to: 1, key: ->(speaker_id) { "speaker_speech/#{speaker_id}" }, duration: 30.minutes

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  after_discard { |job, _| Recordings::SpeakerSpeech.reset!(job.arguments.first) }

  def perform(speaker_id)
    speaker = Speaker.find(speaker_id)
    return unless speaker.speech_state == "building"

    Recordings::Ingest.call(speaker.recording, speaker: speaker)
    Recordings::SpeakerSpeech.finished!(speaker)
  end
end
