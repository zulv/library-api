class Reader < ApplicationRecord
  encrypts :full_name
  encrypts :email, deterministic: true

  normalizes :card_number, :full_name, with: ->(value) { value.strip }
  normalizes :email, with: ->(value) { value.strip.downcase }

  with_options unless: :anonymized? do
    validates :card_number, :full_name, :email, presence: true
    validates :full_name, length: { maximum: 255 }
    validates :email, length: { maximum: 254 }
    validates :card_number, format: { with: /\A\d{6}\z/, allow_blank: true }, uniqueness: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }, uniqueness: true
  end

  scope :identified, -> { where(anonymized_at: nil) }
  scope :with_card_number, ->(card_number) { where(card_number:) if card_number.present? }

  def anonymized?
    anonymized_at.present?
  end

  def anonymize!
    return if anonymized?

    update!(card_number: nil, full_name: nil, email: nil, anonymized_at: Time.current)
  end
end
