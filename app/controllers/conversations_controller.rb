class ConversationsController < ApplicationController
  before_action :set_persona

  def index
    @conversations = @persona.conversations.order(created_at: :desc)
  end

  def show
    @conversation = @persona.conversations.find(params[:id])
    @messages = @conversation.messages.chronological
  end

  def create
    @conversation = @persona.conversations.create!
    redirect_to persona_conversation_path(@persona, @conversation)
  end

  def destroy
    @persona.conversations.find(params[:id]).destroy
    redirect_to persona_conversations_path(@persona), notice: "Чат удалён"
  end

  private

  def set_persona
    @persona = Current.user.personas.find(params[:persona_id])
  end
end
