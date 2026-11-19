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
