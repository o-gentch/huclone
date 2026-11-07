import { Controller } from "@hotwired/stimulus"

// Прогресс прямой загрузки (Active Storage direct upload)
export default class extends Controller {
  static targets = ["progressWrap", "bar", "label", "submit"]

  start() {
    this.progressWrapTarget.classList.remove("hidden")
    this.submitTarget.disabled = true
  }

  progress(event) {
    const pct = Math.round(event.detail.progress)
    this.barTarget.style.width = `${pct}%`
    this.labelTarget.textContent = `Загрузка… ${pct}%`
  }

  end() {
    this.labelTarget.textContent = "Файл загружен, создаём запись…"
  }

  error(event) {
    event.preventDefault()
    this.submitTarget.disabled = false
    this.labelTarget.textContent = "Не удалось загрузить файл. Проверьте тип и размер и попробуйте ещё раз."
  }
}
