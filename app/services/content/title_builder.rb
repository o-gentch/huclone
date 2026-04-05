module Content
  module TitleBuilder
    def self.build(text)
      text.gsub(/\s+/, " ").strip.truncate(60)
    end
  end
end
