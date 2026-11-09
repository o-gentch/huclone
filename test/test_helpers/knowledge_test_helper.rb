module KnowledgeTestHelper
  # Вектор «около оси cluster» — для детерминированной кластеризации в тестах
  def cluster_vector(cluster, noise_seed = 0)
    rng = Random.new(noise_seed + cluster * 1000)
    Array.new(1536) { |i| i == cluster ? 1.0 : rng.rand * 0.02 }
  end

  # Материал библиотеки + связь с DD
  def add_content(persona, role: "voice", is_exemplar: false, included_in_map: false, **attrs)
    content = Content.create!({ user: persona.user, sources: [] }.merge(attrs))
    PersonaContent.create!(persona: persona, content: content, role: role, is_exemplar: is_exemplar, included_in_map: included_in_map)
    content
  end

  def create_speech(persona, recording, cluster, n, text: nil, summary: "Резюме #{n}")
    content = Content.create!(
      user: persona.user, kind: "speech", recording: recording, title: "s#{n}", body: text || "Ответ автора номер #{n}.", raw_body: "сырой #{n}",
      status: "done", sources: [], summary: summary, start_ms: n * 10_000, end_ms: n * 10_000 + 9_000, context_text: "Вопрос #{n}?"
    )
    link = persona.persona_recordings.find_by(recording: recording)
    link&.update!(status: "ready")
    PersonaContent.create!(persona: persona, content: content, persona_recording: link, role: "voice")
    content.chunks.create!(text: content.body, position: 0, start_ms: content.start_ms, embedding: cluster_vector(cluster, n))
    content
  end

  class NamingClient
    attr_reader :calls
    def initialize = @calls = 0

    def chat(parameters:)
      @calls += 1
      content = if parameters[:response_format]
        { title: "Тема #{@calls}", summary: "Резюме темы #{@calls}" }.to_json
      else
        "Резюме текста #{@calls}"
      end
      { "choices" => [ { "message" => { "content" => content } } ], "usage" => { "prompt_tokens" => 1, "completion_tokens" => 1 } }
    end
  end
end

ActiveSupport.on_load(:active_support_test_case) { include KnowledgeTestHelper }
