module Recordings
  # Превращает реплики записи в «ходы диалога»: вопрос другого спикера → ответ персоны.
  # Длинные ответы режутся на фрагменты по границам предложений и паузам.
  class TurnBuilder
    Turn = Struct.new(:context_text, :speaker_name, :text, :start_ms, :end_ms, keyword_init: true)

    MIN_FRAGMENT_WORDS = 300   # режем по паузе, когда набрано не меньше
    MAX_FRAGMENT_WORDS = 1500  # жёсткий предел
    PAUSE_MS = 4_000
    MIN_KEEP_WORDS = 10        # совсем короткие реплики («да», «конечно») не знания
    MAX_QUESTION_UTTERANCES = 3
    MAX_QUESTION_WORDS = 60
    MIN_CONFIDENCE = Recording::LOW_CONFIDENCE

    Unit = Struct.new(:text, :start_ms, :end_ms, :utterance_index)

    def self.call(...) = new(...).call

    def initialize(recording, speaker:, min_confidence: MIN_CONFIDENCE)
      @recording = recording
      @speaker = speaker
      @min_confidence = min_confidence
    end

    def call
      persona_speaker = @speaker

      utterances = @recording.utterances.includes(:speaker).to_a
      turns = []
      i = 0
      while i < utterances.size
        unless utterances[i].speaker_id == persona_speaker.id
          i += 1
          next
        end

        run = []
        while i < utterances.size && utterances[i].speaker_id == persona_speaker.id
          run << utterances[i]
          i += 1
        end
        first_index = utterances.index(run.first)
        turns.concat(build_turns(run, question_before(utterances, first_index, persona_speaker)))
      end
      turns
    end

    private

    # Вопрос — только реплики других спикеров непосредственно перед ответом
    def question_before(utterances, index, persona_speaker)
      picked = []
      words = 0
      j = index - 1
      while j >= 0 && utterances[j].speaker_id != persona_speaker.id && picked.size < MAX_QUESTION_UTTERANCES
        w = utterances[j].text.split.size
        break if picked.any? && words + w > MAX_QUESTION_WORDS
        picked.unshift(utterances[j])
        words += w
        j -= 1
      end
      return nil if picked.empty? || words > MAX_QUESTION_WORDS * 2

      { text: picked.map(&:text).join(" "), speaker: picked.last.speaker.name }
    end

    def build_turns(run, question)
      units = run.each_with_index.flat_map { |u, idx| units_for(u, idx) }
      return [] if units.empty?

      groups = group_units(units)
      turns = groups.filter_map do |group|
        text = group.map(&:text).join(" ")
        next if text.split.size < MIN_KEEP_WORDS

        Turn.new(text: text, start_ms: group.first.start_ms, end_ms: group.last.end_ms)
      end
      if question && turns.any?
        turns.first.context_text = question[:text].truncate(500)
        turns.first.speaker_name = question[:speaker]
      end
      turns
    end

    # Реплика (если уверенность достаточна) → предложения с интерполированными таймкодами
    def units_for(utterance, idx)
      return [] if utterance.confidence && utterance.confidence < @min_confidence

      sentences = utterance.text.scan(/[^.!?…]+[.!?…]*\s*/).map(&:strip).reject(&:empty?)
      total = [ sentences.sum(&:length), 1 ].max
      span = utterance.end_ms - utterance.start_ms
      offset = 0
      sentences.map do |s|
        start_ms = utterance.start_ms + (span * offset / total)
        offset += s.length
        Unit.new(s, start_ms, utterance.start_ms + (span * offset / total), idx)
      end
    end

    def group_units(units)
      groups = [ [] ]
      words = 0
      units.each_with_index do |unit, k|
        groups.last << unit
        words += unit.text.split.size
        nxt = units[k + 1]
        break_here = nxt && (words >= MAX_FRAGMENT_WORDS ||
                             (words >= MIN_FRAGMENT_WORDS && nxt.utterance_index != unit.utterance_index &&
                              nxt.start_ms - unit.end_ms >= PAUSE_MS))
        if break_here
          groups << []
          words = 0
        end
      end
      groups.reject(&:empty?)
    end
  end
end
