class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :personas, dependent: :destroy
  has_many :recordings, dependent: :destroy
  has_many :contents, dependent: :destroy
  has_many :usage_events, dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
