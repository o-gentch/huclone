# Видео из библиотеки, подключённое к Digital Double: кто из спикеров — этот человек.
class PersonaRecording < ApplicationRecord
  belongs_to :persona
  belongs_to :recording
  has_many :persona_contents, dependent: :nullify

  enum :status, { needs_speakers: "needs_speakers", ready: "ready" }

  before_destroy { Personas::RemoveContents.call(persona, persona_contents.pluck(:content_id)) }

  def speakers = recording.speakers.where(id: speaker_ids)

  def contents = Content.where(id: persona_contents.select(:content_id))
end
