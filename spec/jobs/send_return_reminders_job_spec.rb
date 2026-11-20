require "rails_helper"

RSpec.describe SendReturnRemindersJob, type: :job do
  include ActiveJob::TestHelper

  let(:today) { Time.zone.local(2026, 3, 10, 8) }

  def borrowing_due_in(days, **attributes)
    create(:borrowing, borrowed_at: today + days.days - Borrowing::LOAN_PERIOD, **attributes)
  end

  before { ActionMailer::Base.deliveries.clear }

  around { |example| travel_to(today) { example.run } }

  it "enqueues a reminder for each pending borrowing and kind" do
    due_in_three_days = borrowing_due_in(3)
    due_today = borrowing_due_in(0)

    described_class.perform_now

    expect(ReturnReminderJob).to have_been_enqueued.with(due_in_three_days, "due_soon")
    expect(ReturnReminderJob).to have_been_enqueued.with(due_today, "due_today")
    expect(enqueued_jobs.size).to eq(2)
  end

  it "enqueues nothing for borrowings that are not pending" do
    borrowing_due_in(4)
    borrowing_due_in(-1)
    borrowing_due_in(2, returned_at: today - 1.hour)
    borrowing_due_in(0, due_today_reminder_sent_at: today)
    borrowing_due_in(1).reader.update_columns(card_number: nil, full_name: nil, email: nil, anonymized_at: today)

    described_class.perform_now

    expect(enqueued_jobs).to be_empty
  end

  it "delivers the emails end to end" do
    borrowing_due_in(3)
    borrowing_due_in(0)

    perform_enqueued_jobs { described_class.perform_now }

    expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly(
      "Reminder: your library book is due soon",
      "Your library book is due today"
    )
  end

  it "delivers nothing new when the sweep runs again" do
    borrowing_due_in(3)
    borrowing_due_in(0)
    perform_enqueued_jobs { described_class.perform_now }

    expect { perform_enqueued_jobs { described_class.perform_now } }.not_to change { ActionMailer::Base.deliveries.size }
  end
end
