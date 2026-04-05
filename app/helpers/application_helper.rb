module ApplicationHelper
  def status_badge(status)
    css = Content::STATUS_STYLES.fetch(status, "bg-gray-100 text-gray-500")
    label = Content::STATUS_LABELS.fetch(status, status)
    content_tag(:span, label, class: "text-xs font-medium rounded-full px-2.5 py-0.5 #{css}")
  end
end
