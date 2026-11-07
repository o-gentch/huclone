class MessagesController < ApplicationController
  MAX_BODY_LENGTH = 4_000

  before_action :set_conversation

  def create
    mode = params.dig(:message, :mode).presence_in(Message::MODES) || "strict"
    body = params.dig(:message, :body).to_s.strip

    return head :unprocessable_entity if body.blank? || body.length > MAX_BODY_LENGTH

    Message.transaction do
      @user_message      = @conversation.messages.create!(role: "user",      body: body, mode: mode)
      @assistant_message = @conversation.messages.create!(role: "assistant", body: "",   mode: mode)
    end

    ChatResponseJob.perform_later(@conversation.id, @user_message.id, @assistant_message.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to persona_conversation_path(@persona, @conversation) }
    end
  end

  private

  def set_conversation
    @persona      = Persona.find(params[:persona_id])
    @conversation = @persona.conversations.find(params[:conversation_id])
  end
end
