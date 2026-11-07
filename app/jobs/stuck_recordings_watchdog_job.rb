# Раз в 10 минут: находит записи, у которых потерялся джоб, и перезапускает стадию либо помечает failed.
class StuckRecordingsWatchdogJob < ApplicationJob
  queue_as :media

  EXTRACT_STALE_AFTER = 20.minutes
  TRANSCRIBE_STALE_AFTER = 10.minutes # poll-джоб делает touch не реже раза в 2 минуты
  TRANSCRIBE_MAX_TOTAL = 75.minutes

  def perform
    Recording.where(status: %w[uploaded extracting_audio]).where(status_changed_at: ...EXTRACT_STALE_AFTER.ago).find_each do |r|
      ExtractAudioJob.perform_later(r.id)
      r.touch
    end

    Recording.transcribing.where(updated_at: ...TRANSCRIBE_STALE_AFTER.ago).find_each do |r|
      if r.status_changed_at < TRANSCRIBE_MAX_TOTAL.ago
        r.fail!("Распознавание не завершилось вовремя. Нажмите «Повторить»")
      else
        TranscribeRecordingJob.perform_later(r.id)
        r.touch
      end
    end
  end
end
