class Conversation < ApplicationRecord
  belongs_to :persona
  has_many :messages, dependent: :destroy
end
