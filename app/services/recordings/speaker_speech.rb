module Recordings
  # Ленивая обработка речи по спикеру: фрагменты строятся при первом выборе спикера любым DD (§2.3, §6.2).
  # Состояние в speakers.speech_state; захват — атомарный UPDATE, поэтому параллельные выборы не дублируют работу.
  module SpeakerSpeech
    module_function

    # :started — запущена обработка, :building — уже идёт, :ready — фрагменты готовы
    def request!(speaker)
      claimed = Speaker.where(id: speaker.id, speech_state: "idle").update_all(speech_state: "building")
      if claimed == 1
        BuildSpeakerSpeechJob.perform_later(speaker.id)
        :started
      else
        speaker.reload.speech_state.to_sym
      end
    end

    # Вызывается джобом по завершении построения фрагментов
    def finished!(speaker)
      speaker.update!(speech_state: "ready")
      PersonaRecording.where(recording_id: speaker.recording_id).where("? = ANY(speaker_ids)", speaker.id).find_each do |pr|
        PersonaRecordings::Sync.call(pr)
      end
    end

    def reset!(speaker_id)
      Speaker.where(id: speaker_id).update_all(speech_state: "idle")
    end
  end
end
