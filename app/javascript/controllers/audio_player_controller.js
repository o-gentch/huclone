import { Controller } from "@hotwired/stimulus"

// Один <audio> на странице; кнопки «прослушать» проигрывают фрагмент [start, end]
export default class extends Controller {
  static targets = ["audio"]

  // Ссылка вида #t=754 открывает запись на нужном моменте
  connect() {
    const m = window.location.hash.match(/^#t=(\d+)/)
    if (!m) return
    const seek = () => { this.audioTarget.currentTime = parseInt(m[1], 10) }
    if (this.audioTarget.readyState >= 1) seek()
    else this.audioTarget.addEventListener("loadedmetadata", seek, { once: true })
  }

  play(event) {
    const start = parseFloat(event.params.start)
    const end = parseFloat(event.params.end)
    const audio = this.audioTarget
    audio.currentTime = start
    this.stopAt = end
    audio.play()
  }

  tick() {
    if (this.stopAt && this.audioTarget.currentTime >= this.stopAt) {
      this.audioTarget.pause()
      this.stopAt = null
    }
  }
}
