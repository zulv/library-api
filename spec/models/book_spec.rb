require "rails_helper"

RSpec.describe Book, type: :model do
  describe "validations" do
    subject { build(:book) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:serial_number) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:author) }

    it "reports only a blank error for a blank serial number" do
      book = build(:book, serial_number: "")
      book.validate

      expect(book.errors[:serial_number]).to eq([ "can't be blank" ])
    end

    it "accepts a serial number with leading zeros" do
      expect(build(:book, serial_number: "012345")).to be_valid
    end

    it "rejects a serial number that is too short" do
      expect(build(:book, serial_number: "12345")).not_to be_valid
    end

    it "rejects a serial number that is too long" do
      expect(build(:book, serial_number: "1234567")).not_to be_valid
    end

    it "rejects a serial number with letters" do
      expect(build(:book, serial_number: "12a456")).not_to be_valid
    end

    it "rejects a serial number with an embedded non-digit" do
      expect(build(:book, serial_number: "123 56")).not_to be_valid
    end

    it "rejects a duplicated serial number" do
      create(:book, serial_number: "123456")

      expect(build(:book, serial_number: "123456")).not_to be_valid
    end

    it "rejects a serial number belonging to a discarded book" do
      create(:book, serial_number: "123456").discard!

      expect(build(:book, serial_number: "123456")).not_to be_valid
    end
  end

  describe "normalization" do
    it "strips whitespace around title and author" do
      book = build(:book, title: "  Dune ", author: " Frank Herbert  ")

      expect([ book.title, book.author ]).to eq([ "Dune", "Frank Herbert" ])
    end

    it "strips whitespace around serial number" do
      expect(build(:book, serial_number: " 100001\n").serial_number).to eq("100001")
    end

    it "rejects a whitespace-only title" do
      expect(build(:book, title: "   ")).not_to be_valid
    end

    it "keeps unicode characters intact" do
      book = build(:book, title: " Zażółć gęślą jaźń ")

      expect(book.title).to eq("Zażółć gęślą jaźń")
    end
  end

  describe ".with_serial_number" do
    let!(:matching) { create(:book, serial_number: "111111") }
    let!(:other) { create(:book, serial_number: "222222") }

    it "returns only the book with that serial number" do
      expect(Book.with_serial_number("111111")).to contain_exactly(matching)
    end

    it "returns nothing for an unknown serial number" do
      expect(Book.with_serial_number("999999")).to be_empty
    end

    it "returns all books for a blank serial number" do
      expect(Book.with_serial_number("")).to contain_exactly(matching, other)
    end

    it "returns all books for a nil serial number" do
      expect(Book.with_serial_number(nil)).to contain_exactly(matching, other)
    end
  end

  describe "borrowing state" do
    let(:book) { create(:book) }

    it "is available without borrowings" do
      expect(book.status).to eq("available")
      expect(book).not_to be_borrowed
      expect(book.due_on).to be_nil
    end

    it "is borrowed with an active borrowing" do
      borrowing = create(:borrowing, book:)

      expect(book.reload.status).to eq("borrowed")
      expect(book).to be_borrowed
      expect(book.due_on).to eq(borrowing.due_on)
    end

    it "is available again when the only borrowing was returned" do
      create(:borrowing, :returned, book:)

      expect(book.reload.status).to eq("available")
      expect(book.due_on).to be_nil
    end
  end

  describe "#borrow_by!" do
    let(:book) { create(:book) }
    let(:reader) { create(:reader) }

    it "creates an active borrowing for the reader" do
      borrowing = book.borrow_by!(reader)

      expect(borrowing).to be_persisted
      expect(borrowing.reader).to eq(reader)
      expect(borrowing.book).to eq(book)
      expect(borrowing.returned_at).to be_nil
    end

    it "sets the due date 30 days ahead" do
      borrowing = book.borrow_by!(reader)

      expect(borrowing.due_on).to eq(Date.current + 30.days)
    end

    it "raises when the book is already borrowed" do
      book.borrow_by!(reader)

      expect { book.borrow_by!(create(:reader)) }.to raise_error(Book::AlreadyBorrowed, "book is already borrowed")
    end

    it "does not create a second borrowing when the book is already borrowed" do
      book.borrow_by!(reader)

      expect { book.borrow_by!(create(:reader)) }.to raise_error(Book::AlreadyBorrowed)
      expect(book.borrowings.count).to eq(1)
    end

    it "allows borrowing again after a return" do
      book.borrow_by!(reader)
      book.return!

      expect { book.borrow_by!(create(:reader)) }.not_to raise_error
    end

    it "allows one reader to borrow several books" do
      book.borrow_by!(reader)

      expect { create(:book).borrow_by!(reader) }.not_to raise_error
    end

    it "raises not found for an anonymized reader" do
      anonymized = create(:reader, :anonymized)

      expect { book.borrow_by!(anonymized) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(book.borrowings).to be_empty
    end

    it "raises not found when the book was discarded behind its back" do
      stale_book = Book.find(book.id)
      Book.where(id: book.id).update_all(discarded_at: Time.current)

      expect { stale_book.borrow_by!(reader) }.to raise_error(ActiveRecord::RecordNotFound) { |error| expect(error.model).to eq("Book") }
      expect(Borrowing.count).to eq(0)
    end

    it "raises not found when the reader was anonymized behind its back" do
      stale_reader = Reader.find(reader.id)
      Reader.where(id: reader.id).update_all(card_number: nil, full_name: nil, email: nil, anonymized_at: Time.current)

      expect { book.borrow_by!(stale_reader) }.to raise_error(ActiveRecord::RecordNotFound) { |error| expect(error.model).to eq("Reader") }
      expect(Borrowing.count).to eq(0)
    end
  end

  describe "#return!" do
    let(:book) { create(:book) }

    it "marks the active borrowing as returned" do
      borrowing = book.borrow_by!(create(:reader))

      returned = book.return!

      expect(returned).to eq(borrowing)
      expect(returned).to be_returned
      expect(borrowing.reload.returned_at).to be_present
    end

    it "raises when there is nothing to return" do
      expect { book.return! }.to raise_error(Book::NotBorrowed)
    end

    it "raises when the last borrowing was already returned" do
      create(:borrowing, :returned, book:)

      expect { book.return! }.to raise_error(Book::NotBorrowed)
    end
  end

  describe "#discard" do
    let(:book) { create(:book) }

    it "refuses to discard a borrowed book" do
      create(:borrowing, book:)

      expect { book.discard }.to raise_error(Book::CannotDiscardBorrowed, "book is borrowed and can't be removed")
      expect(book.reload).not_to be_discarded
    end

    it "refuses to discard! a borrowed book" do
      create(:borrowing, book:)

      expect { book.discard! }.to raise_error(Book::CannotDiscardBorrowed)
      expect(book.reload).not_to be_discarded
    end

    it "discards a book after it was returned" do
      book.borrow_by!(create(:reader))
      book.return!

      book.discard!

      expect(book.reload).to be_discarded
    end

    it "raises when the book was already discarded behind its back" do
      stale_book = Book.find(book.id)
      Book.where(id: book.id).update_all(discarded_at: Time.current)

      expect { stale_book.discard! }.to raise_error(Discard::RecordNotDiscarded)
    end

    it "discards a book that was never borrowed" do
      expect(book.discard).to be(true)
    end
  end

  describe "#borrowing_history" do
    let(:book) { create(:book) }

    it "lists borrowings newest first" do
      oldest = create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 1, 1, 12))
      newest = create(:borrowing, book:, borrowed_at: Time.zone.local(2026, 3, 1, 12))
      middle = create(:borrowing, :returned, book:, borrowed_at: Time.zone.local(2026, 2, 1, 12))

      expect(book.borrowing_history).to eq([ newest, middle, oldest ])
    end

    it "is empty for a book that was never borrowed" do
      expect(book.borrowing_history).to be_empty
    end
  end

  describe "database constraints" do
    it "rejects an invalid serial number even when validations are bypassed" do
      book = create(:book)

      expect { book.update_column(:serial_number, "abc") }.to raise_error(ActiveRecord::StatementInvalid, /books_serial_number_format/)
    end

    it "rejects a duplicated serial number even when validations are bypassed" do
      create(:book, serial_number: "123456")
      book = build(:book, serial_number: "123456")

      expect { book.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
