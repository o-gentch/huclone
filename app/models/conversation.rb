class Conversation < ApplicationRecord
  belongs_to :persona
  has_many :messages, dependent: :destroy

  def recent_messages(limit = 10)
    messages.order(created_at: :asc).last(limit)
  end
end
