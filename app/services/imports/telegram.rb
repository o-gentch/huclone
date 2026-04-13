module Imports
  class Telegram
    MIN_TEXT_LENGTH = 100

    def self.call(persona:, file:) = new(persona:, file:).call

    def initialize(persona:, file:)
      @persona = persona
      @file = file
    end

    def call
      data     = parse_json!
      messages = data["messages"] || []
      channel  = data["name"]

      imported = 0
      skipped  = 0

      messages.each do |msg|
        next unless msg["type"] == "message"

        text = extract_text(msg["text"])
        next if text.length < MIN_TEXT_LENGTH
        next unless Filters.content_post?(text)

        content = @persona.contents.create!(
          title:   Contents::TitleBuilder.build(text),
          body:    text,
          sources: [ { type: "telegram", date: msg["date"], channel: channel } ],
          status:  "pending"
        )
        ProcessContentJob.perform_later(content.id)
        imported += 1
      rescue StandardError
        skipped += 1
      end

      { imported: imported, skipped: skipped }
    end

    private

    def parse_json!
      JSON.parse(@file.read.encode("UTF-8", invalid: :replace, undef: :replace, replace: ""))
    end

    def extract_text(raw)
      text = case raw
      when String then raw
      when Array  then raw.filter_map { |part| part.is_a?(Hash) ? part["text"] : part }.join
      else ""
      end

      text.gsub("\u0000", "").strip
    end
  end
end
