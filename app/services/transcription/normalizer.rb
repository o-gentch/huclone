module Transcription
  # Склеивает подряд идущие реплики одного спикера (пауза < MAX_GAP_MS),
  # отбрасывает пустые, переименовывает спикеров в A, B, C… в порядке появления.
  class Normalizer
    MAX_GAP_MS = 2_000

    def self.call(...) = new(...).call

    def initialize(utterances, max_gap_ms: MAX_GAP_MS)
      @utterances = utterances
      @max_gap_ms = max_gap_ms
    end

    def call
      labels = {}
      merged = []

      @utterances.sort_by { |u| u[:start_ms] }.each do |u|
        text = u[:text].to_s.squish
        next if text.empty?

        label = (labels[u[:speaker].to_s] ||= ("A".ord + labels.size).chr)
        last = merged.last
        if last && last[:speaker] == label && u[:start_ms] - last[:end_ms] < @max_gap_ms
          last[:confidences] << [ u[:confidence], text.length ]
          last[:text] = "#{last[:text]} #{text}"
          last[:end_ms] = [ last[:end_ms], u[:end_ms] ].max
        else
          merged << { speaker: label, start_ms: u[:start_ms], end_ms: u[:end_ms], text: text,
                      confidences: [ [ u[:confidence], text.length ] ] }
        end
      end

      merged.map { |m| m.except(:confidences).merge(confidence: weighted(m[:confidences])) }
    end

    private

    # Средняя уверенность, взвешенная по длине текста
    def weighted(pairs)
      known = pairs.reject { |c, _| c.nil? }
      return nil if known.empty?
      total = known.sum { |_, w| w }
      (known.sum { |c, w| c * w } / total).round(3)
    end
  end
end
