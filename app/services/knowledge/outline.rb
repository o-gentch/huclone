module Knowledge
  # Дерево тем в текстовом виде: для промпта режима «книга» и для Markdown-экспорта.
  module Outline
    MAX_PROMPT_CHARS = 8_000

    module_function

    def tree(persona)
      topics = persona.topics.order(:depth, :position).to_a
      by_parent = topics.group_by(&:parent_id)
      build = ->(parent_id) { (by_parent[parent_id] || []).sort_by(&:position).map { |t| [ t, build.call(t.id) ] } }
      build.call(nil)
    end

    # Для промпта: нумерованное оглавление; при превышении бюджета резюме отбрасываются
    def prompt_text(persona)
      nodes = tree(persona)
      return nil if nodes.empty?

      text = render(nodes, summaries: true)
      text.length > MAX_PROMPT_CHARS ? render(nodes, summaries: false).truncate(MAX_PROMPT_CHARS) : text
    end

    def render(nodes, prefix: "", summaries: true)
      nodes.each_with_index.map do |(topic, children), i|
        number = "#{prefix}#{i + 1}"
        line = "#{'  ' * topic.depth}#{number}. #{topic.title}"
        line += " — #{topic.summary}" if summaries && topic.summary.present?
        [ line, render(children, prefix: "#{number}.", summaries: summaries) ].reject(&:blank?).join("\n")
      end.join("\n")
    end

    def markdown(persona)
      lines = [ "# Оглавление: #{persona.name}", "" ]
      walk_markdown(tree(persona), "", lines)
      lines.join("\n") + "\n"
    end

    def walk_markdown(nodes, prefix, lines)
      nodes.each_with_index do |(topic, children), i|
        number = "#{prefix}#{i + 1}"
        lines << "#{'#' * [ topic.depth + 2, 6 ].min} #{number}. #{topic.title}"
        lines << ""
        lines << topic.summary if topic.summary.present?
        lines << "" if topic.summary.present?
        if children.empty?
          sources = topic.sources
          if sources.any?
            lines << "Источники:"
            sources.each { |s| lines << "- «#{s[:title]}», #{Recording.format_ms(s[:start_ms].to_i)}" }
            lines << ""
          end
        else
          walk_markdown(children, "#{number}.", lines)
        end
      end
    end
  end
end
