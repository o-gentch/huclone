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
      <div class="flex justify-end">
        <div class="max-w-lg bg-gray-900 text-white rounded-2xl rounded-tr-sm px-4 py-3 text-sm leading-relaxed">
          ${this.escapeHtml(content).replace(/\n/g, "<br>")}
        </div>
      </div>`
  }

  buildThinkingIndicator() {
    return `
      <div id="thinking-indicator" class="flex">
        <div class="bg-white border border-gray-200 rounded-2xl rounded-tl-sm px-4 py-3">
          <div class="flex items-center gap-1">
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay:0ms"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay:150ms"></span>
            <span class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay:300ms"></span>
          </div>
        </div>
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
