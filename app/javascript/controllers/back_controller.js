import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  go(event) {
    event.preventDefault()
    history.back()
  }
}
