class ChatResponseJob < ApplicationJob
  queue_as :chat

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 3
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  # Все ретраи исчерпаны — показываем ошибку вместо вечного «печатает»
  after_discard do |job, _exception|
    _conversation_id, _user_message_id, assistant_message_id = job.arguments
    assistant = Message.find_by(id: assistant_message_id)
    next unless assistant && assistant.body.blank?

    Conversations::ChatResponder.show_error_for(assistant)
  end

  def perform(conversation_id, user_message_id, assistant_message_id)
    conversation      = Conversation.find(conversation_id)
    user_message      = Message.find(user_message_id)
    assistant_message = Message.find(assistant_message_id)

    Conversations::ChatResponder.call(conversation, user_message, assistant_message)
  end
end
