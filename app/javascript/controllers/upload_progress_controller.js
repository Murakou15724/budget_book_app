import { Controller } from "@hotwired/stimulus"

// アップロードフォームのsubmitからページ遷移までの待ち時間、
// AIが処理中であることをメッセージのローテーションで示す。
export default class extends Controller {
  static targets = ["overlay", "message"]

  static MESSAGES = [
    "画像を読み込んでいます…",
    "AIが文字を読み取っています…",
    "取引の候補をまとめています…",
    "カテゴリや口座を推測しています…",
    "もう少しで完了します…"
  ]

  connect() {
    this.messageIndex = 0
  }

  disconnect() {
    this.stopRotation()
  }

  start() {
    this.overlayTarget.classList.add("is-active")
    this.messageIndex = 0
    this.messageTarget.textContent = this.constructor.MESSAGES[0]
    this.intervalId = window.setInterval(() => this.rotateMessage(), 2200)
  }

  rotateMessage() {
    this.messageIndex = (this.messageIndex + 1) % this.constructor.MESSAGES.length
    this.messageTarget.textContent = this.constructor.MESSAGES[this.messageIndex]
  }

  stopRotation() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
  }
}
