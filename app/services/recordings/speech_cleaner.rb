module Recordings
  # LLM-очистка устной речи от слов-паразитов и повторов — для базы знаний.
  # Результат валидируется; при любом сомнении возвращается исходный текст.
  class SpeechCleaner
    MODEL = "gpt-4o-mini"
    MIN_RATIO = 0.60
    MAX_RATIO = 1.05
    MIN_KEYWORD_OVERLAP = 0.85
    MAX_WORDS = 1500

    PROMPT = <<~TEXT.freeze
      Ты редактор расшифровок устной речи. Очисти текст: убери слова-паразиты («ну», «вот», «как бы», «э-э»),
      заикания и дословные повторы, исправь очевидные ошибки распознавания.
      СТРОГО запрещено: перефразировать, менять смысл, добавлять новое, сокращать содержательные фрагменты,
      менять числа, имена и термины. Сохрани порядок и лексику говорящего. Верни только очищенный текст.
    TEXT

    def self.call(...) = new(...).call

    def initialize(text, ai_client: Ai::Client.instance)
      @text = text.to_s
      @client = ai_client
    end

    def call
      return @text if @text.split.size > MAX_WORDS * 1.2 # не должно случаться: ходы режутся заранее

      cleaned = Ai::Chat.call(
        stage: "speech_cleanup", client: @client, model: MODEL, temperature: 0,
        messages: [ { role: "system", content: PROMPT }, { role: "user", content: @text } ]
      ).strip
      valid?(cleaned) ? cleaned : @text
    rescue OpenAI::Error, Faraday::Error => e
      Rails.logger.warn("[SpeechCleaner] fallback to raw text: #{e.class}")
      @text
    end

    def valid?(cleaned)
      return false if cleaned.blank?

      ratio = cleaned.length.fdiv(@text.length)
      return false unless ratio.between?(MIN_RATIO, MAX_RATIO)
      return false unless numbers(@text).all? { |n| cleaned.include?(n) }

      keywords = keywords(@text)
      return true if keywords.empty?

      cleaned_words = cleaned.downcase.scan(/[[:alnum:]]+/).to_set
      keywords.count { |w| cleaned_words.include?(w) }.fdiv(keywords.size) >= MIN_KEYWORD_OVERLAP
    end

    private

    def numbers(text) = text.scan(/\d+/).uniq

    # Значимые слова (≥6 букв) — их потеря означает, что модель переписала текст
    def keywords(text) = text.downcase.scan(/[[:alpha:]]{6,}/).uniq
  end
end
