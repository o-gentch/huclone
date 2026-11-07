# Адаптер ASR-провайдера. Реальный провайдер — AssemblyAI; в тестах — Fake.
module Transcription
  class Error < StandardError; end
  # Сеть, 429, 5xx — имеет смысл повторить
  class TransientError < Error; end
  # Битый файл, нет речи, отказ провайдера — повтор не поможет
  class PermanentError < Error; end

  class << self
    attr_writer :provider

    def provider
      @provider ||= build_provider
    end

    def reset!
      @provider = nil
    end

    private

    def build_provider
      return Fake.new if Rails.env.test?

      case ENV.fetch("TRANSCRIPTION_PROVIDER", "assemblyai")
      when "assemblyai" then AssemblyAi.new
      else raise ArgumentError, "Неизвестный TRANSCRIPTION_PROVIDER"
      end
    end
  end
end
