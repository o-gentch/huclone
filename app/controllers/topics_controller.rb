class TopicsController < ApplicationController
  before_action :set_persona

  def index
    @tree = Knowledge::Outline.tree(@persona)
  end

  def export
    send_data Knowledge::Outline.markdown(@persona),
              filename: "knowledge-structure.md", type: "text/markdown; charset=utf-8", disposition: "attachment"
  end

  def rebuild
    Knowledge::BuildTopicTreeJob.perform_later(@persona.id, true)
    redirect_to persona_topics_path(@persona), notice: "Дерево тем пересобирается — обновите страницу через минуту"
  end

  private

  def set_persona
    @persona = Current.user.personas.find(params[:persona_id])
  end
end
