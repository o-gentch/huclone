module Knowledge
  class SummarizeRecordingJob < ApplicationJob
    queue_as :personality_map
    def perform(recording_id); end
  end
end
