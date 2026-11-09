module Personas
  # Вызывается, когда у DD появились/дообработались материалы: резюме записей, карта личности.
  module ContentReady
    module_function

    def call(persona)
      persona.persona_recordings.ready.where(summary: nil).find_each do |pr|
        links = pr.persona_contents
        next if links.empty?
        next if Content.where(id: links.select(:content_id), status: %w[pending processing]).exists?

        Knowledge::SummarizeRecordingJob.perform_later(pr.id)
      end

      return if persona.contents.where(status: %w[pending processing]).exists?

      persona.schedule_map_build!
    end
  end
end
