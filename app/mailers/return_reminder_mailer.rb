class ReturnReminderMailer < ApplicationMailer
  before_action { @borrowing = params[:borrowing] }

  def due_soon
    mail to: @borrowing.reader.email, subject: "Reminder: your library book is due soon"
  end

  def due_today
    mail to: @borrowing.reader.email, subject: "Your library book is due today"
  end
end
