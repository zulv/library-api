require "rails_helper"

RSpec.describe ReturnReminderMailer, type: :mailer do
  let(:book) { create(:book, title: "Solaris", author: "Stanisław Lem") }
  let(:reader) { create(:reader, full_name: "Zażółć Gęślą", email: "zazolc@example.com") }
  let(:borrowing) { create(:borrowing, book:, reader:, borrowed_at: Time.zone.local(2026, 3, 1, 12)) }

  shared_examples "a reminder with the loan details" do
    it "is sent to the reader from the library address" do
      expect(mail.to).to eq([ "zazolc@example.com" ])
      expect(mail.from).to eq([ ENV.fetch("LIBRARY_EMAIL_FROM", "library@example.com") ])
    end

    it "does not put the book title in the subject" do
      expect(mail.subject).not_to include("Solaris")
    end

    %w[text_part html_part].each do |part|
      it "describes the loan in the #{part}" do
        body = mail.public_send(part).body.decoded

        expect(body).to include("Zażółć Gęślą", "Solaris", "Stanisław Lem", "March 31, 2026")
      end

      it "does not expose internal ids in the #{part}" do
        body = mail.public_send(part).body.decoded

        expect(body).not_to include(borrowing.id, book.id, reader.id)
      end
    end
  end

  describe "#due_soon" do
    let(:mail) { described_class.with(borrowing:).due_soon }

    it "has a generic subject" do
      expect(mail.subject).to eq("Reminder: your library book is due soon")
    end

    it_behaves_like "a reminder with the loan details"
  end

  describe "#due_today" do
    let(:mail) { described_class.with(borrowing:).due_today }

    it "has a generic subject" do
      expect(mail.subject).to eq("Your library book is due today")
    end

    it_behaves_like "a reminder with the loan details"

    it "says the book is due today" do
      expect(mail.text_part.body.decoded).to include("due today")
    end
  end
end
