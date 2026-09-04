# 資産スナップショット間で、取引記録から見込まれる口座残高の増減と、実際に記録された
# 増減との食い違いを検出する。DBには保持せず、都度計算する(他の集計クラスと同じ方針)。
#
# 食い違いは「振替/投資として記録すべきだった移動を支出として計上した」
# 「本来記録すべき取引を記録し忘れた」といった、二重計上や漏れのサインになりうる。
#
# 制約(いずれもベストエフォート。完全な複式簿記ではない):
# - kind: credit_pending(クレカ仮置き)の口座は対象外。現金ではなく「今後の支払義務」
#   を表す特殊な口座のため、別途 .credit_card_pending_diff で扱う。
# - クレジットカードの引落による口座残高の減少は、設定でクレカ引落元口座
#   (Setting#credit_card_payment_account)が指定されている場合のみ考慮する。
#   支払済への変更日時の履歴は保持していないため、updated_atが対象期間内かどうかで
#   近似する(期間内に無関係な編集をした場合は誤差の原因になりうる)。
class AccountReconciliation
  RECONCILABLE_KINDS = %w[bank e_money securities cash].freeze

  attr_reader :account, :expected_delta, :actual_delta

  # 直近2回のスナップショット間で、残高の記録があり見込みと食い違う口座だけを返す。
  def self.build_for(current_snapshot, previous_snapshot)
    return [] if current_snapshot.nil? || previous_snapshot.nil?

    period = (previous_snapshot.recorded_on + 1)..current_snapshot.recorded_on
    transactions = Transaction.actual.where(date: period).to_a
    payment_account_id = Setting.current.credit_card_payment_account_id
    prev_balances = previous_snapshot.asset_balances.index_by(&:account_id)
    curr_balances = current_snapshot.asset_balances.index_by(&:account_id)

    Account.where(kind: RECONCILABLE_KINDS).filter_map do |account|
      prev_balance = prev_balances[account.id]&.balance
      curr_balance = curr_balances[account.id]&.balance
      next if prev_balance.nil? || curr_balance.nil?

      expected_delta = expected_delta_for(account, transactions, payment_account_id, period)
      actual_delta = curr_balance - prev_balance
      next if expected_delta == actual_delta

      new(account: account, expected_delta: expected_delta, actual_delta: actual_delta)
    end
  end

  # クレカ仮置き口座の「スナップショット記録時点の残高」と、現在の未払いクレカ取引合計を比較する。
  # (未払い額は履歴を持たない現在値のため、最新スナップショットとの比較でのみ意味を持つ)
  def self.credit_card_pending_diff(snapshot)
    return nil if snapshot.nil?

    credit_pending_account = Account.find_by(kind: :credit_pending)
    return nil if credit_pending_account.nil?

    recorded = snapshot.asset_balances.find { |b| b.account_id == credit_pending_account.id }&.balance
    return nil if recorded.nil?

    recorded - Transaction.unpaid.sum(:amount)
  end

  def self.expected_delta_for(account, transactions, payment_account_id, period)
    transactions.sum do |t|
      next t.amount if t.account_id == account.id && t.income?
      next(-t.amount) if t.account_id == account.id && t.expense? && t.not_applicable?
      next(-t.amount) if t.account_id == account.id && (t.transfer? || t.investment?)
      next t.amount if t.to_account_id == account.id && (t.transfer? || t.investment?)
      next(-t.amount) if payment_account_id == account.id && t.paid? && period.cover?(t.updated_at.to_date)

      0
    end
  end
  private_class_method :expected_delta_for

  def initialize(account:, expected_delta:, actual_delta:)
    @account = account
    @expected_delta = expected_delta
    @actual_delta = actual_delta
  end

  def diff
    actual_delta - expected_delta
  end
end
