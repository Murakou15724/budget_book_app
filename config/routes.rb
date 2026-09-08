Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # 外部cronから定期的に叩いて起こす(Renderの無料プランはアクセスが無いとスリープする)用の、
  # DBアクセス・ビューレンダリングを一切行わない最小コスト routing。
  get "ping", to: "ping#show"

  get "dashboard", to: "dashboard#index"

  # 筋トレ記録
  get "workouts", to: "workouts#index"
  resources :workout_days
  resources :exercises, except: [:show]
  resources :badges, except: [:show]
  get "weekly_reviews", to: "weekly_reviews#index"
  get "weekly_reviews/:week_start_date/edit", to: "weekly_reviews#edit", as: :edit_weekly_review,
      constraints: { week_start_date: /\d{4}-\d{2}-\d{2}/ }
  patch "weekly_reviews/:week_start_date", to: "weekly_reviews#update", as: :weekly_review,
      constraints: { week_start_date: /\d{4}-\d{2}-\d{2}/ }

  resources :transactions, except: [:show] do
    collection do
      patch :mark_credit_card_paid
    end
    member do
      patch :shift_credit_card_payment_due_on
    end
  end
  resources :asset_snapshots, except: [:show] do
    collection do
      get :reconcile_preview
      patch :force_align
    end
  end
  get "credit_card_unpaids", to: "credit_card_unpaids#index"
  get "monthly_summaries", to: "monthly_summaries#index"
  get "monthly_summaries/:year/:month/actual_balance", to: "monthly_summaries#actual_balance",
      as: :monthly_summary_actual_balance, constraints: { year: /\d+/, month: /\d+/ }
  get "monthly_reviews", to: "monthly_reviews#index"
  get "monthly_reviews/:year/:month/edit", to: "monthly_reviews#edit", as: :edit_monthly_review, constraints: { year: /\d+/, month: /\d+/ }
  patch "monthly_reviews/:year/:month", to: "monthly_reviews#update", as: :monthly_review, constraints: { year: /\d+/, month: /\d+/ }
  resources :categories, except: [:show]
  resources :accounts, except: [:show]
  resources :payment_methods, except: [:show]
  resources :quick_entry_templates, except: [:show]
  resource :image_imports, only: [:new, :create]
  resources :image_import_drafts, only: [:index, :destroy] do
    collection do
      patch :bulk_approve
      delete :bulk_reject
    end
  end
  resource :settings, only: [:edit, :update]
  resource :budget_plan, only: [:edit, :update]
  get "more", to: "more#index"

  # config.exceptions_appから例外発生時に振り分けられるエラーページ用ルート。
  match "/404", to: "errors#not_found", via: :all
  match "/422", to: "errors#unprocessable_entity", via: :all
  match "/500", to: "errors#internal_server_error", via: :all
  match "/:status_code", to: "errors#show", via: :all, constraints: { status_code: /\d{3}/ }

  # Defines the root path route ("/")
  root "home#index"
end
