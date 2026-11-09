class LibraryController < ApplicationController
  include StreamsAudio

  PER_PAGE = 50

  before_action :require_persona, only: :index
  before_action :set_recording, only: %i[recording audio disconnect]

  def index
    @personas = Current.user.personas.order(:id)
    @filters = params.permit(:q, :type, :status, :source, :dd).to_h.symbolize_keys.compact_blank
    @page = [ params[:page].to_i, 1 ].max

    recordings = filtered_recordings
    posts = filtered_posts
    @total = recordings.count + posts.count

    take = @page * PER_PAGE
    rows = recordings.for_list.reorder(created_at: :desc, id: :desc).limit(take).to_a +
           posts.select(:id, :user_id, :title, :status, :created_at, :sources).reorder(created_at: :desc, id: :desc).limit(take).to_a
    @items = rows.sort_by { |r| [ r.created_at, r.id ] }.reverse.slice((@page - 1) * PER_PAGE, PER_PAGE) || []

    rec_ids = @items.grep(Recording).map(&:id)
    post_ids = @items.grep(Content).map(&:id)
    @rec_links = PersonaRecording.where(recording_id: rec_ids).includes(:persona).group_by(&:recording_id)
    @post_links = PersonaContent.where(content_id: post_ids).includes(:persona).group_by(&:content_id)
    @facets = source_facets
    @last_page = [ (@total.fdiv(PER_PAGE)).ceil, 1 ].max
  end

  def recording
    @speakers = @recording.speakers.to_a
    @utterances = @recording.utterances.to_a if @speakers.any?
    @links = @recording.persona_recordings.includes(:persona).order(:id)
    @free_personas = Current.user.personas.where.not(id: @links.map(&:persona_id)).order(:id)
  end

  def audio = stream_audio(@recording)

  def connect
    persona = Current.user.personas.find(params[:persona_id])
    recordings, contents = selected_items
    return redirect_back_or("Ничего не выбрано") if recordings.empty? && contents.empty?

    role = params[:role] == "knowledge" ? "knowledge" : "voice"
    recordings.each { |r| PersonaRecordings::Connect.call(persona, r) }
    contents.each { |c| Contents::Connect.call(persona, c, role: role) }
    redirect_back_or(nil, notice: "Подключено к «#{persona.name}»: #{recordings.size + contents.size}")
  end

  def delete
    recordings, contents = selected_items
    return redirect_back_or("Ничего не выбрано") if recordings.empty? && contents.empty?

    recordings.each(&:destroy)
    contents.each(&:destroy)
    redirect_to library_path, notice: "Удалено из библиотеки: #{recordings.size + contents.size}"
  end

  def disconnect
    persona = Current.user.personas.find(params[:persona_id])
    @recording.persona_recordings.find_by!(persona: persona).destroy
    redirect_to library_recording_path(@recording), notice: "Отключено от «#{persona.name}». Запись осталась в библиотеке"
  end

  private

  def require_persona
    redirect_to new_persona_path unless Current.user.personas.exists?
  end

  def set_recording
    @recording = Current.user.recordings.find(params[:id])
  end

  def redirect_back_or(alert, **opts)
    redirect_back fallback_location: library_path, alert: alert, **opts
  end

  # items[]: "recording_12", "content_5"
  def selected_items
    keys = Array(params[:items]).map(&:to_s)
    ids = ->(prefix) { keys.filter_map { |k| k.delete_prefix(prefix).to_i if k.start_with?(prefix) } }
    [ Current.user.recordings.where(id: ids.call("recording_")).to_a, Current.user.contents.posts.where(id: ids.call("content_")).to_a ]
  end

  # ---- Фильтры ------------------------------------------------------------------------------

  def filtered_recordings
    scope = Current.user.recordings
    return scope.none if @filters[:type] == "post" || @filters[:source].to_s.start_with?("telegram:", "manual")

    if (q = @filters[:q])
      like = "%#{Recording.sanitize_sql_like(q)}%"
      scope = scope.where("recordings.title ILIKE :like OR recordings.id IN (SELECT recording_id FROM utterances WHERE to_tsvector('russian', text) @@ plainto_tsquery('russian', :q))", like: like, q: q)
    end
    scope = case @filters[:status]
    when "ready" then scope.where(status: "transcribed")
    when "processing" then scope.where(status: %w[uploaded extracting_audio transcribing])
    when "failed" then scope.where(status: "failed")
    else scope
    end
    scope_by_dd(scope, PersonaRecording, :recording_id, "recordings")
  end

  def filtered_posts
    scope = Current.user.contents.posts
    return scope.none if @filters[:type] == "video" || @filters[:source] == "upload"

    if (q = @filters[:q])
      like = "%#{Content.sanitize_sql_like(q)}%"
      scope = scope.where("contents.title ILIKE :like OR to_tsvector('russian', coalesce(contents.body, '')) @@ plainto_tsquery('russian', :q)", like: like, q: q)
    end
    scope = case @filters[:status]
    when "ready" then scope.where(status: "done")
    when "processing" then scope.where(status: %w[pending processing])
    when "failed" then scope.where(status: "failed")
    else scope
    end
    if (src = @filters[:source].to_s).start_with?("telegram:")
      scope = scope.where("contents.sources @> ?", [ { type: "telegram", channel: src.delete_prefix("telegram:") } ].to_json)
    elsif src == "manual"
      scope = scope.where("contents.sources @> ?", [ { type: "manual" } ].to_json)
    end
    scope_by_dd(scope, PersonaContent, :content_id, "contents")
  end

  def scope_by_dd(scope, link_model, fk, table)
    dd = @filters[:dd]
    return scope if dd.blank?

    if dd == "none"
      scope.where.not(id: link_model.select(fk))
    else
      scope.where(id: link_model.where(persona_id: Current.user.personas.where(id: dd)).select(fk))
    end
  end

  def source_facets
    counts = Hash.new(0)
    Current.user.contents.posts.group(Arel.sql("sources->0->>'type'"), Arel.sql("sources->0->>'channel'")).count.each do |(type, channel), n|
      counts[type == "telegram" ? "telegram:#{channel}" : "manual"] += n
    end
    facets = []
    uploads = Current.user.recordings.count
    facets << [ "upload", "Загрузки · видео и аудио", uploads ] if uploads.positive?
    counts.each do |key, n|
      label = key == "manual" ? "Добавлено вручную" : "Telegram · #{key.delete_prefix('telegram:').presence || 'канал'}"
      facets << [ key, label, n ]
    end
    facets
  end
end
