require "rails_helper"
require "fugit"

RSpec.describe "Recurring schedule" do
  let(:warsaw) { Time.find_zone("Europe/Warsaw") }
  let(:options) { Rails.application.config_for(:recurring, env: "production").fetch(:send_return_reminders) }
  let(:schedule) { Fugit.parse("#{options.fetch(:schedule)} #{SolidQueue.time_zone}") }

  it "runs the return reminders sweep" do
    expect(options.fetch(:class)).to eq("SendReturnRemindersJob")
  end

  it "runs at 8 in the morning Warsaw time" do
    next_run = schedule.next_time(Time.utc(2026, 3, 1, 12)).to_t

    expect(next_run.in_time_zone(warsaw)).to eq(warsaw.local(2026, 3, 2, 8))
  end

  it "keeps 8 in the morning across the daylight saving change" do
    next_run = schedule.next_time(Time.utc(2026, 3, 28, 12)).to_t

    expect(next_run.in_time_zone(warsaw)).to eq(warsaw.local(2026, 3, 29, 8))
  end
end
