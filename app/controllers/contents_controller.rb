class ContentsController < ApplicationController
  before_action :set_persona

  def index
    @contents = @persona.contents.order(created_at: :desc)
  end

  def new
    @content = @persona.contents.new
  end

  def create
    text = extract_text(params[:content])
    @content = @persona.contents.new(
      title:   params[:content][:title].presence || Contents::TitleBuilder.build(text),
      body:    text,
      sources: [ { type: "manual" } ],
      status:  "pending"
    )

    if text.blank?
      @content.errors.add(:body, "не может быть пустым")
      render :new, status: :unprocessable_entity
      return
    end

    if @content.save
      ProcessContentJob.perform_later(@content.id)
      if params[:add_more]
        redirect_to new_persona_content_path(@persona), notice: "Сохранено. Добавьте следующий текст."
      else
        redirect_to persona_contents_path(@persona), notice: "Текст добавлен и отправлен на обработку"
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @persona.contents.find(params[:id]).destroy
    redirect_to persona_contents_path(@persona), notice: "Удалено"
  end

  private

  def set_persona
    @persona = Persona.find(params[:persona_id])
  end

  def extract_text(content_params)
    if content_params[:file].present?
      content_params[:file].read.force_encoding("UTF-8")
    else
      content_params[:body].to_s.strip
    end
  end
end
