require "faraday"

module Transcription
  # AssemblyAI: POST /v2/upload -> POST /v2/transcript -> GET /v2/transcript/:id
  # Ключ — ENV["ASSEMBLYAI_API_KEY"] или credentials.assemblyai.api_key.
  # Русский поддерживает модель universal-2; цена ≈ $0.15/ч + $0.02/ч диаризация.
  class AssemblyAi < Provider
    BASE_URL = ENV.fetch("ASSEMBLYAI_BASE_URL", "https://api.assemblyai.com")
    SPEECH_MODELS = [ "universal-2" ].freeze
    COST_PER_HOUR_USD = 0.17

    def initialize(api_key: nil, connection: nil)
      @api_key = api_key.presence || ENV["ASSEMBLYAI_API_KEY"].presence ||
                 Rails.application.credentials.dig(:assemblyai, :api_key)
      @connection = connection
    end

    def cost_per_hour_usd = COST_PER_HOUR_USD

    def submit(io, expected_speakers: nil, language: "ru")
      raise PermanentError, "Не задан ASSEMBLYAI_API_KEY" if @api_key.blank?

      upload = request { conn.post("/v2/upload", io, "content-type" => "application/octet-stream") }
      body = {
        audio_url: upload.fetch("upload_url"),
        language_code: language,
        speech_models: SPEECH_MODELS,
        speaker_labels: true,
        punctuate: true
      }
      body[:speakers_expected] = expected_speakers if expected_speakers

      request { conn.post("/v2/transcript", body.to_json, "content-type" => "application/json") }.fetch("id")
    end

    def fetch(job_id)
      data = request { conn.get("/v2/transcript/#{job_id}") }
      case data["status"]
      when "queued", "processing" then :pending
      when "error" then raise PermanentError, "Ошибка распознавания: #{data['error']}".truncate(300)
      when "completed" then parse(data)
      else raise TransientError, "Неожиданный статус провайдера: #{data['status']}"
      end
    end

    private

    def parse(data)
      utterances = Array(data["utterances"]).map do |u|
        { speaker: u["speaker"].to_s, start_ms: u["start"].to_i, end_ms: u["end"].to_i,
          text: u["text"].to_s, confidence: u["confidence"]&.to_f }
      end
      raise PermanentError, "В записи не найдено речи" if utterances.empty?

      Result.new(utterances: utterances, duration_ms: (data["audio_duration"].to_f * 1000).round)
    end

    def request
      response = yield
      case response.status
      when 200..299 then JSON.parse(response.body)
      when 429, 500..599 then raise TransientError, "Провайдер вернул #{response.status}"
      when 401, 403 then raise PermanentError, "Провайдер отклонил ключ доступа (#{response.status})"
      else raise PermanentError, "Провайдер отклонил запрос (#{response.status}): #{response.body.to_s.truncate(200)}"
      end
    rescue Faraday::Error, JSON::ParserError => e
      raise TransientError, "Сетевая ошибка: #{e.class}"
    end

    def conn
      @connection ||= Faraday.new(url: BASE_URL, headers: { "authorization" => @api_key }) do |f|
        f.options.timeout = 600
        f.options.open_timeout = 15
      end
    end
  end
end
