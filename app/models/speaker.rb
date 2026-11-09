class Speaker < ApplicationRecord
  belongs_to :recording
  has_many :utterances, dependent: :delete_all
  has_many :contents, dependent: :nullify

  def name = display_name.presence || "Спикер #{label}"

  def share(total_ms)
    total_ms.positive? ? (speech_ms * 100.0 / total_ms).round : 0
  end

  # Самые длинные реплики — для проверки «это я?»
  def sample_utterances(limit = 3)
    utterances.reorder(Arel.sql("length(text) DESC")).limit(limit).sort_by(&:position)
  end
end
