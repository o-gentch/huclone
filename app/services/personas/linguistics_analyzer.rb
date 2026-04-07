module Personas
  class LinguisticsAnalyzer
    STOP_WORDS = %w[
      и в на с по к за из что это как не но а то да
      же ли бы со до при под над про без через
    ].freeze

    def self.call(...) = new(...).call

    def initialize(persona_id)
      @persona = ::Persona.find(persona_id)
    end

    def call
      contents = Content
        .where(persona_id: @persona.id, status: "done")
        .order(:id)

      return if contents.empty?

      linguistics = analyze(contents.to_a)

      @persona.update!(linguistics: linguistics)
    end

    private

    def analyze(contents)
      all_text      = contents.map(&:body).join(" ")
      words         = all_text.downcase.scan(/[а-яёa-z]+/)
      sentences     = all_text.split(/[.!?…]+/).map(&:strip).reject(&:empty?)
      all_sentences = contents.flat_map { |c|
        c.body.split(/[.!?…]+/).map(&:strip).reject(&:empty?)
      }

      top_words = words
        .reject { |w| STOP_WORDS.include?(w) || w.length < 4 }
        .tally
        .sort_by { |_, v| -v }
        .first(100)
        .to_h

      lengths      = all_sentences.map { |s| s.split.size }
      post_lengths = contents.map { |c| c.body.split.size }

      {
        top_words:               top_words,
        avg_sentence_words:      lengths.empty? ? 0 : (lengths.sum.to_f / lengths.size).round(1),
        median_sentence_words:   lengths.empty? ? 0 : lengths.sort[lengths.size / 2],
        short_sentences_pct:     lengths.empty? ? 0 : (lengths.count { |l| l < 8 }.to_f  / lengths.size * 100).round,
        long_sentences_pct:      lengths.empty? ? 0 : (lengths.count { |l| l > 20 }.to_f / lengths.size * 100).round,
        avg_post_words:          post_lengths.empty? ? 0 : (post_lengths.sum.to_f / post_lengths.size).round,
        total_words:             words.size,
        unique_words:            words.uniq.size,
        vocabulary_richness:     words.empty? ? 0 : (words.uniq.size.to_f / words.size).round(3),
        avg_paragraphs_per_post: (contents.map { |c| c.body.split(/\n{2,}/).size }.sum.to_f / contents.size).round(1),
        emoji_usage:             classify_emoji_usage(all_text),
        exclamation_pct:         sentences.empty? ? 0 : (all_text.count("!").to_f / sentences.size * 100).round,
        question_pct:            sentences.empty? ? 0 : (all_text.count("?").to_f / sentences.size * 100).round,
        ellipsis_pct:            sentences.empty? ? 0 : (all_text.scan(/\.{3}|…/).size.to_f / sentences.size * 100).round
      }
    end

    def classify_emoji_usage(text)
      count = text.scan(/[\u{1F300}-\u{1FFFF}]/).size
      case count
      when 0      then "никогда"
      when 1..10  then "редко"
      when 11..50 then "умеренно"
      else             "часто"
      end
    end
  end
end
