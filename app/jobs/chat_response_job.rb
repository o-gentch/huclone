class ChatResponseJob < ApplicationJob
  queue_as :chat

  retry_on OpenAI::Error, wait: :polynomially_longer, attempts: 3
  retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(conversation_id, user_message_id, assistant_message_id)
    conversation      = Conversation.find(conversation_id)
    user_message      = Message.find(user_message_id)
    assistant_message = Message.find(assistant_message_id)

    Conversations::ChatResponder.call(conversation, user_message, assistant_message)
  end
end
