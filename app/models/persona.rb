class Persona < ApplicationRecord
  has_many :contents, dependent: :destroy
  has_many :conversations, dependent: :destroy

  validates :name, presence: true
  validates :personality_map, presence: true

  def personality_map_ready?
    personality_map_built_at.present? && personality_map.present?
  end
end
