module Personas
  class ExemplarSelector
    MAX_EXEMPLARS = 7

    def self.call(persona) = new(persona).call

    def initialize(persona)
      @persona = persona
    end

    def call
      done_contents = @persona.contents.done.includes(:chunks)
      return if done_contents.empty?

      exemplar_ids = done_contents
        .sort_by { |c| -c.chunks.size }
        .first(MAX_EXEMPLARS)
        .map(&:id)

      @persona.contents.where(is_exemplar: true).where.not(id: exemplar_ids).update_all(is_exemplar: false)
      @persona.contents.where(id: exemplar_ids).update_all(is_exemplar: true)
    end
  end
end
