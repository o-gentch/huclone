module ApplicationHelper
  STATUS_STYLES = {
    "pending"    => "bg-gray-100 text-gray-500",
    "processing" => "bg-blue-50 text-blue-600",
    "done"       => "bg-green-50 text-green-600",
    "failed"     => "bg-red-50 text-red-600",
    "uploaded"   => "bg-gray-100 text-gray-500",
    "extracting_audio" => "bg-blue-50 text-blue-600",
    "transcribing"     => "bg-blue-50 text-blue-600",
    "awaiting_speaker_confirmation" => "bg-amber-50 text-amber-600",
    "confirmed"  => "bg-green-50 text-green-600"
  }.freeze

  STATUS_LABELS = {
    "pending"    => "ожидает",
    "processing" => "обрабатывается",
    "done"       => "готово",
    "failed"     => "ошибка",
    "uploaded"   => "загружено",
    "extracting_audio" => "извлекаем звук",
    "transcribing"     => "расшифровываем",
    "awaiting_speaker_confirmation" => "нужно выбрать спикера",
    "confirmed"  => "подтверждено"
  }.freeze

  def status_badge(status)
    css   = STATUS_STYLES.fetch(status, "bg-gray-100 text-gray-500")
    label = STATUS_LABELS.fetch(status, status)
    content_tag(:span, label, class: "text-xs font-medium rounded-full px-2.5 py-0.5 #{css}")
  end

  SPEAKER_COLORS = [
    "bg-indigo-50 text-indigo-700", "bg-emerald-50 text-emerald-700", "bg-amber-50 text-amber-700",
    "bg-rose-50 text-rose-700", "bg-sky-50 text-sky-700", "bg-gray-100 text-gray-700"
  ].freeze

  def speaker_color(speaker)
    SPEAKER_COLORS[(speaker.label.ord - "A".ord) % SPEAKER_COLORS.size]
  end
end
