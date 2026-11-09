module Personas
  class ExemplarSelector
    MAX_EXEMPLARS = 7

    def self.call(persona) = new(persona).call

    def initialize(persona)
      @persona = persona
    end

    def call
      # Эталоны — только письменные тексты: по ним выбирается письменный голос
      # Ручной выбор пользователя (exemplar_pinned) автоматика не трогает
      pinned = @persona.persona_contents.where(exemplar_pinned: true)
      slots = MAX_EXEMPLARS - pinned.where(is_exemplar: true).count

      done = @persona.contents.merge(PersonaContent.voice).posts.done.where.not(id: pinned.select(:content_id))
      return unless done.exists? || slots <= 0

      # Самые длинные материалы (по длине текста) — без загрузки записей и чанков
      exemplar_ids = slots.positive? ? done.order(Arel.sql("char_length(body) DESC")).limit(slots).pluck(:id) : []

      auto = @persona.persona_contents.where(exemplar_pinned: false)
      auto.where(is_exemplar: true).where.not(content_id: exemplar_ids).update_all(is_exemplar: false)
      auto.where(content_id: exemplar_ids).update_all(is_exemplar: true)
    end
  end
end
