module Transcription
  # Тестовый провайдер: читает JSON из test/fixtures/files/transcripts/<fixture>.json
  class Fake < Provider
    attr_accessor :fixture, :pending_polls, :submit_error, :fetch_error
    attr_reader :submitted, :submit_count

    def initialize(fixture: "interview")
      @fixture = fixture
      @pending_polls = 0
      @submitted = []
      @submit_count = 0
    end

    def cost_per_hour_usd = 0.17

    def submit(_io, expected_speakers: nil, language: "ru")
      raise submit_error if submit_error
      @submit_count += 1
      @submitted << { expected_speakers: expected_speakers, language: language }
      "fake-#{@submit_count}"
    end

    def fetch(_job_id)
      raise fetch_error if fetch_error
      if @pending_polls.positive?
        @pending_polls -= 1
        return :pending
      end
      data = JSON.parse(Rails.root.join("test/fixtures/files/transcripts/#{fixture}.json").read, symbolize_names: true)
      Result.new(utterances: data[:utterances], duration_ms: data[:duration_ms])
    end
  end
end
