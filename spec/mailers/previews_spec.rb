require "rails_helper"
require Rails.root.join("spec/mailers/previews/return_reminder_mailer_preview")

RSpec.describe ReturnReminderMailerPreview do
  it "builds the due soon email" do
    mail = described_class.new.due_soon.message

    expect(mail).to be_a(Mail::Message)
    expect(mail.subject).to eq("Reminder: your library book is due soon")
  end

  it "builds the due today email" do
    mail = described_class.new.due_today.message

    expect(mail).to be_a(Mail::Message)
    expect(mail.subject).to eq("Your library book is due today")
  end
end
