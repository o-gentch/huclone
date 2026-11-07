module Transcription
  # utterances: [{speaker:, start_ms:, end_ms:, text:, confidence:}]
  Result = Struct.new(:utterances, :duration_ms, keyword_init: true)
end
