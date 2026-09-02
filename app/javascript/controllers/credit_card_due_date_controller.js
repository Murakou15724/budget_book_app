import { Controller } from "@hotwired/stimulus"

// 支払予定日の入力欄を、前月/次月ボタンでその場(サーバー通信なし)にずらす。
// Ruby側(CreditCardPaymentCycle.resolve_payment_due_date)と同じ規則
// (支払日を月末で丸め、土日なら翌平日にずらす)をJS側でも再現している。
export default class extends Controller {
  static targets = ["input"]
  static values = { paymentDay: Number }

  shiftPrev() {
    this.shift(-1)
  }

  shiftNext() {
    this.shift(1)
  }

  shift(months) {
    if (!this.inputTarget.value) return

    const [year, month] = this.inputTarget.value.split("-").map(Number)
    const targetMonth = new Date(year, month - 1 + months, 1)

    const daysInTargetMonth = new Date(targetMonth.getFullYear(), targetMonth.getMonth() + 1, 0).getDate()
    const day = Math.min(this.paymentDayValue, daysInTargetMonth)
    const result = new Date(targetMonth.getFullYear(), targetMonth.getMonth(), day)

    while (result.getDay() === 0 || result.getDay() === 6) {
      result.setDate(result.getDate() + 1)
    }

    this.inputTarget.value = this.formatDate(result)
  }

  formatDate(date) {
    const y = date.getFullYear()
    const m = String(date.getMonth() + 1).padStart(2, "0")
    const d = String(date.getDate()).padStart(2, "0")
    return `${y}-${m}-${d}`
  }
}
