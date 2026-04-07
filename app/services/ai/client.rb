module Ai
  module Client
    def self.instance
      @instance ||= OpenAI::Client.new(log_errors: true)
    end
  end
end
