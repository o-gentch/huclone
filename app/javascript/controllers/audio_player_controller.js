import { Controller } from "@hotwired/stimulus"

// Один <audio> на странице; кнопки «прослушать» проигрывают фрагмент [start, end]
export default class extends Controller {
  static targets = ["audio"]

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
