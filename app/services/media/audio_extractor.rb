require "json"

module Media
  class InvalidMediaError < StandardError; end

  # ffprobe/ffmpeg: проверка файла и извлечение моно 16 кГц mp3 ~48 кбит/с.
  class AudioExtractor
    BITRATE = "48k"
    SAMPLE_RATE = "16000"
    FFMPEG_THREADS = "2"
    TIMEOUT = 30.minutes.to_i

    # Возвращает { duration_ms:, audio_path: } — файл лежит в dir, очистка за вызывающим.
    def self.extract(input_path, dir:)
      info = probe(input_path)
      output = File.join(dir, "audio.mp3")
      Command.run("nice", "-n", "10", "ffmpeg", "-nostdin", "-y", "-v", "error",
                  "-threads", FFMPEG_THREADS, "-i", input_path, "-vn", "-map", "0:a:0",
                  "-ac", "1", "-ar", SAMPLE_RATE, "-c:a", "libmp3lame", "-b:a", BITRATE,
                  output, timeout: TIMEOUT)
      { duration_ms: info[:duration_ms], audio_path: output }
    end

    # Проверяет, что это медиафайл с аудиодорожкой; возвращает длительность.
    def self.probe(path)
      out = Command.run("ffprobe", "-v", "error", "-print_format", "json",
                        "-show_format", "-show_streams", path, timeout: 60).stdout
      data = JSON.parse(out)
      raise InvalidMediaError, "В файле нет аудиодорожки" unless Array(data["streams"]).any? { |s| s["codec_type"] == "audio" }

      seconds = data.dig("format", "duration").to_f
      raise InvalidMediaError, "Не удалось определить длительность" unless seconds.positive?

      { duration_ms: (seconds * 1000).round }
    rescue JSON::ParserError
      raise InvalidMediaError, "Файл не удалось прочитать как аудио или видео"
    rescue TimeoutError
      raise
    rescue CommandError => e
      raise if e.message.include?("не установлен")
      raise InvalidMediaError, "Файл не удалось прочитать как аудио или видео"
    end

    # Свободное место (байт) на разделе, где лежит dir
    def self.free_bytes(dir)
      line = Command.run("df", "-Pk", dir, timeout: 10).stdout.lines.last.to_s.split
      line[3].to_i * 1024
    end
  end
end
