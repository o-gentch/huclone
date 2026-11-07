require "tmpdir"

class ExtractAudioJob < ApplicationJob
  queue_as :media

  discard_on ActiveJob::DeserializationError

  after_discard do |job, exception|
    Recording.find_by(id: job.arguments.first)&.fail!("Не удалось обработать файл: #{exception.message}")
  end

  # Идемпотентно: если аудио уже извлечено, просто двигаем запись дальше.
  def perform(recording_id)
    recording = Recording.find(recording_id)
    return unless recording.uploaded? || recording.extracting_audio?

    if recording.audio_file.attached?
      return advance(recording)
    end

    unless recording.source_file.attached?
      return recording.fail!("Исходный файл не найден — загрузите запись заново")
    end

    recording.advance!("extracting_audio")
    extract(recording)
  end

  private

  def extract(recording)
    blob = recording.source_file.blob
    Dir.mktmpdir("recording-#{recording.id}-") do |dir|
      needed = blob.byte_size * 2 + 200.megabytes
      if Media::AudioExtractor.free_bytes(dir) < needed
        return recording.fail!("На сервере недостаточно свободного места для обработки файла. Попробуйте позже")
      end

      blob.open(tmpdir: dir) do |file|
        result = Media::AudioExtractor.extract(file.path, dir: dir)

        if result[:duration_ms] > Recording::MAX_DURATION_MS
          return recording.fail!("Запись длиннее #{Recording::MAX_DURATION_MS / 3_600_000} часов — загрузите файл покороче")
        end

        File.open(result[:audio_path], "rb") do |audio|
          recording.audio_file.attach(io: audio, filename: "recording-#{recording.id}.mp3", content_type: "audio/mpeg")
        end
        recording.update!(duration_ms: result[:duration_ms])
      end
    end

    recording.source_file.purge unless Recording::KEEP_SOURCE
    advance(recording)
  rescue Media::InvalidMediaError => e
    recording.fail!(e.message)
  rescue Media::TimeoutError
    recording.fail!("Обработка файла заняла слишком много времени")
  rescue Media::CommandError => e
    recording.fail!("Не удалось обработать файл: #{e.message}")
  end

  def advance(recording)
    recording.advance!("transcribing")
    TranscribeRecordingJob.perform_later(recording.id)
  end
end
