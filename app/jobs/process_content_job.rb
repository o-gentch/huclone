class ProcessContentJob < ApplicationJob
  queue_as :default

  def perform(content_id)
    ContentProcessor.process(content_id)
  end
end
