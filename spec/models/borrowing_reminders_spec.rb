require "rails_helper"

RSpec.describe Borrowing, type: :model do
  let(:today) { Date.new(2026, 3, 10) }

  def borrowing_due_on(due_on, **attributes)
    create(:borrowing, borrowed_at: Time.zone.local(due_on.year, due_on.month, due_on.day, 12) - Borrowing::LOAN_PERIOD, **attributes)
  end

  describe ".due_soon_reminder_pending" do
    it "includes borrowings due from tomorrow up to 3 days ahead" do
      tomorrow = borrowing_due_on(today + 1)
      in_two_days = borrowing_due_on(today + 2)
      in_three_days = borrowing_due_on(today + 3)

      expect(Borrowing.due_soon_reminder_pending(today)).to contain_exactly(tomorrow, in_two_days, in_three_days)
    end

    it "excludes borrowings due in 4 days" do
      borrowing_due_on(today + 4)

      expect(Borrowing.due_soon_reminder_pending(today)).to be_empty
    end

    it "excludes borrowings due today" do
      borrowing_due_on(today)

      expect(Borrowing.due_soon_reminder_pending(today)).to be_empty
    end

    it "excludes overdue borrowings" do
      borrowing_due_on(today - 1)

      expect(Borrowing.due_soon_reminder_pending(today)).to be_empty
    end

    it "excludes returned borrowings" do
      borrowing_due_on(today + 2, returned_at: Time.zone.local(2026, 3, 9, 12))

      expect(Borrowing.due_soon_reminder_pending(today)).to be_empty
    end

    it "excludes borrowings of anonymized readers" do
      borrowing = borrowing_due_on(today + 2)
      borrowing.reader.update_columns(card_number: nil, full_name: nil, email: nil, anonymized_at: Time.current)

      expect(Borrowing.due_soon_reminder_pending(today)).to be_empty
    end

    it "excludes borrowings with a detached reader" do
      borrowing_due_on(today + 2).update_column(:reader_id, nil)

      expect(Borrowing.due_soon_reminder_pending(today)).to be_empty
    end

    it "excludes borrowings whose reminder was already sent" do
      borrowing_due_on(today + 2, due_soon_reminder_sent_at: Time.current)

      expect(Borrowing.due_soon_reminder_pending(today)).to be_empty
    end

    it "still includes borrowings whose due today reminder was sent" do
      borrowing = borrowing_due_on(today + 2, due_today_reminder_sent_at: Time.current)

      expect(Borrowing.due_soon_reminder_pending(today)).to eq([ borrowing ])
    end
  end

  describe ".due_today_reminder_pending" do
    it "includes only borrowings due today" do
      due_today = borrowing_due_on(today)
      borrowing_due_on(today + 1)
      borrowing_due_on(today - 1)

      expect(Borrowing.due_today_reminder_pending(today)).to eq([ due_today ])
    end

    it "excludes returned borrowings" do
      borrowing_due_on(today, returned_at: Time.zone.local(2026, 3, 9, 12))

      expect(Borrowing.due_today_reminder_pending(today)).to be_empty
    end

    it "excludes borrowings of anonymized readers" do
      borrowing = borrowing_due_on(today)
      borrowing.reader.update_columns(card_number: nil, full_name: nil, email: nil, anonymized_at: Time.current)

      expect(Borrowing.due_today_reminder_pending(today)).to be_empty
    end

    it "excludes borrowings with a detached reader" do
      borrowing_due_on(today).update_column(:reader_id, nil)

      expect(Borrowing.due_today_reminder_pending(today)).to be_empty
    end

    it "excludes borrowings whose reminder was already sent" do
      borrowing_due_on(today, due_today_reminder_sent_at: Time.current)

      expect(Borrowing.due_today_reminder_pending(today)).to be_empty
    end
  end

  describe "time zone" do
    it "uses the Warsaw date as today" do
      travel_to(Time.utc(2026, 3, 1, 23, 30)) do
        due_on_warsaw_today = borrowing_due_on(Date.new(2026, 3, 2))

        expect(Borrowing.due_today_reminder_pending).to eq([ due_on_warsaw_today ])
        expect(Borrowing.due_soon_reminder_pending).to be_empty
      end
    end

    it "treats the borrowing due on the following Warsaw date as due soon" do
      travel_to(Time.utc(2026, 3, 1, 23, 30)) do
        due_tomorrow = borrowing_due_on(Date.new(2026, 3, 3))

        expect(Borrowing.due_soon_reminder_pending).to eq([ due_tomorrow ])
        expect(Borrowing.due_today_reminder_pending).to be_empty
      end
    end
  end

  describe ".reminder_pending" do
    it "returns the due soon scope for the due_soon kind" do
      borrowing = borrowing_due_on(today + 2)

      expect(Borrowing.reminder_pending("due_soon", today)).to eq([ borrowing ])
    end

    it "returns the due today scope for the due_today kind" do
      borrowing = borrowing_due_on(today)

      expect(Borrowing.reminder_pending("due_today", today)).to eq([ borrowing ])
    end

    it "raises for an unknown kind" do
      expect { Borrowing.reminder_pending("overdue", today) }.to raise_error(ArgumentError, /unknown reminder kind/)
    end
  end

  describe "#reminder_pending?" do
    it "is true for a borrowing due soon" do
      travel_to(Time.zone.local(2026, 3, 10, 8)) do
        expect(borrowing_due_on(today + 2).reminder_pending?("due_soon")).to be(true)
      end
    end

    it "is true for a borrowing due today" do
      travel_to(Time.zone.local(2026, 3, 10, 8)) do
        expect(borrowing_due_on(today).reminder_pending?("due_today")).to be(true)
      end
    end

    it "is false for the other kind" do
      travel_to(Time.zone.local(2026, 3, 10, 8)) do
        borrowing = borrowing_due_on(today + 2)

        expect(borrowing.reminder_pending?("due_today")).to be(false)
      end
    end

    it "is false after the reminder was marked as sent" do
      travel_to(Time.zone.local(2026, 3, 10, 8)) do
        borrowing = borrowing_due_on(today)
        borrowing.mark_reminder_sent!("due_today")

        expect(borrowing.reminder_pending?("due_today")).to be(false)
      end
    end

    it "raises for an unknown kind" do
      expect { create(:borrowing).reminder_pending?("overdue") }.to raise_error(ArgumentError)
    end
  end

  describe "#mark_reminder_sent!" do
    it "stores the time of the due soon reminder" do
      borrowing = create(:borrowing)

      travel_to(Time.zone.local(2026, 3, 10, 8)) { borrowing.mark_reminder_sent!("due_soon") }

      expect(borrowing.reload.due_soon_reminder_sent_at).to eq(Time.zone.local(2026, 3, 10, 8))
    end

    it "leaves the due today reminder untouched when marking due soon" do
      borrowing = create(:borrowing)

      borrowing.mark_reminder_sent!("due_soon")

      expect(borrowing.reload.due_today_reminder_sent_at).to be_nil
    end

    it "stores the time of the due today reminder" do
      borrowing = create(:borrowing)

      travel_to(Time.zone.local(2026, 3, 10, 8)) { borrowing.mark_reminder_sent!("due_today") }

      expect(borrowing.reload.due_today_reminder_sent_at).to eq(Time.zone.local(2026, 3, 10, 8))
    end

    it "leaves the due soon reminder untouched when marking due today" do
      borrowing = create(:borrowing)

      borrowing.mark_reminder_sent!("due_today")

      expect(borrowing.reload.due_soon_reminder_sent_at).to be_nil
    end

    it "raises for an unknown kind" do
      expect { create(:borrowing).mark_reminder_sent!("overdue") }.to raise_error(ArgumentError)
    end
  end
end
