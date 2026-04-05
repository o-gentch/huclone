module ApplicationHelper
  STATUS_STYLES = {
    "pending"    => "bg-gray-100 text-gray-500",
    "processing" => "bg-blue-50 text-blue-600",
    "done"       => "bg-green-50 text-green-600"
  }.freeze

  STATUS_LABELS = {
    "pending"    => "ожидает",
    "processing" => "обрабатывается",
    "done"       => "готово"
  }.freeze

  def status_badge(status)
    css   = STATUS_STYLES.fetch(status, "bg-gray-100 text-gray-500")
    label = STATUS_LABELS.fetch(status, status)
    content_tag(:span, label, class: "text-xs font-medium rounded-full px-2.5 py-0.5 #{css}")
  end
end
