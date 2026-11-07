Rails.application.routes.draw do
  resource :session
  get "up" => "rails/health#show", as: :rails_health_check
  resources :personas, only: [ :new, :create ] do
    resources :contents, only: [ :index, :new, :create, :destroy ]
    resources :telegram_imports, only: [ :new, :create ]
    resources :conversations, only: [ :index, :new, :create, :show ] do
      resources :messages, only: [ :create ]
    end
  end

  root "personas#index"
  mount MissionControl::Jobs::Engine, at: "/jobs"
end
