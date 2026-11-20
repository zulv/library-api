require "rails_helper"

RSpec.describe Session, type: :model do
  let(:now) { Time.zone.local(2026, 3, 10, 12) }

  around { |example| travel_to(now) { example.run } }

  describe ".expired" do
    it "includes sessions older than the lifetime" do
      expired = create(:session, created_at: Session::LIFETIME.ago - 1.minute)

      expect(Session.expired).to eq([ expired ])
    end

    it "includes sessions one second past the lifetime" do
      expired = create(:session, created_at: Session::LIFETIME.ago - 1.second)

      expect(Session.expired).to eq([ expired ])
    end

    it "excludes sessions exactly at the lifetime" do
      create(:session, created_at: Session::LIFETIME.ago)

      expect(Session.expired).to be_empty
    end

    it "excludes sessions younger than the lifetime" do
      create(:session, created_at: Session::LIFETIME.ago + 1.minute)

      expect(Session.expired).to be_empty
    end
  end

  describe ".purge_expired" do
    it "deletes only expired sessions" do
      create(:session, created_at: Session::LIFETIME.ago - 1.minute)
      fresh = create(:session, created_at: Session::LIFETIME.ago + 1.minute)

      Session.purge_expired

      expect(Session.all).to eq([ fresh ])
    end

    it "returns the number of deleted sessions" do
      2.times { create(:session, created_at: 2.days.ago) }
      create(:session)

      expect(Session.purge_expired).to eq(2)
    end

    it "returns 0 when nothing expired" do
      create(:session)

      expect(Session.purge_expired).to eq(0)
    end
  end
end
