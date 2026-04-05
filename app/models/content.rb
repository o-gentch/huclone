class Content < ApplicationRecord
  belongs_to :persona
  has_many :chunks, dependent: :destroy

  STATUSES = %w[pending processing done].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :exemplars, -> { where(is_exemplar: true) }
  scope :done, -> { where(status: "done") }

  def pending? = status == "pending"
  def processing? = status == "processing"
  def done? = status == "done"
end
