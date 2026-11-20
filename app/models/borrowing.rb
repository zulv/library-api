class Borrowing < ApplicationRecord
  LOAN_PERIOD = 30.days
  DUE_SOON_NOTICE = 3.days
  RETENTION_PERIOD = 2.years
  REMINDERS = {
    "due_soon" => { pending: :due_soon_reminder_pending, sent_at: :due_soon_reminder_sent_at },
    "due_today" => { pending: :due_today_reminder_pending, sent_at: :due_today_reminder_sent_at }
  }.freeze

  belongs_to :book
  belongs_to :reader, optional: true

  validates :reader, presence: true, on: :create
  validate :reader_not_anonymized, on: :create

  before_create :start_loan

  scope :active, -> { where(returned_at: nil) }
  scope :past_retention, -> { where(returned_at: ...RETENTION_PERIOD.ago).where.not(reader_id: nil) }
  scope :newest_first, -> { order(borrowed_at: :desc, id: :desc) }
  scope :with_identified_reader, -> { joins(:reader).merge(Reader.identified) }
  scope :due_soon_reminder_pending, ->(today = Date.current) {
    active.with_identified_reader.where(due_on: today.tomorrow..(today + DUE_SOON_NOTICE), due_soon_reminder_sent_at: nil)
  }
  scope :due_today_reminder_pending, ->(today = Date.current) {
    active.with_identified_reader.where(due_on: today, due_today_reminder_sent_at: nil)
  }

  def self.anonymize_past_retention
    past_retention.in_batches.update_all(reader_id: nil, updated_at: Time.current)
  end

  def self.reminder_pending(kind, today = Date.current)
    public_send(reminder(kind)[:pending], today)
  end

  def self.reminder(kind)
    REMINDERS.fetch(kind) { raise ArgumentError, "unknown reminder kind: #{kind.inspect}" }
  end

  def returned?
    returned_at.present?
  end

  def return!
    update!(returned_at: Time.current)
  end

  def identified_reader
    reader unless reader&.anonymized?
  end

  def reminder_pending?(kind)
    self.class.reminder_pending(kind).exists?(id)
  end

  def mark_reminder_sent!(kind)
    update!(self.class.reminder(kind)[:sent_at] => Time.current)
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
