module PersonaRecordings
  # Приводит persona_contents в соответствие с выбранными спикерами. Идемпотентно.
  class Sync
    def self.call(...) = new(...).call

    def initialize(persona_recording)
      @pr = persona_recording
    end

    def call
      persona = @pr.persona
      wanted = Content.speeches.where(recording_id: @pr.recording_id, speaker_id: @pr.speaker_ids).pluck(:id)
      existing = @pr.persona_contents.pluck(:content_id)

      Personas::RemoveContents.call(persona, existing - wanted)

      added = wanted - existing
      if added.any?
        now = Time.current
        PersonaContent.insert_all(
          added.map { |cid| { persona_id: persona.id, content_id: cid, persona_recording_id: @pr.id, role: "voice", created_at: now, updated_at: now } },
          unique_by: %i[persona_id content_id]
        )
      end
      @pr.update!(summary: nil) if added.any? || (existing - wanted).any?
      Personas::ContentReady.call(persona)
    end
  end
end
