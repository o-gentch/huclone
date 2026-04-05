module Contents
  def self.build_title(text)
    text.gsub(/\s+/, " ").strip.truncate(60)
  end
end