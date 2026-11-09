module ApplicationHelper
  STATUS_STYLES = {
    "pending"    => "b-gray",
    "processing" => "b-info b-pulse",
    "done"       => "b-ok",
    "failed"     => "b-err",
    "uploaded"   => "b-gray",
    "extracting_audio" => "b-info b-pulse",
    "transcribing"     => "b-info b-pulse",
    "transcribed" => "b-ok",
    "needs_speakers" => "b-warn",
    "ready"      => "b-ok"
  }.freeze

  STATUS_LABELS = {
    "pending"    => "ожидает",
    "processing" => "обрабатывается",
    "done"       => "готово",
    "failed"     => "ошибка",
    "uploaded"   => "загружено",
    "extracting_audio" => "извлекаем звук",
    "transcribing"     => "расшифровываем",
    "transcribed" => "расшифровано",
    "needs_speakers" => "нужно выбрать спикера",
    "ready"      => "готово"
  }.freeze

  def status_badge(status)
    css   = STATUS_STYLES.fetch(status, "b-gray")
    label = STATUS_LABELS.fetch(status, status)
    content_tag(:span, label, class: "badge #{css}")
  end

  SPEAKER_COLORS = %w[c0 c1 c2 c3 c4 c5].freeze

  def speaker_color(speaker)
    SPEAKER_COLORS[(speaker.label.ord - "A".ord) % SPEAKER_COLORS.size]
  end

  NAV_ICONS = {
    contents:      '<path d="M6 3h9l4 4v14H6zM9 13h7M9 17h5"/>',
    recordings:    '<rect x="3" y="6" width="12" height="12" rx="2"/><path d="M15 10l6-3v10l-6-3"/>',
    topics:        '<path d="M5 5h5M5 12h5M5 19h5M14 5h5M14 12h5M14 19h5"/>',
    library:       '<path d="M4 5h4v14H4zM10 5h4v14h-4zM16 6l4 1-3 12-4-1z"/>',
    conversations: '<path d="M4 5h16v11H9l-5 4z"/>'
  }.freeze

  # Иконка для плитки/навигации. Размер задаёт CSS (.ico svg / .tile svg).
  def section_icon(key)
    tag.svg(NAV_ICONS.fetch(key).html_safe, viewBox: "0 0 24 24")
  end

  def nav_link(label, path, section, tone)
    on = controller_name == section.to_s
    link_to path, class: ("on" if on) do
      safe_join([ tag.span(section_icon(section), class: "ico #{tone}"), label ])
    end
  end

  def conversation_title(conversation)
    first = conversation.messages.where(role: "user").order(:created_at).first
    first ? first.body.squish.truncate(40) : "Разговор от #{conversation.created_at.strftime('%d.%m %H:%M')}"
  end
end
