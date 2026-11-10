module Imports
  class Telegram
    MIN_TEXT_LENGTH = 100
    MAX_IMPORT      = 5_000

    def self.call(persona:, file:) = new(persona:, file:).call

    # Посты кладутся в библиотеку пользователя и подключаются к DD
    def initialize(persona:, file:)
      @persona = persona
      @user = persona.user
      @file = file
    end

    def call
      data     = parse_json!
      messages = data["messages"] || []
      channel  = data["name"]

      imported = 0
      skipped  = 0
      existing = @user.contents.posts.pluck(:body, :id).to_h

      messages.each do |msg|
        break if imported >= MAX_IMPORT
        next unless msg["type"] == "message"

        text = extract_text(msg["text"])
        next if text.length < MIN_TEXT_LENGTH
        if (known = known_content(channel, msg["id"]))
          Contents::Connect.call(@persona, known)
          next
        end
        next unless Filters.content_post?(text)
        if (existing_id = existing[text])
          Contents::Connect.call(@persona, Content.find(existing_id))
          next
        end

        content = @user.contents.create!(
          title:   Contents::TitleBuilder.build(text),
          body:    text,
          sources: [ { type: "telegram", date: msg["date"], channel: channel, message_id: msg["id"] } ],
          status:  "pending"
        )
        Contents::Connect.call(@persona, content)
        ProcessContentJob.perform_later(content.id)
        existing[text] = content.id
        (@known_ids ||= {})[msg["id"].to_s] = content.id if msg["id"]
        imported += 1
      rescue ActiveRecord::ActiveRecordError
        skipped += 1
      end

      { imported: imported, skipped: skipped }
    end

    private

    # Дубли по (пользователь, канал, message_id): повторный импорт того же экспорта ничего не создаёт
    def known_content(channel, message_id)
      return if message_id.blank?

      @known_ids ||= @user.contents.posts.where("sources @> ?", [ { type: "telegram", channel: channel } ].to_json)
                          .pluck(Arel.sql("sources->0->>'message_id'"), :id).to_h
      (id = @known_ids[message_id.to_s]) && Content.find(id)
    end

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
