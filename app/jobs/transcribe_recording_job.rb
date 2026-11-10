class TranscribeRecordingJob < ApplicationJob
  queue_as :transcription

  POLL_DELAYS = [ 15, 30, 60, 120 ].freeze # секунды, дальше — по 2 минуты
  MAX_WAIT = 60.minutes
  SUBMIT_RETRY_DELAY = 1.minute

  retry_on Transcription::TransientError, wait: :polynomially_longer, attempts: 6
  discard_on ActiveJob::DeserializationError

  after_discard do |job, exception|
    Recording.find_by(id: job.arguments.first)&.fail!(
      exception.is_a?(Transcription::TransientError) ? "Сервис распознавания временно недоступен. Нажмите «Повторить»" : exception.message
    )
  end

  # Не ждём результат внутри джоба: опрашиваем и перепланируем себя.
  # provider_job_id сохраняется сразу после отправки, поэтому повторный запуск
  # продолжает опрос и не отправляет (и не оплачивает) аудио второй раз.
  def perform(recording_id, poll = 0)
    recording = Recording.find(recording_id)
    return unless recording.transcribing?

    provider = Transcription.provider
    return unless recording.provider_job_id || submit(recording, provider)

    recording.touch # сигнал для watchdog: джоб жив
    case (result = provider.fetch(recording.provider_job_id))
    when :pending
      reschedule(recording, poll)
    else
      Recordings::SaveTranscript.call(recording, result)
    end
  rescue Transcription::PermanentError => e
    recording&.update!(provider_job_id: nil)
    recording&.fail!(e.message)
  end

  private

  # false — отправку отложили (лимит конкурентности или квота)
  def submit(recording, provider)
    if concurrent_limit_reached?(recording)
      self.class.set(wait: SUBMIT_RETRY_DELAY).perform_later(recording.id)
      return false
    end

    minutes = recording.duration_ms.to_f / 60_000
    user = recording.user
    Recordings::Quota.check!(user, minutes)

    job_id = recording.audio_file.blob.open do |file|
      provider.submit(file, expected_speakers: recording.expected_speakers, language: recording.language)
    end
    recording.update!(provider: provider.name, provider_job_id: job_id)
    Recordings::Quota.record!(user: user, recording: recording, minutes: minutes,
                              cost_usd: minutes / 60 * provider.cost_per_hour_usd)
    true
  rescue Recordings::QuotaExceeded => e
    recording.fail!(e.message)
    false
  end

  def concurrent_limit_reached?(recording)
    limit = ENV.fetch("TRANSCRIPTION_MAX_CONCURRENT", 5).to_i
    Recording.transcribing.where.not(provider_job_id: nil).where.not(id: recording.id).count >= limit
  end

  def reschedule(recording, poll)
    if Time.current - recording.status_changed_at > MAX_WAIT
      recording.fail!("Распознавание заняло слишком много времени. Нажмите «Повторить»")
    else
      delay = POLL_DELAYS.fetch(poll, POLL_DELAYS.last)
      self.class.set(wait: delay.seconds).perform_later(recording.id, poll + 1)
    end
  end
end
