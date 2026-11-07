module Personas
  class ExemplarSelector
    MAX_EXEMPLARS = 7

    def self.call(persona) = new(persona).call

    def initialize(persona)
      @persona = persona
    end

    def call
      # Эталоны — только письменные тексты: по ним выбирается письменный голос
      done = @persona.contents.posts.done
      return unless done.exists?

      # Самые длинные материалы (по длине текста) — без загрузки записей и чанков
      exemplar_ids = done.order(Arel.sql("char_length(body) DESC")).limit(MAX_EXEMPLARS).pluck(:id)

      @persona.contents.where(is_exemplar: true).where.not(id: exemplar_ids).update_all(is_exemplar: false)
      @persona.contents.where(id: exemplar_ids).update_all(is_exemplar: true)
    end
  end
end
