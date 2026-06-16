Rails.application.routes.draw do
  devise_for :users
  resources :books
  resources :user_books, only: [ :new, :create, :update, :destroy ]
  get "dashboard", to: "dashboard#index", as: :dashboard
  root to: "dashboard#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
