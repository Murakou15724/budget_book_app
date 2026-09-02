module CreditCardPaymentCycle
  extend ActiveSupport::Concern

  included do
    # プリフィルされたcredit_card_payment_due_on_overrideが、実は自動計算値と
    # 同じ(=手を加えていない)場合は上書きとして保存しない。そうしないと、
    # 画面を開いただけで(値を変更しなくても)全件が上書き扱いになってしまう。
    before_save :clear_redundant_credit_card_payment_due_on_override
  end

  # 利用日(date)から、設定済みの締め日・支払日に基づいて支払予定日を算出する。
  # 締め日以前の利用は当月締め、締め日より後の利用は翌月締めとし、
  # 支払いは締め月の翌月(支払日)に行われる(例: 締め15日・支払日26日の場合、
  # 7/20の利用は8月締め→9/26払い、8/10の利用も8月締め→9/26払いとなる)。
  # 支払日が土日にあたる場合は翌平日にずらす(祝日は非対応)。
  #
  # 実際のカード会社の締め処理には例外(取込日と処理日のズレ等)が発生することがあり、
  # その場合はcredit_card_payment_due_on_overrideで個別に補正できる。
  def credit_card_payment_due_on
    credit_card_payment_due_on_override || calculated_credit_card_payment_due_on
  end

  def calculated_credit_card_payment_due_on
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

  private

  def clear_redundant_credit_card_payment_due_on_override
    return if credit_card_payment_due_on_override.blank?

    self.credit_card_payment_due_on_override = nil if credit_card_payment_due_on_override == calculated_credit_card_payment_due_on
  end
end
