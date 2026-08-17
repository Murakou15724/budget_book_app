Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "dashboard", to: "dashboard#index"
  resources :transactions, except: [:show] do
    collection do
      patch :mark_credit_card_paid
    end
  end
  resources :asset_snapshots, except: [:show]
  get "monthly_summaries", to: "monthly_summaries#index"
  get "monthly_reviews", to: "monthly_reviews#index"
  get "monthly_reviews/:year/:month/edit", to: "monthly_reviews#edit", as: :edit_monthly_review, constraints: { year: /\d+/, month: /\d+/ }
  patch "monthly_reviews/:year/:month", to: "monthly_reviews#update", as: :monthly_review, constraints: { year: /\d+/, month: /\d+/ }
  resources :categories, except: [:show]
  resources :accounts, except: [:show]
  resources :payment_methods, except: [:show]
  resource :settings, only: [:edit, :update]
  resource :budget_plan, only: [:edit, :update]
  get "more", to: "more#index"

  # Defines the root path route ("/")
  root "dashboard#index"
end
