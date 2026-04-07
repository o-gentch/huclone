module Imports
  module Filters
    TIMESTAMP_RE      = /\d{1,2}:\d{2}\s*[-–]/
    URL_RE            = %r{https?://\S+}
    MIN_PROSE_LENGTH  = 150

    def self.content_post?(text)
      return false if text.match?(TIMESTAMP_RE)

      prose = prose_length(text)
      return false if text.match?(URL_RE) && prose < MIN_PROSE_LENGTH

      true
    end

    def self.prose_length(text)
      text
        .gsub(URL_RE, "")
        .lines
        .map(&:strip)
        .reject { |line| line.length < 30 }
        .join(" ")
        .length
    end
  end
end
