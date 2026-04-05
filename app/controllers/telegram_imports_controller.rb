class TelegramImportsController < ApplicationController
  before_action :set_persona

  def new
  end

  def create
    file = params[:import]&.dig(:file)

    if file.blank?
      flash.now[:error] = "Файл не выбран"
      render :new, status: :unprocessable_entity
      return
    end

    result = Imports::Telegram.call(persona: @persona, file: file)

    notice = "Импортировано #{result[:imported]} постов"
    notice += ", пропущено #{result[:skipped]}" if result[:skipped] > 0
    redirect_to persona_contents_path(@persona), notice: notice
  rescue JSON::ParserError
    flash.now[:error] = "Невалидный JSON файл"
    render :new, status: :unprocessable_entity
  end

  private

  def set_persona
    @persona = Persona.find(params[:persona_id])
  end
end
