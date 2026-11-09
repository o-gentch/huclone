Rails.application.routes.draw do
  resource :session
  get "up" => "rails/health#show", as: :rails_health_check
  get "library", to: "library#index", as: :library
  post "library/connect", to: "library#connect", as: :connect_library
  post "library/delete", to: "library#delete", as: :delete_library
  get "library/recordings/:id", to: "library#recording", as: :library_recording
  get "library/recordings/:id/audio", to: "library#audio", as: :audio_library_recording
  delete "library/recordings/:id/personas/:persona_id", to: "library#disconnect", as: :library_recording_persona

  resources :personas, only: [ :new, :create, :edit, :update, :destroy ] do
    post :rebuild_portrait, on: :member
    resources :contents, only: [ :index, :new, :create, :destroy ] do
      member do
        post :retry
        post :toggle_exemplar
      end
    end
    resources :recordings, only: [ :index, :new, :create, :show, :destroy ] do
      member do
        post :retry
        post :reprocess
        post :confirm
        get :audio
      end
    end
    resources :topics, only: [ :index ] do
      collection do
        get :export
        post :rebuild
      end
    end
    resources :telegram_imports, only: [ :new, :create ]
    resources :conversations, only: [ :index, :new, :create, :show, :destroy ] do
      resources :messages, only: [ :create ]
    end
  end

  # Стандартные маршруты Active Storage отключены (config.active_storage.draw_routes = false):
  # публичные «ссылки-предъявители» на файлы не нужны. Оставлены только прямая загрузка и приём PUT на диск.
  post "/rails/active_storage/direct_uploads" => "direct_uploads#create", as: :rails_direct_uploads
  put "/rails/active_storage/disk/:encoded_token" => "active_storage/disk#update", as: :update_rails_disk_service

  root "personas#index"
  mount MissionControl::Jobs::Engine, at: "/jobs"
end
