module Transcription
  # Интерфейс провайдера.
  #   submit(io, expected_speakers:, language:) -> job_id (String)
  #   fetch(job_id) -> Result | :pending   (PermanentError/TransientError при сбоях)
  #   cost_per_hour_usd -> Float (оценка для usage_events)
  class Provider
    def submit(_io, expected_speakers: nil, language: "ru") = raise(NotImplementedError)
    def fetch(_job_id) = raise(NotImplementedError)
    def name = self.class.name.demodulize.underscore
    def cost_per_hour_usd = 0.0
  end
end
