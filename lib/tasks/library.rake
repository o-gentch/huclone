require_relative "../../db/support/library_backfill"

namespace :library do
  desc "Сухой прогон переноса в библиотеку: сколько записей, дублей и персон без владельца (запускать ДО миграции)"
  task dry_run: :environment do
    LibraryBackfill.print_report(LibraryBackfill.report(ActiveRecord::Base.connection))
  end
end
