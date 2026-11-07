require "test_helper"

class Knowledge::OutlineAndBookTest < ActiveSupport::TestCase
  setup do
    @persona = users(:one).personas.create!(name: "Автор")
    @recording = create_recording(@persona, status: "confirmed", title: "Конференция")
    n = 0
    2.times { |c| 8.times { create_speech(@persona, @recording, c, n += 1) } }
    Knowledge::TopicTreeBuilder.call(@persona, ai_client: NamingClient.new)
  end

  test "prompt outline is numbered and includes summaries" do
    text = Knowledge::Outline.prompt_text(@persona)
    assert_match(/^1\. Тема/, text)
    assert_match(/^2\. Тема/, text)
    assert_includes text, "Резюме темы"
  end

  test "markdown export has headings and timecoded sources" do
    md = Knowledge::Outline.markdown(@persona)
    assert_match(/\A# Оглавление: Автор/, md)
    assert_match(/^## 1\. Тема/, md)
    assert_match(/Источники:/, md)
    assert_match(/- «Конференция», \d+:\d\d/, md)
  end

  test "empty persona has no outline" do
    assert_nil Knowledge::Outline.prompt_text(users(:two).personas.create!(name: "Пусто"))
  end

  class FakeEmbeddings
    def initialize(vec) = @vec = vec
    def fetch(_text) = @vec
  end

  test "table-of-contents request returns the outline only" do
    ctx = Knowledge::BookContext.call(@persona, "Составь оглавление книги по всем выступлениям", embeddings: FakeEmbeddings.new(cluster_vector(0)))
    assert ctx.outline.present?
    assert_empty ctx.chunks
  end

  test "chapter request pulls chunks of the closest topic with sources" do
    ctx = Knowledge::BookContext.call(@persona, "Раскрой главу про это подробно", embeddings: FakeEmbeddings.new(cluster_vector(1)))
    assert ctx.topic
    assert_operator ctx.chunks.size, :>, 0
    assert ctx.chunks.all? { |c| c.embedding.each_with_index.max[1] == 1 }
    assert_match(/Из выступления «Конференция»/, ctx.chunks.first.source_label)
  end

  test "without a tree there is no outline (falls back to plain RAG)" do
    other = users(:two).personas.create!(name: "X")
    assert_nil Knowledge::BookContext.call(other, "оглавление", embeddings: FakeEmbeddings.new(cluster_vector(0))).outline
  end
end
