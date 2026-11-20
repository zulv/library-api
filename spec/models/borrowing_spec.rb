require "rails_helper"

RSpec.describe Borrowing, type: :model do
  describe "creating" do
    it "sets the due date 30 days after borrowing" do
      borrowing = create(:borrowing, borrowed_at: Time.zone.local(2026, 3, 1, 12))

      expect(borrowing.due_on).to eq(Date.new(2026, 3, 31))
    end

    it "borrows at the current time by default" do
      travel_to(Time.zone.local(2026, 3, 1, 12)) do
        borrowing = create(:borrowing)

        expect(borrowing.borrowed_at).to eq(Time.zone.local(2026, 3, 1, 12))
      end
    end

    it "counts the due date from the Warsaw date and not the UTC date" do
      travel_to(Time.utc(2026, 3, 1, 23, 30)) do
        borrowing = create(:borrowing)

        expect(borrowing.due_on).to eq(Date.current + 30.days)
        expect(borrowing.due_on).to eq(Date.new(2026, 4, 1))
      end
    end

    it "requires a reader" do
      borrowing = build(:borrowing, reader: nil)

      expect(borrowing).not_to be_valid
      expect(borrowing.errors[:reader]).to eq([ "can't be blank" ])
    end

    it "rejects an anonymized reader" do
      borrowing = build(:borrowing, reader: create(:reader, :anonymized))

      expect(borrowing).not_to be_valid
      expect(borrowing.errors[:reader]).to eq([ "is anonymized" ])
    end

    it "keeps a borrowing valid after its reader is anonymized" do
      borrowing = create(:borrowing)

      borrowing.reader.update_columns(card_number: nil, full_name: nil, email: nil, anonymized_at: Time.current)

      expect(borrowing.reload).to be_valid
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns only borrowings that were not returned" do
        active = create(:borrowing)
        create(:borrowing, :returned)

        expect(Borrowing.active).to eq([ active ])
      end
    end

    describe ".newest_first" do
      it "orders by borrowing time descending" do
        oldest = create(:borrowing, :returned, borrowed_at: Time.zone.local(2026, 1, 1, 12))
        newest = create(:borrowing, :returned, borrowed_at: Time.zone.local(2026, 3, 1, 12))
        middle = create(:borrowing, :returned, borrowed_at: Time.zone.local(2026, 2, 1, 12))

        expect(Borrowing.newest_first).to eq([ newest, middle, oldest ])
      end

      it "breaks ties by id descending" do
        borrowed_at = Time.zone.local(2026, 1, 1, 12)
        borrowings = create_list(:borrowing, 3, :returned, borrowed_at:)

        expect(Borrowing.newest_first).to eq(borrowings.sort_by(&:id).reverse)
      end
    end
  end

  describe "#return!" do
    it "sets the return time" do
      borrowing = create(:borrowing)

      travel_to(Time.current + 2.days) do
        borrowing.return!

        expect(borrowing.reload.returned_at).to eq(Time.current)
      end
    end

    it "marks the borrowing as returned" do
      borrowing = create(:borrowing)

      borrowing.return!

      expect(borrowing).to be_returned
    end

    it "removes the borrowing from the active scope" do
      borrowing = create(:borrowing)

      borrowing.return!

      expect(Borrowing.active).to be_empty
    end
  end

  describe "#identified_reader" do
    it "returns the reader" do
      borrowing = create(:borrowing)

      expect(borrowing.identified_reader).to eq(borrowing.reader)
    end

    it "returns nil for an anonymized reader" do
      borrowing = create(:borrowing, :returned)
      borrowing.reader.anonymize!

      expect(borrowing.reload.identified_reader).to be_nil
    end

    it "returns nil when the reader is detached" do
      borrowing = create(:borrowing, :returned)
      borrowing.update_column(:reader_id, nil)

      expect(borrowing.reload.identified_reader).to be_nil
    end
  end

  describe "database constraints" do
    it "rejects a second active borrowing of the same book" do
      book = create(:book)
      create(:borrowing, book:)
      duplicate = build(:borrowing, book:)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new borrowing after the previous one was returned" do
      book = create(:book)
      create(:borrowing, :returned, book:)

      expect { create(:borrowing, book:) }.not_to raise_error
    end

    it "rejects a return before the borrowing" do
      borrowing = build(:borrowing, borrowed_at: Time.zone.local(2026, 3, 1, 12), returned_at: Time.zone.local(2026, 2, 1, 12))

      expect { borrowing.save! }.to raise_error(ActiveRecord::StatementInvalid, /borrowings_returned_after_borrowed/)
    end

    it "rejects deleting a book that has borrowings" do
      borrowing = create(:borrowing, :returned)

      expect { borrowing.book.delete }.to raise_error(ActiveRecord::StatementInvalid, /RestrictViolation/)
    end

    it "rejects deleting a reader that has borrowings" do
      borrowing = create(:borrowing, :returned)

      expect { borrowing.reader.delete }.to raise_error(ActiveRecord::StatementInvalid, /RestrictViolation/)
    end
  end
end
