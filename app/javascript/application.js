// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { Turbo } from "@hotwired/turbo-rails"

Turbo.StreamActions.scroll_to_bottom = function() {
  const el = document.getElementById(this.target)
  if (el) requestAnimationFrame(() => { el.scrollTop = el.scrollHeight })
}
