Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :transactions, except: [:show] do
    collection do
      patch :mark_credit_card_paid
    end
  end
  resources :categories, except: [:show]
  resources :accounts, except: [:show]
  resources :payment_methods, except: [:show]
  resource :settings, only: [:edit, :update]
  resource :budget_plan, only: [:edit, :update]

  # Defines the root path route ("/")
  root "transactions#index"
end
