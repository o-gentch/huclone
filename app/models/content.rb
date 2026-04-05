class Content < ApplicationRecord
  belongs_to :persona
  has_many :chunks, dependent: :destroy

  STATUSES = %w[pending processing done].freeze

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

  validates :status, inclusion: { in: STATUSES }

  scope :exemplars, -> { where(is_exemplar: true) }
  scope :done, -> { where(status: "done") }

  def pending? = status == "pending"
  def processing? = status == "processing"
  def done? = status == "done"
end
