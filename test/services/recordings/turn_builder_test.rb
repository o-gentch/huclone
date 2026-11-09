require "test_helper"

class Recordings::TurnBuilderTest < ActiveSupport::TestCase
  setup do
    @persona = users(:one).personas.create!(name: "P")
    @recording = create_recording(@persona, status: "confirmed")
    @me = @recording.speakers.create!(label: "A")
    @host = @recording.speakers.create!(label: "B", display_name: "Ведущий")
    @guest = @recording.speakers.create!(label: "C")
    @pos = 0
  end

  def say(speaker, text, start: nil, finish: nil, confidence: 0.9)
    start ||= @pos
    finish ||= start + 5_000
    @pos = finish + 500
    @recording.utterances.create!(speaker: speaker, position: @recording.utterances.count, start_ms: start,
                                  end_ms: finish, text: text, confidence: confidence)
  end

  def words(n, word = "слово") = ([ word ] * n).join(" ") + "."

  test "talk without questions yields plain speech segments" do
    say @me, words(40)
    turns = Recordings::TurnBuilder.call(@recording, speaker: @me)
    assert_equal 1, turns.size
    assert_nil turns.first.context_text
  end

  test "question followed by answer attaches the question to the answer" do
    say @host, "Расскажите, как вы начинали?"
    say @me, words(30)
    turns = Recordings::TurnBuilder.call(@recording, speaker: @me)
    assert_equal "Расскажите, как вы начинали?", turns.first.context_text
    assert_equal "Ведущий", turns.first.speaker_name
  end

  test "several consecutive questions are limited to the last three utterances" do
    4.times { |i| say @host, "Вопрос номер #{i}?" }
    say @me, words(30)
    q = Recordings::TurnBuilder.call(@recording, speaker: @me).first.context_text
    assert_not_includes q, "номер 0"
    assert_includes q, "номер 3"
  end

  test "a distant or huge question is not attached" do
    say @host, words(200)
    say @me, words(30)
    assert_nil Recordings::TurnBuilder.call(@recording, speaker: @me).first.context_text
  end

  test "question from a different speaker pair is picked from the utterances directly before the answer" do
    say @guest, "Вопрос из зала?"
    say @host, "Уточню: а что с деньгами?"
    say @me, words(30)
    q = Recordings::TurnBuilder.call(@recording, speaker: @me).first.context_text
    assert_includes q, "Вопрос из зала?"
    assert_includes q, "а что с деньгами"
  end

  test "a long answer is split into fragments and only the first one carries the question" do
    say @host, "Расскажите всё?"
    sentence = "Это довольно длинное предложение про важную тему номер один и два."
    long = ([ sentence ] * 400).join(" ") # ~ 5600 слов
    say @me, long, start: 0, finish: 600_000
    turns = Recordings::TurnBuilder.call(@recording, speaker: @me)
    assert_operator turns.size, :>=, 3
    assert turns.all? { |t| t.text.split.size <= Recordings::TurnBuilder::MAX_FRAGMENT_WORDS + 20 }
    assert turns.first.context_text.present?
    assert turns[1..].all? { |t| t.context_text.nil? }
    assert_equal turns.map(&:start_ms), turns.map(&:start_ms).sort
  end

  test "splits at a long pause between utterances once enough words are collected" do
    say @me, words(350), start: 0, finish: 100_000
    say @me, words(50), start: 120_000, finish: 140_000
    turns = Recordings::TurnBuilder.call(@recording, speaker: @me)
    # две реплики одного спикера подряд, пауза 20 с и набрано > 300 слов
    assert_equal 2, turns.size
  end

  test "drops low confidence utterances, very short answers and other speakers' speech" do
    say @host, "Это речь ведущего без ответа персоны и её не нужно сохранять никуда."
    say @me, words(40), confidence: 0.2
    say @guest, "Ещё вопрос?"
    say @me, "Да, конечно."
    assert_empty Recordings::TurnBuilder.call(@recording, speaker: @me)
  end

  test "a speaker with no utterances produces no turns" do
    say @host, words(40)
    assert_empty Recordings::TurnBuilder.call(@recording, speaker: @me)
  end
end
