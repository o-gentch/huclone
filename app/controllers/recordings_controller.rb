class RecordingsController < ApplicationController
  include StreamsAudio

  before_action :set_persona
  before_action :set_recording, only: %i[show destroy retry reprocess confirm audio]

  def index
    @recordings = @persona.recordings.for_list.order(created_at: :desc)
    @links = @persona.persona_recordings.index_by(&:recording_id)
  end

  def new
    @recording = Recording.new
  end

  def create
    @recording = Current.user.recordings.new(title: recording_params[:title], expected_speakers: recording_params[:expected_speakers].presence)
    signed_id = recording_params[:source_file]
    blob = signed_id.is_a?(String) ? ActiveStorage::Blob.find_signed(signed_id) : nil

    if (error = upload_error(blob))
      @recording.errors.add(:base, error)
      return render :new, status: :unprocessable_entity
    end

    @recording.title = @recording.title.presence || blob.filename.base.to_s.truncate(120)
    @recording.source_checksum = blob.checksum

    if (existing = Current.user.recordings.find_by(source_checksum: blob.checksum))
      PersonaRecordings::Connect.call(@persona, existing)
      return redirect_to persona_recording_path(@persona, existing),
                         notice: "Такая запись уже в библиотеке — подключена к «#{@persona.name}», повторная расшифровка не нужна"
    end

    @recording.source_file.attach(blob)
    if @recording.save
      PersonaRecordings::Connect.call(@persona, @recording)
      ExtractAudioJob.perform_later(@recording.id)
      redirect_to persona_recording_path(@persona, @recording), notice: "Файл загружен и отправлен на обработку"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @speakers = @recording.speakers.to_a
    others = PersonaRecording.where(recording_id: @recording.id).where.not(persona_id: @persona.id).includes(:persona)
    @other_choices = others.flat_map { |pr| pr.speaker_ids.map { |sid| [ sid, pr.persona.name ] } }.group_by(&:first).transform_values { |v| v.map(&:last) }
    @utterances = @recording.utterances.to_a if @speakers.any?
  end

  def destroy
    @persona_recording.destroy
    @recording.destroy if @recording.persona_recordings.reload.none? # без экрана библиотеки осиротевшая запись не нужна
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
    unless @recording.transcribed? && (1..10).cover?(count)
      return redirect_to persona_recording_path(@persona, @recording), alert: "Укажите число говорящих от 1 до 10"
    end

    Recordings::Restart.redo_with_speakers!(@recording, count)
    redirect_to persona_recording_path(@persona, @recording), notice: "Перераспознаём с учётом числа говорящих"
  end

  def confirm
    ids = params[:none].present? ? [] : Array(params[:speaker_ids]).compact_blank
    if ids.empty? && params[:none].blank?
      return redirect_to persona_recording_path(@persona, @recording), alert: "Отметьте говорящих или выберите «Этого человека нет в записи»"
    end

    PersonaRecordings::SelectSpeakers.call(@persona_recording, speaker_ids: ids, names: params[:names]&.to_unsafe_h)
    redirect_to persona_recording_path(@persona, @recording),
                notice: ids.any? ? "Спикеры сохранены" : "Запись сохранена без «#{@persona.name}»"
  rescue PersonaRecordings::SelectSpeakers::Invalid => e
    redirect_to persona_recording_path(@persona, @recording), alert: e.message
  end

  def audio = stream_audio(@recording)

  private

  def set_persona
    @persona = Current.user.personas.find(params[:persona_id])
  end

  def set_recording
    @recording = @persona.recordings.find(params[:id])
    @persona_recording = @persona.persona_recordings.find_by!(recording_id: @recording.id)
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
end
