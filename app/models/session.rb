class Session < ApplicationRecord
  LIFETIME = 12.hours

  belongs_to :user
end
