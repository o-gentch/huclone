module Conversations
  # Текст ответа → HTML. В режиме «Идеи» ответ приходит с маркерами:
  #   [[МАТЕРИАЛЫ]] краткое изложение того, что есть в материалах   → сворачиваемый блок
  #   [[НОВОЕ]]     новая и расширенная информация                  → основной текст
  module BodyRenderer
    MATERIALS = "[[МАТЕРИАЛЫ]]".freeze
    FRESH = "[[НОВОЕ]]".freeze

    module_function

    def call(text, streaming: false)
      text = text.to_s.gsub(/\r\n?/, "\n")
      text = text.sub(/\[\[[^\]]*\z/, "") if streaming # недописанный маркер не показываем

      html = if text.include?(MATERIALS)
        materials, fresh = text.sub(/\A.*?#{Regexp.escape(MATERIALS)}/m, "").split(FRESH, 2)
        block = paragraphs(materials)
        details = block.present? ? "<details class=\"from-materials\"><summary>Что есть в ваших материалах</summary>#{block}</details>" : ""
        details + paragraphs(fresh)
      else
        paragraphs(text.sub(FRESH, ""))
      end
      streaming ? html + "<span class=\"cursor\"></span>" : html
    end

    def paragraphs(text)
      text.to_s.strip.split(/\n{2,}/).map do |para|
        "<p class=\"mb-3 last:mb-0\">#{CGI.escapeHTML(para.strip).gsub("\n", "<br>")}</p>"
      end.join
    end
  end
end
