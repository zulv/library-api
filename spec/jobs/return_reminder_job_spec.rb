require "rails_helper"

RSpec.describe ReturnReminderJob, type: :job do
  include ActiveJob::TestHelper

  let(:today) { Time.zone.local(2026, 3, 10, 8) }
  let(:due_soon_borrowing) { create(:borrowing, borrowed_at: today - 28.days) }
  let(:due_today_borrowing) { create(:borrowing, borrowed_at: today - 30.days) }

  before { ActionMailer::Base.deliveries.clear }

  around { |example| travel_to(today) { example.run } }

  it "sends the due soon email and marks it as sent" do
    described_class.perform_now(due_soon_borrowing, "due_soon")

    expect(ActionMailer::Base.deliveries.map(&:subject)).to eq([ "Reminder: your library book is due soon" ])
    expect(due_soon_borrowing.reload.due_soon_reminder_sent_at).to eq(today)
    expect(due_soon_borrowing.due_today_reminder_sent_at).to be_nil
  end

  it "sends the due today email and marks it as sent" do
    described_class.perform_now(due_today_borrowing, "due_today")

    expect(ActionMailer::Base.deliveries.map(&:subject)).to eq([ "Your library book is due today" ])
    expect(due_today_borrowing.reload.due_today_reminder_sent_at).to eq(today)
    expect(due_today_borrowing.due_soon_reminder_sent_at).to be_nil
  end

  it "sends only once when run twice" do
    2.times { described_class.perform_now(due_today_borrowing, "due_today") }

    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "does nothing when the reminder was already sent" do
    due_today_borrowing.mark_reminder_sent!("due_today")

    described_class.perform_now(due_today_borrowing, "due_today")

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "does nothing when the book was returned" do
    due_today_borrowing.return!

    described_class.perform_now(due_today_borrowing, "due_today")

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "does nothing when the reader was anonymized" do
    due_today_borrowing.reader.update_columns(card_number: nil, full_name: nil, email: nil, anonymized_at: Time.current)

    described_class.perform_now(due_today_borrowing, "due_today")

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "does nothing when the borrowing is not due in the given kind" do
    described_class.perform_now(due_soon_borrowing, "due_today")

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "raises for an unknown kind" do
    expect { described_class.perform_now(due_today_borrowing, "overdue") }.to raise_error(ArgumentError)
  end

  it "retries after a transient SMTP timeout" do
    allow(ReturnReminderMailer).to receive(:with).and_raise(Net::OpenTimeout)

    described_class.perform_now(due_today_borrowing, "due_today")

    expect(described_class).to have_been_enqueued.with(due_today_borrowing, "due_today")
    expect(due_today_borrowing.reload.due_today_reminder_sent_at).to be_nil
  end

  it "does not send a due today reminder after midnight" do
    job_borrowing = due_today_borrowing

    travel_to(today + 1.day)
    described_class.perform_now(job_borrowing, "due_today")

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(job_borrowing.reload.due_today_reminder_sent_at).to be_nil
  end

  it "does not send a due soon reminder once the loan is due today" do
    job_borrowing = due_soon_borrowing

    travel_to(today + 2.days)
    described_class.perform_now(job_borrowing, "due_soon")

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(job_borrowing.reload.due_soon_reminder_sent_at).to be_nil
  end

  it "retries after a connection error" do
    allow(ReturnReminderMailer).to receive(:with).and_raise(SocketError)

    described_class.perform_now(due_today_borrowing, "due_today")

    expect(described_class).to have_been_enqueued.with(due_today_borrowing, "due_today")
  end

  it "logs the borrowing id without personal data" do
    borrowing = due_today_borrowing

    logs = with_captured_logs { described_class.perform_now(borrowing, "due_today") }

    expect(logs).to include("Sent due_today reminder for borrowing #{borrowing.id}")
    expect(logs).not_to include(borrowing.reader.email, borrowing.reader.full_name, borrowing.book.title)
  end

  it "does not log a sent reminder when nothing was sent" do
    due_today_borrowing.mark_reminder_sent!("due_today")

    logs = with_captured_logs { described_class.perform_now(due_today_borrowing, "due_today") }

    expect(logs).to include("ReturnReminderJob")
    expect(logs).not_to include("Sent due_today reminder")
  end
end
