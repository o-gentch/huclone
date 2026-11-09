module PersonaRecordings
  module Connect
    module_function

    def call(persona, recording)
      PersonaRecording.find_or_create_by!(persona: persona, recording: recording)
    rescue ActiveRecord::RecordNotUnique
      PersonaRecording.find_by!(persona: persona, recording: recording)
    end
  end
end
