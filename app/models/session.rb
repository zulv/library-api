class Session < ApplicationRecord
  LIFETIME = 12.hours

  belongs_to :user

  scope :expired, -> { where(created_at: ...LIFETIME.ago) }

  def self.purge_expired
    expired.in_batches.delete_all
  end
end
