require "net/smtp"

class ReturnReminderJob < ApplicationJob
  retry_on Net::OpenTimeout, Net::ReadTimeout, Net::SMTPServerBusy,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, EOFError, SocketError,
    wait: :polynomially_longer, attempts: 5

  def perform(borrowing, kind)
    sent = borrowing.with_lock { send_reminder(borrowing, kind) if borrowing.reminder_pending?(kind) }
    logger.info "Sent #{kind} reminder for borrowing #{borrowing.id}" if sent
  end

  private

  def send_reminder(borrowing, kind)
    ReturnReminderMailer.with(borrowing:).public_send(kind).deliver_now
    borrowing.mark_reminder_sent!(kind)
  end
end
