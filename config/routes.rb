Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: "users/registrations" }
  resources :books, only: [ :index, :show ] do
    member do
      get :most_recent_session
    end
    collection do
      get :discover
      get :search
      post :import
      get :quick_add
      post :quick_add
    end
    resources :reading_sessions, only: [ :new, :create ]
    resources :reviews, only: [ :new, :create, :edit, :update ]
  end
  resources :webhook_endpoints, only: [ :index, :create, :destroy ]
  post "/inbound_webhooks", to: "inbound_webhooks#receive"

  resources :reading_sessions, only: [ :index, :edit, :update, :destroy ]
  resources :reviews, only: [ :index ]
  get "/books/:book_id/reading_journal", to: "reading_sessions#show", as: :book_reading_journal
  get "/books/:book_id/finished_journal", to: "reading_sessions#finished", as: :book_finished_journal
  delete "/books/:book_id/finished_journal", to: "reading_sessions#destroy_finished"
  resources :challenges, only: [ :index, :show ]
  resources :user_challenges, only: [ :create, :destroy ]

  namespace :admin do
    root to: "challenges#index"
    get "catalog", to: "books#index", as: :catalog
    resources :reviews, only: [ :index, :destroy ]
    resources :members, only: [ :index, :create, :update, :destroy ]
    resources :book_clubs, only: [ :index, :create, :update, :destroy ] do
      get :search_books, on: :collection
    end
    resources :books, only: [ :new, :create, :edit, :update, :destroy ]
    resources :challenges, only: [ :index, :create, :update, :destroy ]
  end
  namespace :api do
    resources :reading_sessions, only: [ :index, :show, :create ]
  end
  resources :user_books, only: [ :new, :create, :update, :destroy ]
  resources :notifications, only: :update
  resources :book_clubs, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    get :search_books, on: :collection
    member do
      post :join
      delete :leave
      patch :set_current_book
    end
  end

  authenticate :user, ->(u) { u.admin? } do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  get "dashboard", to: "dashboard#index", as: :dashboard
  root to: "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
