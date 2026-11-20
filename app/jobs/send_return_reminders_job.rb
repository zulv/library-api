class SendReturnRemindersJob < ApplicationJob
  def perform
    Borrowing.due_soon_reminder_pending.find_each { |borrowing| ReturnReminderJob.perform_later(borrowing, "due_soon") }
    Borrowing.due_today_reminder_pending.find_each { |borrowing| ReturnReminderJob.perform_later(borrowing, "due_today") }
  end
end
