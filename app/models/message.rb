class Message < ApplicationRecord
  belongs_to :conversation

  ROLES = %w[user assistant].freeze
  MODES = %w[strict ideas].freeze

  validates :role, inclusion: { in: ROLES }
  validates :mode, inclusion: { in: MODES }
  validates :body, presence: true

  scope :by_user, -> { where(role: "user") }
  scope :by_assistant, -> { where(role: "assistant") }
  scope :chronological, -> { order(created_at: :asc) }
end
