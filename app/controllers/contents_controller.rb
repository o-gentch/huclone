class ContentsController < ApplicationController
  MAX_BODY_BYTES = 1.megabyte

  before_action :set_persona

  def index
    # Фрагменты речи принадлежат записям и управляются со страницы «Видео»
    @links = @persona.persona_contents.joins(:content).merge(Content.posts).includes(:content).order("contents.created_at DESC")
  end

  def new
    @content = Content.new
  end

  def create
    text = extract_text(params[:content])
    if text.bytesize > MAX_BODY_BYTES
      @content = Content.new(title: params[:content][:title], body: nil)
      @content.errors.add(:body, "слишком большой (максимум #{MAX_BODY_BYTES / 1.megabyte} МБ)")
      render :new, status: :unprocessable_entity
      return
    end

    @content = Current.user.contents.new(
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
      Contents::Connect.call(@persona, @content)
      # Карта пересобирается из ProcessContentJob после завершения обработки
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
    Contents::Connect.disconnect(@persona, @persona.contents.find(params[:id]))
    redirect_to persona_contents_path(@persona), notice: "Удалено"
  end

  private

  def set_persona
    @persona = Current.user.personas.find(params[:persona_id])
  end

  def extract_text(content_params)
    raw = if content_params[:file].present?
      file = content_params[:file]
      return "" if file.size > MAX_BODY_BYTES * 2
      file.read(MAX_BODY_BYTES * 2 + 1)
    else
      content_params[:body].to_s
    end

    raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
       .gsub("\u0000", "")
       .strip
  end
end
