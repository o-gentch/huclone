module Imports
  class Telegram
    MIN_TEXT_LENGTH = 100
    MAX_IMPORT      = 5_000

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
      existing_bodies = @persona.contents.pluck(:body).to_set

      messages.each do |msg|
        break if imported >= MAX_IMPORT
        next unless msg["type"] == "message"

        text = extract_text(msg["text"])
        next if text.length < MIN_TEXT_LENGTH
        next unless Filters.content_post?(text)
        next if existing_bodies.include?(text)

        content = @persona.contents.create!(
          title:   Contents::TitleBuilder.build(text),
          body:    text,
          sources: [ { type: "telegram", date: msg["date"], channel: channel } ],
          status:  "pending"
        )
        ProcessContentJob.perform_later(content.id)
        existing_bodies << text
        imported += 1
      rescue ActiveRecord::ActiveRecordError
        skipped += 1
      end

      { imported: imported, skipped: skipped }
    end

    private

    def parse_json!
      JSON.parse(@file.read.force_encoding("UTF-8").scrub(""))
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
