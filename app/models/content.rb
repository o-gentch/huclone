class Content < ApplicationRecord
  belongs_to :user
  belongs_to :recording, optional: true
  belongs_to :speaker, optional: true
  has_many :persona_contents, dependent: :delete_all
  has_many :personas, through: :persona_contents
  has_many :chunks, dependent: :delete_all

  enum :status, { pending: "pending", processing: "processing", done: "done", failed: "failed" }
  enum :kind, { post: "post", speech: "speech" }, scopes: false

  scope :posts,       -> { where(kind: "post") }
  scope :speeches,    -> { where(kind: "speech") }

  before_destroy { persona_contents.group_by(&:persona_id).each_key { |pid| Personas::RemoveContents.call(Persona.find(pid), [ id ]) } }

  # Для карты личности и стиля: сырой текст речи, а не «причёсанный» для знаний
  def style_text = raw_body.presence || body

  def timecode = start_ms && Recording.format_ms(start_ms)
end
