class Utterance < ApplicationRecord
  belongs_to :recording
  belongs_to :speaker

  def timecode = Recording.format_ms(start_ms)
end
