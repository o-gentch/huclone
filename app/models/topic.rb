class Topic < ApplicationRecord
  belongs_to :persona
  belongs_to :parent, class_name: "Topic", optional: true
  has_many :children, -> { order(:position) }, class_name: "Topic", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent
  has_many :topic_chunks, dependent: :delete_all
  has_many :chunks, through: :topic_chunks

  has_neighbors :centroid

  before_validation { self.slug ||= "t-#{SecureRandom.hex(4)}" }
  validates :title, presence: true

  scope :roots, -> { where(parent_id: nil).order(:position) }

  def leaf? = children.none?

  # Чанки темы и всех вложенных тем
  def subtree_chunk_scope
    ids = [ id ]
    frontier = [ id ]
    while frontier.any?
      frontier = Topic.where(parent_id: frontier).pluck(:id)
      ids.concat(frontier)
    end
    Chunk.joins(:topic_chunks).where(topic_chunks: { topic_id: ids })
  end

  # [recording, start_ms] — источники темы с таймкодами
  def sources(limit: nil)
    rows = subtree_chunk_scope.joins(content: :recording).distinct
             .pluck("recordings.id", "recordings.title", "chunks.start_ms").sort_by { |id, _t, ms| [ id, ms.to_i ] }
    rows = rows.first(limit) if limit
    rows.map { |rid, title, ms| { recording_id: rid, title: title, start_ms: ms } }
  end
end
