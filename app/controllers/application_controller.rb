class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  stale_when_importmap_changes

  before_action :authenticate

  private

  # HTTP Basic для всего приложения (включая /jobs).
  # Креды: ENV APP_USERNAME / APP_PASSWORD или credentials.basic_auth.{username,password}.
  # В production без настроенных кредов доступ закрыт; в development/test — открыт.
  def authenticate
    username, password = basic_auth_credentials

    if username.blank? || password.blank?
      return if Rails.env.local?
      return head :forbidden
    end

    authenticate_or_request_with_http_basic("Huclone") do |u, p|
      ActiveSupport::SecurityUtils.secure_compare(u, username) &
        ActiveSupport::SecurityUtils.secure_compare(p, password)
    end
  end

  def basic_auth_credentials
    [
      ENV["APP_USERNAME"].presence || Rails.application.credentials.dig(:basic_auth, :username),
      ENV["APP_PASSWORD"].presence || Rails.application.credentials.dig(:basic_auth, :password)
    ]
  end
end
