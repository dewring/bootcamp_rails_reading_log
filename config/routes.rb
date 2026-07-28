Rails.application.routes.draw do
  devise_for :users
  resources :books, only: [ :index, :show ] do
    member do
      get :most_recent_session
    end
    collection do
      get :discover
      get :search
      post :import
    end
    resources :reading_sessions, only: [ :new, :create ]
    resources :reviews, only: [ :new, :create, :edit, :update ]
  end
  resources :webhook_endpoints, only: [ :index, :create, :destroy ]
  post "/inbound_webhooks", to: "inbound_webhooks#receive"

  resources :reading_sessions, only: [ :index, :edit, :update, :destroy ]
  resources :challenges, only: [ :index, :show ]
  resources :user_challenges, only: [ :create, :destroy ]

  namespace :admin do
    resources :books, only: [ :new, :create, :edit, :update, :destroy ]
    resources :challenges, only: [ :new, :create, :edit, :update, :destroy ]
  end
  namespace :api do
    resources :reading_sessions, only: [ :index, :show, :create ]
  end
  resources :user_books, only: [ :new, :create, :update, :destroy ]

  authenticate :user, ->(u) { u.admin? } do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  get "dashboard", to: "dashboard#index", as: :dashboard
  root to: "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
