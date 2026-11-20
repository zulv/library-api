require "rails_helper"

RSpec.describe Borrowing, type: :model do
  let(:now) { Time.zone.local(2026, 3, 10, 12) }

  around { |example| travel_to(now) { example.run } }

  def returned_borrowing(returned_at, **attributes)
    create(:borrowing, borrowed_at: returned_at - 5.days, returned_at:, **attributes)
  end

  describe ".past_retention" do
    it "includes borrowings returned more than the retention period ago" do
      old = returned_borrowing(Borrowing::RETENTION_PERIOD.ago - 1.day)

      expect(Borrowing.past_retention).to eq([ old ])
    end

    it "includes borrowings returned one second past the retention period" do
      old = returned_borrowing(Borrowing::RETENTION_PERIOD.ago - 1.second)

      expect(Borrowing.past_retention).to eq([ old ])
    end

    it "excludes borrowings returned exactly at the retention period" do
      returned_borrowing(Borrowing::RETENTION_PERIOD.ago)

      expect(Borrowing.past_retention).to be_empty
    end

    it "excludes borrowings returned within the retention period" do
      returned_borrowing(Borrowing::RETENTION_PERIOD.ago + 1.day)

      expect(Borrowing.past_retention).to be_empty
    end

    it "excludes active borrowings however old" do
      create(:borrowing, borrowed_at: 3.years.ago)

      expect(Borrowing.past_retention).to be_empty
    end

    it "excludes borrowings that already have no reader" do
      returned_borrowing(3.years.ago).update_column(:reader_id, nil)

      expect(Borrowing.past_retention).to be_empty
    end
  end

  describe ".anonymize_past_retention" do
    it "detaches only borrowings past retention and returns their count" do
      old = returned_borrowing(3.years.ago)
      recent = returned_borrowing(1.month.ago)
      active = create(:borrowing, borrowed_at: 3.years.ago)
      already_anonymized = returned_borrowing(3.years.ago).tap { |borrowing| borrowing.update_column(:reader_id, nil) }

      count = Borrowing.anonymize_past_retention

      expect(count).to eq(1)
      expect(old.reload.reader_id).to be_nil
      expect(recent.reload.reader_id).not_to be_nil
      expect(active.reload.reader_id).not_to be_nil
      expect(already_anonymized.reload.updated_at).to eq(already_anonymized.updated_at)
    end

    it "touches updated_at" do
      borrowing = returned_borrowing(3.years.ago)

      travel 1.day
      Borrowing.anonymize_past_retention

      expect(borrowing.reload.updated_at).to eq(now + 1.day)
    end

    it "keeps the row and its other columns" do
      borrowing = returned_borrowing(3.years.ago)
      expected = borrowing.attributes.except("reader_id", "updated_at")

      Borrowing.anonymize_past_retention

      expect(borrowing.reload.attributes.except("reader_id", "updated_at")).to eq(expected)
    end

    it "returns 0 when there is nothing to anonymize" do
      expect(Borrowing.anonymize_past_retention).to eq(0)
    end
  end
end
