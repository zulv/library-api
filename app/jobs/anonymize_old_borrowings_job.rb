class AnonymizeOldBorrowingsJob < ApplicationJob
  def perform
    anonymized_count = Borrowing.anonymize_past_retention
    logger.info "Anonymized #{anonymized_count} borrowings past retention"
  end
end
