Rails.application.routes.draw do
  devise_for :users
  resources :books, only: [ :index, :show ] do
    member do
      get :most_recent_session
    end
    collection do
      get :discover
    end
    resources :reading_sessions, only: [ :new, :create ]
    resources :reviews, only: [ :new, :create, :edit, :update ]
  end

  resources :reading_sessions, only: [ :index, :edit, :update, :destroy ]

  namespace :admin do
    resources :books, only: [ :new, :create, :edit, :update, :destroy ]
  end
  namespace :api do
    resources :reading_sessions, only: [ :index, :show, :create ]
  end
  resources :user_books, only: [ :new, :create, :update, :destroy ]
  get "dashboard", to: "dashboard#index", as: :dashboard
  root to: "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
