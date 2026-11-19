class Book < ApplicationRecord
  include Discard::Model

  normalizes :serial_number, :title, :author, with: ->(value) { value.strip }

  validates :serial_number, :title, :author, presence: true
  validates :title, :author, length: { maximum: 255 }
  validates :serial_number, format: { with: /\A\d{6}\z/, allow_blank: true }, uniqueness: true

  scope :with_serial_number, ->(serial_number) { where(serial_number:) if serial_number.present? }
end
