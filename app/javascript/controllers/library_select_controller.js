import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["box"]

  toggleAll(event) {
    this.boxTargets.forEach((box) => { box.checked = event.target.checked })
  }
}
