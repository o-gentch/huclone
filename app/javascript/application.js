// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()
import { Turbo } from "@hotwired/turbo-rails"

Turbo.StreamActions.scroll_to_bottom = function() {
  const el = document.getElementById(this.target)
  if (el) requestAnimationFrame(() => { el.scrollTop = el.scrollHeight })
}
