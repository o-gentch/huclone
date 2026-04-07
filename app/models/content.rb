class Content < ApplicationRecord
  belongs_to :persona
  has_many :chunks, dependent: :destroy

  enum :status, { pending: "pending", processing: "processing", done: "done", failed: "failed" }

  scope :exemplars, -> { where(is_exemplar: true) }
end
