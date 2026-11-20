class Borrowing < ApplicationRecord
  LOAN_PERIOD = 30.days

  belongs_to :book
  belongs_to :reader, optional: true

  validates :reader, presence: true, on: :create
  validate :reader_not_anonymized, on: :create

  before_create :start_loan

  scope :active, -> { where(returned_at: nil) }
  scope :newest_first, -> { order(borrowed_at: :desc, id: :desc) }

  def returned?
    returned_at.present?
  end

  def return!
    update!(returned_at: Time.current)
  end

  def identified_reader
    reader unless reader&.anonymized?
  end

  private

  def reader_not_anonymized
    errors.add(:reader, "is anonymized") if reader&.anonymized?
  end

  def start_loan
    self.borrowed_at ||= Time.current
    self.due_on = (borrowed_at + LOAN_PERIOD).to_date
  end
end
