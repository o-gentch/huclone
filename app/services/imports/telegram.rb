module Imports
  class Telegram
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
        next if text.blank?

        content = @persona.contents.create!(
          title:   Content::TitleBuilder.build(text),
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
      JSON.parse(@file.read.force_encoding("UTF-8"))
    end

    def extract_text(raw)
      case raw
      when String then raw.strip
      when Array  then raw.filter_map { |part| part.is_a?(Hash) ? part["text"] : part }.join.strip
      else ""
      end
    end
  end
end
