class Content < ApplicationRecord
  belongs_to :persona
  belongs_to :recording, optional: true
  has_many :chunks, dependent: :delete_all

  enum :status, { pending: "pending", processing: "processing", done: "done", failed: "failed" }
  enum :kind, { post: "post", speech: "speech" }, scopes: false

  scope :posts,       -> { where(kind: "post") }
  scope :speeches,    -> { where(kind: "speech") }
  scope :exemplars,   -> { where(is_exemplar: true) }
  scope :not_in_map,  -> { where(included_in_map: false) }

  # Для карты личности и стиля: сырой текст речи, а не «причёсанный» для знаний
  def style_text = raw_body.presence || body

  def timecode = start_ms && Recording.format_ms(start_ms)
end
