OpenAI.configure do |config|
  config.access_token = ENV["OPENAI_ACCESS_TOKEN"].presence ||
                        Rails.application.credentials.dig(:openai, :access_token)
end
