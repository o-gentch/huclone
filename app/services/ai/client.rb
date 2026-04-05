module AI
  module Client
    def self.instance
      @instance ||= OpenAI::Client.new
    end
  end
end
