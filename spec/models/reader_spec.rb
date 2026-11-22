require "rails_helper"

RSpec.describe Reader, type: :model do
  def raw_value(reader, column)
    Reader.connection.select_value(Reader.sanitize_sql([ "SELECT #{column} FROM readers WHERE id = ?", reader.id ]))
  end

  describe "validations" do
    subject { build(:reader) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:card_number) }
    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_presence_of(:email) }

    it "reports only a blank error for a blank card number" do
      reader = build(:reader, card_number: "")
      reader.validate

      expect(reader.errors[:card_number]).to eq([ "can't be blank" ])
    end

    it "reports only a blank error for a blank email" do
      reader = build(:reader, email: "")
      reader.validate

      expect(reader.errors[:email]).to eq([ "can't be blank" ])
    end

    it "accepts a card number with leading zeros" do
      expect(build(:reader, card_number: "012345")).to be_valid
    end

    it "rejects a card number that is too short" do
      expect(build(:reader, card_number: "12345")).not_to be_valid
    end

    it "explains the expected card number format" do
      reader = build(:reader, card_number: "12345")

      reader.validate

      expect(reader.errors[:card_number]).to eq([ "must be 6 digits" ])
    end

    it "rejects a card number that is too long" do
      expect(build(:reader, card_number: "1234567")).not_to be_valid
    end

    it "rejects a card number with letters" do
      expect(build(:reader, card_number: "12a456")).not_to be_valid
    end

    it "rejects a duplicated card number" do
      create(:reader, card_number: "123456")

      expect(build(:reader, card_number: "123456")).not_to be_valid
    end

    it "rejects a malformed email" do
      expect(build(:reader, email: "not-an-email")).not_to be_valid
    end

    it "rejects a duplicated email" do
      create(:reader, email: "ann@example.com")

      expect(build(:reader, email: "ann@example.com")).not_to be_valid
    end

    it "rejects a duplicated email in a different case" do
      create(:reader, email: "ann@example.com")

      expect(build(:reader, email: "ANN@Example.com")).not_to be_valid
    end

    it { is_expected.to validate_length_of(:email).is_at_most(254) }

    it "accepts a full name of 255 characters" do
      expect(build(:reader, full_name: "a" * 255)).to be_valid
    end

    it "rejects a full name longer than 255 characters" do
      expect(build(:reader, full_name: "a" * 256)).not_to be_valid
    end

    it "accepts unicode in the full name" do
      expect(build(:reader, full_name: "Zażółć Gęślą")).to be_valid
    end
  end

  describe "normalization" do
    it "strips whitespace from card number and full name" do
      reader = build(:reader, card_number: " 123456 ", full_name: "  Ann Smith ")

      expect([ reader.card_number, reader.full_name ]).to eq([ "123456", "Ann Smith" ])
    end

    it "strips and downcases the email" do
      reader = build(:reader, email: "  Ann@Example.COM ")

      expect(reader.email).to eq("ann@example.com")
    end
  end

  describe "scopes" do
    describe ".identified" do
      it "excludes anonymized readers" do
        identified = create(:reader)
        create(:reader, :anonymized)

        expect(Reader.identified).to eq([ identified ])
      end
    end

    describe ".with_card_number" do
      it "returns the reader with the given card number" do
        wanted = create(:reader, card_number: "111111")
        create(:reader, card_number: "222222")

        expect(Reader.with_card_number("111111")).to eq([ wanted ])
      end

      it "ignores spaces around the card number" do
        wanted = create(:reader, card_number: "111111")
        create(:reader, card_number: "222222")

        expect(Reader.with_card_number(" 111111 ")).to eq([ wanted ])
      end

      it "returns nothing for an unknown card number" do
        create(:reader, card_number: "111111")

        expect(Reader.with_card_number("999999")).to be_empty
      end

      it "returns all readers for a blank card number" do
        create_list(:reader, 2)

        expect(Reader.with_card_number("").count).to eq(2)
      end

      it "returns all readers for a nil card number" do
        create_list(:reader, 2)

        expect(Reader.with_card_number(nil).count).to eq(2)
      end
    end
  end

  describe "#anonymize!" do
    it "clears personal data" do
      reader = create(:reader)

      reader.anonymize!

      expect(reader.reload.attributes.values_at("card_number", "full_name", "email")).to eq([ nil, nil, nil ])
    end

    it "sets the anonymization time" do
      reader = create(:reader)

      travel_to(Time.zone.local(2026, 5, 1, 10)) { reader.anonymize! }

      expect(reader.reload.anonymized_at).to eq(Time.zone.local(2026, 5, 1, 10))
    end

    it "marks the reader as anonymized" do
      reader = create(:reader)

      reader.anonymize!

      expect(reader).to be_anonymized
    end

    it "keeps the row" do
      reader = create(:reader)

      reader.anonymize!

      expect(Reader.exists?(reader.id)).to be(true)
    end

    it "does not change the timestamp when called twice" do
      reader = create(:reader)
      travel_to(Time.zone.local(2026, 5, 1, 10)) { reader.anonymize! }

      travel_to(Time.zone.local(2026, 6, 1, 10)) { reader.anonymize! }

      expect(reader.reload.anonymized_at).to eq(Time.zone.local(2026, 5, 1, 10))
    end

    it "frees the card number and email for a new reader" do
      reader = create(:reader, card_number: "123456", email: "ann@example.com")
      reader.anonymize!

      expect(build(:reader, card_number: "123456", email: "ann@example.com")).to be_valid
    end
  end

  describe "#anonymize! with borrowings" do
    let(:reader) { create(:reader) }

    it "raises when the reader has an active borrowing" do
      create(:borrowing, reader:)

      expect { reader.anonymize! }.to raise_error(Reader::HasActiveBorrowing, "reader has a borrowed book")
    end

    it "keeps personal data when the reader has an active borrowing" do
      create(:borrowing, reader:)

      expect { reader.anonymize! }.to raise_error(Reader::HasActiveBorrowing)
      expect(reader.reload).not_to be_anonymized
      expect(reader.email).to be_present
    end

    it "anonymizes after the book was returned" do
      create(:borrowing, :returned, reader:)

      reader.anonymize!

      expect(reader.reload).to be_anonymized
    end

    it "anonymizes after returning through the book" do
      book = create(:book)
      book.borrow_by!(reader)
      book.return!

      reader.anonymize!

      expect(reader.reload).to be_anonymized
    end

    it "keeps borrowings after anonymization" do
      borrowing = create(:borrowing, :returned, reader:)

      reader.anonymize!

      expect(Borrowing.find(borrowing.id).reader_id).to eq(reader.id)
      expect(reader.borrowings.count).to eq(1)
    end

    it "is still idempotent for an anonymized reader" do
      create(:borrowing, :returned, reader:)
      reader.anonymize!

      expect { reader.anonymize! }.not_to raise_error
    end
  end

  describe "anonymized readers" do
    it "skips validations" do
      expect(build(:reader, :anonymized)).to be_valid
    end

    it "allows several anonymized readers" do
      create(:reader, :anonymized)

      expect(build(:reader, :anonymized)).to be_valid
    end
  end

  describe "encryption" do
    it "stores the email encrypted" do
      reader = create(:reader, email: "ann@example.com")

      payload = JSON.parse(raw_value(reader, "email"))

      expect(payload).to include("p")
      expect(raw_value(reader, "email")).not_to include("ann@example.com")
    end

    it "stores the full name encrypted" do
      reader = create(:reader, full_name: "Ann Smith")

      payload = JSON.parse(raw_value(reader, "full_name"))

      expect(payload).to include("p")
      expect(raw_value(reader, "full_name")).not_to include("Ann Smith")
    end

    it "reads the encrypted values back" do
      reader = create(:reader, full_name: "Ann Smith", email: "ann@example.com")

      expect(Reader.find(reader.id).attributes.values_at("full_name", "email")).to eq([ "Ann Smith", "ann@example.com" ])
    end

    it "finds a reader by email in a different case" do
      reader = create(:reader, email: "ann@example.com")

      expect(Reader.find_by(email: "ANN@example.com")).to eq(reader)
    end
  end

  describe "database constraints" do
    it "rejects missing personal data without anonymization" do
      reader = build(:reader, full_name: nil)

      expect { reader.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /readers_identity_present_unless_anonymized/)
    end

    it "rejects a malformed card number" do
      reader = build(:reader, card_number: "12ab56")

      expect { reader.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /readers_card_number_format/)
    end

    it "rejects a duplicated card number" do
      create(:reader, card_number: "123456")
      reader = build(:reader, card_number: "123456")

      expect { reader.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a duplicated email in a different case" do
      create(:reader, email: "ann@example.com")
      reader = build(:reader, email: "ANN@Example.com")

      expect { reader.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
