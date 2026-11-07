class Persona < ApplicationRecord
  belongs_to :user, optional: true # nil только у персон, созданных до появления аккаунтов
  has_many :contents, dependent: :destroy
  has_many :conversations, dependent: :destroy

  validates :name, presence: true

  def personality_map_ready?
    personality_map_built_at.present? && personality_map.present?
  end
end
