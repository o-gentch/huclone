class Chunk < ApplicationRecord
  belongs_to :content
  has_many :topic_chunks, dependent: :delete_all

  has_neighbors :embedding

  validates :text, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Подпись источника для промпта и UI: «Из выступления «…», 34:12»
  def source_label
    if content.speech? && content.recording
      stamp = start_ms ? ", #{Recording.format_ms(start_ms)}" : ""
      "Из выступления «#{content.recording.title}»#{stamp}"
    else
      "Из поста «#{content.title}»"
    end
  end

  def source_reference
    { "label" => source_label, "content_id" => content_id,
      "recording_id" => content.recording_id, "start_ms" => start_ms }.compact
  end

  scope :ordered, -> { order(:position) }
end
