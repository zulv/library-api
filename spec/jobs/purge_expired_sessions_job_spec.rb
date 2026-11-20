require "rails_helper"

RSpec.describe PurgeExpiredSessionsJob, type: :job do
  let(:now) { Time.zone.local(2026, 3, 10, 3, 15) }

  around { |example| travel_to(now) { example.run } }

  it "purges expired sessions and logs the count" do
    create(:session, created_at: 2.days.ago)
    fresh = create(:session)

    logs = with_captured_logs { described_class.perform_now }

    expect(Session.all).to eq([ fresh ])
    expect(logs).to include("Purged 1 expired sessions")
  end

  it "purges nothing when it runs again" do
    create(:session, created_at: 2.days.ago)
    described_class.perform_now

    logs = with_captured_logs { described_class.perform_now }

    expect(logs).to include("Purged 0 expired sessions")
  end
end
