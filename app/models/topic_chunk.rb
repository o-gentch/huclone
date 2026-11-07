class TopicChunk < ApplicationRecord
  belongs_to :topic
  belongs_to :chunk
end
