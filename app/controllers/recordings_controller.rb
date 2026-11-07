class RecordingsController < ApplicationController
  before_action :set_persona
  before_action :set_recording, only: %i[show destroy retry reprocess confirm audio]

  def index
    @recordings = @persona.recordings.for_list.order(created_at: :desc)
  end

  def new
    @recording = @persona.recordings.new
  end

  def create
    @recording = @persona.recordings.new(title: recording_params[:title], expected_speakers: recording_params[:expected_speakers].presence)
    blob = ActiveStorage::Blob.find_signed(recording_params[:source_file])

    if (error = upload_error(blob))
      @recording.errors.add(:base, error)
      return render :new, status: :unprocessable_entity
    end

    @recording.title = @recording.title.presence || blob.filename.base.to_s.truncate(120)
    @recording.source_checksum = blob.checksum

    if duplicate?(blob) && params[:force].blank?
      @recording.errors.add(:base, "Такая запись уже загружена. Если это не ошибка — нажмите «Всё равно загрузить»")
      @duplicate = true
      @signed_blob_id = recording_params[:source_file]
      return render :new, status: :unprocessable_entity
    end

    @recording.source_file.attach(blob)
    if @recording.save
      ExtractAudioJob.perform_later(@recording.id)
      redirect_to persona_recording_path(@persona, @recording), notice: "Файл загружен и отправлен на обработку"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @speakers = @recording.speakers.to_a
    @utterances = @recording.utterances.to_a if @speakers.any?
  end

  def destroy
    @recording.destroy
    redirect_to persona_recordings_path(@persona), notice: "Запись удалена"
  end

  def retry
    if @recording.retryable?
      Recordings::Restart.retry!(@recording)
      redirect_to persona_recording_path(@persona, @recording), notice: "Запись отправлена на повторную обработку"
    else
      redirect_to persona_recording_path(@persona, @recording), alert: "Эту запись нельзя повторить — загрузите файл заново"
    end
  end

  def reprocess
    count = params[:expected_speakers].to_i
    unless @recording.awaiting_speaker_confirmation? && (1..10).cover?(count)
      return redirect_to persona_recording_path(@persona, @recording), alert: "Укажите число говорящих от 1 до 10"
    end

    Recordings::Restart.redo_with_speakers!(@recording, count)
    redirect_to persona_recording_path(@persona, @recording), notice: "Перераспознаём с учётом числа говорящих"
  end

  def confirm
    speaker_id = params[:speaker_id] == "none" ? nil : params[:speaker_id]
    Recordings::Confirm.call(@recording, speaker_id: speaker_id, names: params[:names]&.to_unsafe_h)
    redirect_to persona_recording_path(@persona, @recording),
                notice: speaker_id ? "Спикер подтверждён" : "Запись сохранена без вашего голоса"
  rescue Recordings::Confirm::Invalid => e
    redirect_to persona_recording_path(@persona, @recording), alert: e.message
  end

  # Аудио отдаётся только владельцу, с поддержкой Range (перемотка в <audio>)
  def audio
    return head(:not_found) unless @recording.audio_file.attached?

    blob = @recording.audio_file.blob
    total = blob.byte_size
    range = parse_range(request.headers["Range"], total)

    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Cache-Control"] = "private, max-age=3600"
    if range
      data = blob.service.download_chunk(blob.key, range)
      response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{total}"
      send_data data, type: blob.content_type, disposition: "inline", status: :partial_content
    else
      send_data blob.download, type: blob.content_type, disposition: "inline"
    end
  end

  private

  def set_persona
    @persona = Current.user.personas.find(params[:persona_id])
  end

  def set_recording
    @recording = @persona.recordings.find(params[:id])
  end

  def recording_params
    params.fetch(:recording, {}).permit(:title, :source_file, :expected_speakers)
  end

  def upload_error(blob)
    return "Выберите файл для загрузки" unless blob
    return "Неподдерживаемый тип файла (#{blob.content_type})" unless Recording::ALLOWED_TYPES.include?(blob.content_type)
    if blob.byte_size > Recording.max_upload_bytes
      return "Файл слишком большой (максимум #{Recording.max_upload_label})"
    end
    if Recordings::Quota.remaining_minutes(Current.user).zero?
      return "Месячная квота распознавания исчерпана"
    end
    nil
  end

  def duplicate?(blob)
    @persona.recordings.where(source_checksum: blob.checksum).exists?
  end

  def parse_range(header, total)
    m = header.to_s.match(/\Abytes=(\d*)-(\d*)\z/)
    return unless m && (m[1].present? || m[2].present?)

    first, last = if m[1].empty?
      [ [ total - m[2].to_i, 0 ].max, total - 1 ]
    else
      [ m[1].to_i, m[2].present? ? [ m[2].to_i, total - 1 ].min : total - 1 ]
    end
    first <= last && first < total ? (first..last) : nil
  end
end
