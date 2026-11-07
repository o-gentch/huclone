class UsageEvent < ApplicationRecord
  belongs_to :user
  belongs_to :recording, optional: true

  scope :this_month, -> { where(created_at: Time.current.all_month) }
  scope :transcription, -> { where(kind: "transcription") }

  def self.minutes_this_month(user)
    where(user_id: user.id).transcription.this_month.sum(:quantity)
  end
end
