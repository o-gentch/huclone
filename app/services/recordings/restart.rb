module Recordings
  # Повтор упавшей записи с нужной стадии и «перераспознать с N спикерами».
  module Restart
    module_function

    # Продолжает с того места, где остановились; provider_job_id сохраняется —
    # чтобы не платить за повторную отправку, если результат у провайдера уже есть.
    def retry!(recording)
      raise ArgumentError, "Повтор невозможен" unless recording.retryable?

      if recording.audio_file.attached?
        recording.advance!("transcribing")
        TranscribeRecordingJob.perform_later(recording.id)
      else
        recording.advance!("uploaded")
        ExtractAudioJob.perform_later(recording.id)
      end
    end

    def redo_with_speakers!(recording, count)
      raise ArgumentError, "Нужно аудио" unless recording.audio_file.attached?

      Recording.transaction do
        # Спикеры будут созданы заново — выбор у всех персон сбрасывается
        recording.persona_recordings.each do |pr|
          Personas::RemoveContents.call(pr.persona, pr.persona_contents.pluck(:content_id))
          pr.update!(speaker_ids: [], status: "needs_speakers", summary: nil)
        end
        recording.contents.destroy_all
        recording.utterances.delete_all
        recording.speakers.delete_all
        recording.update!(expected_speakers: count, provider_job_id: nil)
        recording.advance!("transcribing")
      end
      TranscribeRecordingJob.perform_later(recording.id)
    end
  end
end
