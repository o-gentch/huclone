class Persona < ApplicationRecord
  belongs_to :user, optional: true # nil только у персон, созданных до появления аккаунтов
  has_many :contents, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :recordings, dependent: :destroy

  validates :name, presence: true

  MAP_DEBOUNCE = Integer(ENV.fetch("MAP_BUILD_DEBOUNCE_SECONDS", 120)).seconds
  MAP_SCHEDULE_STALE = 15.minutes

  # Дебаунс: не чаще одной сборки карты за окно; пачка загруженных видео даёт один merge.
  # Возвращает true, если сборка поставлена в очередь.
  def schedule_map_build!
    claimed = Persona.where(id: id)
                     .where("map_build_scheduled_at IS NULL OR map_build_scheduled_at < ?", MAP_SCHEDULE_STALE.ago)
                     .update_all(map_build_scheduled_at: Time.current)
    return false if claimed.zero?

    BuildPersonalityMapJob.set(wait: MAP_DEBOUNCE).perform_later(id)
    true
  end

  def personality_map_ready?
    personality_map_built_at.present? && personality_map.present?
  end
end
