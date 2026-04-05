class TelegramImporter
  def self.import(persona:, file:)
    data     = parse_json!(file)
    messages = data["messages"] || []
    channel  = data["name"]

    imported = 0
    skipped  = 0

    messages.each do |msg|
      next unless msg["type"] == "message"

      text = extract_text(msg["text"])
      next if text.blank?

      content = persona.contents.create!(
        title:   Contents.build_title(text),
        body:    text,
        sources: [ { type: "telegram",
                     date: msg["date"],
                     channel: channel }
        ],
        status:  "pending"
      )
      ProcessContentJob.perform_later(content.id)
      imported += 1
    rescue StandardError
      skipped += 1
    end

    { imported: imported, skipped: skipped }
  end

  def self.parse_json!(file)
    JSON.parse(file.read.force_encoding("UTF-8"))
  end

  def self.extract_text(raw)
    case raw
    when String then raw.strip
    when Array  then raw.filter_map { |part| part.is_a?(Hash) ? part["text"] : part }.join.strip
    else ""
    end
  end
end
