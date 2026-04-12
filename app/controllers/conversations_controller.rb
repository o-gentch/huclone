class ConversationsController < ApplicationController
  before_action :set_persona

  def index
    @conversations = @persona.conversations.order(created_at: :desc)
    if @conversations.one?
      redirect_to persona_conversation_path(@persona, @conversations.first)
    end
  end

  def show
    @conversation = @persona.conversations.find(params[:id])
    @messages = @conversation.messages.chronological
  end

  def create
    @conversation = @persona.conversations.create!
    redirect_to persona_conversation_path(@persona, @conversation)
  end

  private

  def set_persona
    @persona = Persona.find(params[:persona_id])
  end
end
