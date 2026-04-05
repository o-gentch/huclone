class BuildPersonalityMapJob < ApplicationJob
  queue_as :default

  def perform(persona_id)
    PersonalityMapBuilder.build(persona_id)
  end
end
