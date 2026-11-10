module Contents
  module Connect
    module_function

    # role: "voice" — написано этим человеком (идёт в карту личности), "knowledge" — только в знания
    def call(persona, content, role: "voice")
      link = PersonaContent.find_or_create_by!(persona: persona, content: content) { |l| l.role = role }
      Personas::ContentReady.call(persona) if content.done?
      link
    rescue ActiveRecord::RecordNotUnique
      PersonaContent.find_by!(persona: persona, content: content)
    end

    # Отключение от DD. Материал без единой связи удаляется (пока нет экрана библиотеки)
    def disconnect(persona, content)
      Personas::RemoveContents.call(persona, [ content.id ])
      content.destroy if content.persona_contents.reload.none?
    end
  end
end
