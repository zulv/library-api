require "rails_helper"

RSpec.describe AnonymizeOldBorrowingsJob, type: :job do
  let(:now) { Time.zone.local(2026, 3, 10, 3) }

  around { |example| travel_to(now) { example.run } }

  def returned_borrowing(returned_at, **attributes)
    create(:borrowing, borrowed_at: returned_at - 5.days, returned_at:, **attributes)
  end

  it "anonymizes old borrowings and logs the count" do
    old = returned_borrowing(3.years.ago)
    recent = returned_borrowing(1.month.ago)

    logs = with_captured_logs { described_class.perform_now }

    expect(old.reload.reader_id).to be_nil
    expect(recent.reload.reader_id).not_to be_nil
    expect(logs).to include("Anonymized 1 borrowings past retention")
  end

  it "anonymizes nothing when it runs again" do
    returned_borrowing(3.years.ago)
    described_class.perform_now

    logs = with_captured_logs { described_class.perform_now }

    expect(logs).to include("Anonymized 0 borrowings past retention")
  end

  it "logs without reader personal data" do
    reader = create(:reader, card_number: "987654", full_name: "Zofia Nowak", email: "zofia@example.com")
    returned_borrowing(3.years.ago, reader:)

    logs = with_captured_logs { described_class.perform_now }

    expect(logs).not_to include("987654", "Zofia", "zofia@example.com")
  end
end
