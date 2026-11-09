# Какие фрагменты знаний доступны Digital Double (и в какой роли).
class PersonaContent < ApplicationRecord
  belongs_to :persona
  belongs_to :content
  belongs_to :persona_recording, optional: true

  enum :role, { voice: "voice", knowledge: "knowledge" }

  scope :exemplars,  -> { where(is_exemplar: true) }
  scope :not_in_map, -> { where(included_in_map: false) }
end
