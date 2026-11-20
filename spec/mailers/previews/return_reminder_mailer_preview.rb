class ReturnReminderMailerPreview < ActionMailer::Preview
  def due_soon
    ReturnReminderMailer.with(borrowing: borrowing_due_on(Date.current + Borrowing::DUE_SOON_NOTICE)).due_soon
  end

  def due_today
    ReturnReminderMailer.with(borrowing: borrowing_due_on(Date.current)).due_today
  end

  private

  def borrowing_due_on(due_on)
    Borrowing.new(
      book: Book.new(title: "Solaris", author: "Stanisław Lem"),
      reader: Reader.new(full_name: "Anna Kowalska", email: "anna.kowalska@example.com"),
      due_on:
    )
  end
end
