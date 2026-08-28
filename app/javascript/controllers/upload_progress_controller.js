import { Controller } from "@hotwired/stimulus"

// アップロードフォームのsubmitからページ遷移までの待ち時間、
// AIが処理中であることをアイコン+メッセージのクロスフェードで示す。
export default class extends Controller {
  static targets = ["overlay", "message", "icon"]

  static FADE_MS = 250
  static ROTATE_MS = 2200

  static STEPS = [
    { icon: "📥", text: "画像を読み込んでいます…" },
    { icon: "🔍", text: "AIが文字を読み取っています…" },
    { icon: "🗂️", text: "取引の候補をまとめています…" },
    { icon: "🏷️", text: "カテゴリや口座を推測しています…" },
    { icon: "✨", text: "もう少しで完了します…" }
  ]

  connect() {
    this.stepIndex = 0
  }

  disconnect() {
    this.stopRotation()
  }

  start() {
    this.overlayTarget.classList.add("is-active")
    this.stepIndex = 0
    this.render(this.constructor.STEPS[0])
    this.intervalId = window.setInterval(() => this.rotateStep(), this.constructor.ROTATE_MS)
  }

  rotateStep() {
    this.stepIndex = (this.stepIndex + 1) % this.constructor.STEPS.length
    const step = this.constructor.STEPS[this.stepIndex]

    this.messageTarget.classList.add("is-fading")
    this.iconTarget.classList.add("is-fading")

    window.setTimeout(() => {
      this.render(step)
      this.messageTarget.classList.remove("is-fading")
      this.iconTarget.classList.remove("is-fading")
    }, this.constructor.FADE_MS)
  }

  render(step) {
    this.messageTarget.textContent = step.text
    this.iconTarget.textContent = step.icon
  }

  stopRotation() {
    if (this.intervalId) {
      window.clearInterval(this.intervalId)
      this.intervalId = null
    }
  }
}
