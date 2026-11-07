class AddUserForeignKeyToPersonas < ActiveRecord::Migration[8.1]
  def change
    # user_id остаётся nullable: персоны, созданные до появления аккаунтов, привязываются rake-задачей users:create
    add_foreign_key :personas, :users
  end
end
