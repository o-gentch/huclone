class ContentsController < ApplicationController
  MAX_BODY_BYTES = 1.megabyte

  before_action :set_persona

  def index
    # Фрагменты речи принадлежат записям и управляются со страницы «Видео»
    links = @persona.persona_contents.joins(:content).merge(Content.posts).includes(:content).to_a
    @recording_links = @persona.persona_recordings.includes(:recording).to_a
    # Видео и тексты — одним списком, новые сверху
    @counts = { "post" => links.size, "video" => @recording_links.size }
    @type = params[:type].presence_in(%w[video post])
    links = [] if @type == "video"
    @recording_links = [] if @type == "post"
    @items = (links + @recording_links).sort_by { |i| i.is_a?(PersonaContent) ? i.content.created_at : i.recording.created_at }.reverse
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

  # Повтор обработки упавшего материала
  def retry
    content = @persona.contents.find(params[:id])
    if content.failed?
      content.update!(status: "pending")
      ProcessContentJob.perform_later(content.id)
      redirect_to persona_contents_path(@persona), notice: "Отправлено на повторную обработку"
    else
      redirect_to persona_contents_path(@persona)
    end
  end

  # Ручная отметка эталона: образец голоса для написания постов
  def toggle_exemplar
    link = @persona.persona_contents.find_by!(content_id: params[:id])
    link.update!(is_exemplar: !link.is_exemplar, exemplar_pinned: true)
    redirect_to persona_contents_path(@persona)
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
