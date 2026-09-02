module CreditCardPaymentCycle
  extend ActiveSupport::Concern

  # 利用日(date)から、設定済みの締め日・支払日に基づいて支払予定日を算出する。
  # 締め日以前の利用は当月締め、締め日より後の利用は翌月締めとし、
  # 支払いは締め月の翌月(支払日)に行われる(例: 締め15日・支払日26日の場合、
  # 7/20の利用は8月締め→9/26払い、8/10の利用も8月締め→9/26払いとなる)。
  # 支払日が土日にあたる場合は翌平日にずらす(祝日は非対応)。
  def credit_card_payment_due_on
    return nil if date.blank?

    setting = Setting.current
    closing_day = setting.credit_card_closing_day
    payment_day = setting.credit_card_payment_day

    closing_month = date.day <= closing_day ? date.beginning_of_month : date.next_month.beginning_of_month
    payment_month = closing_month.next_month
    last_day_of_payment_month = payment_month.end_of_month.day
    due_date = payment_month.change(day: [payment_day, last_day_of_payment_month].min)

    due_date += 1 while due_date.saturday? || due_date.sunday?
    due_date
  end
end
