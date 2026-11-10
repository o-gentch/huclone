import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "input"]

  connect() {
    this.scrollToBottom()
  }

  // Fires when Turbo starts submitting — before roundtrip
  onSubmit(event) {
    const form = event.target
    const input = form.querySelector("textarea")
    const content = input?.value.trim()

    if (!content) {
      event.preventDefault()
      return
    }

    //  // Блокируем форму
    //  if (submit) submit.disabled = true
    //  if (input) {
    //    input.disabled = true
    //    input.value = ""
    //  }

    document.getElementById("empty-state")?.remove()

    this.appendToMessages(this.buildUserBubble(content))
    this.appendToMessages(this.buildThinkingIndicator())
    this.scrollToBottom()
  }

  onKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      if (this.hasInputTarget && this.inputTarget.value.trim()) {
        this.inputTarget.closest("form")?.requestSubmit()
      }
    }
  }

  // Клик по подсказке на пустом экране: подставляет текст и режим
  fill(event) {
    const { text, mode } = event.params
    if (!this.hasInputTarget) return
    this.inputTarget.value = text
    const radio = document.getElementById(`mode_${mode}`)
    if (radio) radio.checked = true
    this.inputTarget.focus()
    this.inputTarget.setSelectionRange(text.length, text.length)
  }

  onInput(event) {
    const el = event.target
    el.style.height = "auto"
    el.style.height = Math.min(el.scrollHeight, 160) + "px"
  }

  scrollToBottom() {
    if (this.hasMessagesTarget) {
      requestAnimationFrame(() => {
        this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
      })
    }
  }

  appendToMessages(html) {
    if (this.hasMessagesTarget) {
      this.messagesTarget.insertAdjacentHTML("beforeend", html)
    }
  }

  buildUserBubble(content) {
    return `
      <div class="msg-u">
        <div>${this.escapeHtml(content).replace(/\n/g, "<br>")}</div>
      </div>`
  }

  buildThinkingIndicator() {
    return `
      <div id="thinking-indicator" class="msg-a">
        <span class="blob blob-sm"><i></i></span>
        <div class="msg-body"><span class="typing"><i></i><i></i><i></i></span></div>
      </div>`
  }

  escapeHtml(str) {
    return str
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
