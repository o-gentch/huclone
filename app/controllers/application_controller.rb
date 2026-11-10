class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  stale_when_importmap_changes

  helper_method :current_persona

  # Выбранный Digital Double: из пути /personas/:persona_id/..., иначе первый
  def current_persona
    return unless Current.user

    @current_persona ||= Current.user.personas.find_by(id: params[:persona_id] || (params[:id] if controller_name == "personas")) ||
                         Current.user.personas.order(:id).first
  end
end
