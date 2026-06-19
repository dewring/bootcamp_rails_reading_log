Rails.application.routes.draw do
  devise_for :users
  resources :books do
    resources :reading_sessions, only: [ :new, :create ]
    resources :reviews, only: [ :new, :create, :edit, :update ]
  end
  resources :reading_sessions, only: [ :index, :edit, :update, :destroy ]
  resources :user_books, only: [ :new, :create, :update, :destroy ]
  get "dashboard", to: "dashboard#index", as: :dashboard
  root to: "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
