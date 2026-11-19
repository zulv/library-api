require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    subject { build(:user) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:email_address) }
    it { is_expected.to validate_presence_of(:password) }

    it "rejects a malformed email address" do
      user = build(:user, email_address: "not-an-email")

      expect(user).not_to be_valid
    end

    it "rejects a duplicated email address" do
      create(:user, email_address: "taken@example.com")
      user = build(:user, email_address: "taken@example.com")

      expect(user).not_to be_valid
    end

    it "rejects a duplicated email address with different case and whitespace" do
      create(:user, email_address: "taken@example.com")
      user = build(:user, email_address: "  TAKEN@Example.com ")

      expect(user).not_to be_valid
    end
  end

  describe "normalization" do
    it "strips whitespace and downcases the email address" do
      user = build(:user, email_address: "  John@Example.COM  ")

      expect(user.email_address).to eq("john@example.com")
    end
  end

  describe "password" do
    it "is verified by authenticate" do
      user = create(:user, password: "password123")

      expect(user.authenticate("password123")).to eq(user)
    end

    it "is rejected by authenticate when wrong" do
      user = create(:user, password: "password123")

      expect(user.authenticate("wrong")).to be(false)
    end
  end

  describe "sessions" do
    it "destroys sessions together with the user" do
      user = create(:user)
      create_list(:session, 2, user: user)

      expect { user.destroy }.to change(Session, :count).by(-2)
    end
  end
end
