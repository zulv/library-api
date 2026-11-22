class Book < ApplicationRecord
  include Discard::Model

  class AlreadyBorrowed < ConflictError
    def initialize = super("book is already borrowed")
  end

  class CannotDiscardBorrowed < ConflictError
    def initialize = super("book is borrowed and can't be removed")
  end

  has_many :borrowings
  has_one :active_borrowing, -> { active }, class_name: "Borrowing"

  delegate :due_on, to: :active_borrowing, allow_nil: true

  normalizes :serial_number, :title, :author, with: ->(value) { value.strip }

  validates :serial_number, :title, :author, presence: true
  validates :title, :author, length: { maximum: 255 }
  validates :serial_number, format: { with: /\A\d{6}\z/, allow_blank: true }, uniqueness: true

  before_discard :ensure_not_borrowed

  scope :with_serial_number, ->(serial_number) { where(serial_number:) if serial_number.present? }

  def borrowed?
    active_borrowing.present?
  end

  def status
    borrowed? ? "borrowed" : "available"
  end

  def borrow_by!(reader)
    with_lock do
      raise ActiveRecord::RecordNotFound.new("Couldn't find Book", "Book") if discarded?
      raise AlreadyBorrowed if borrowed?

      reader.lock!
      raise ActiveRecord::RecordNotFound.new("Couldn't find Reader", "Reader") if reader.anonymized?

      borrowings.create!(reader:)
    end
  end

  def return!
    with_lock do
      raise ActiveRecord::RecordNotFound unless borrowed?

      active_borrowing.tap(&:return!)
    end
  end

  def discard
    with_lock { super }
  end

  def borrowing_history
    borrowings.includes(:reader).newest_first
  end

  private

  def ensure_not_borrowed
    raise CannotDiscardBorrowed if borrowed?
  end
end
