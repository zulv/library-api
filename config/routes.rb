Rails.application.routes.draw do
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  get "up" => "rails/health#show", as: :rails_health_check

  defaults format: :json do
    resource :session, only: [ :create, :destroy ]
    resources :books, only: [ :index, :show, :create, :destroy ]
    resources :readers, only: [ :index, :show, :create, :destroy ]
  end
end
