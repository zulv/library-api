FactoryBot.define do
  factory :reader do
    sequence(:card_number) { |n| format("%06d", n) }
    full_name { Faker::Name.name }
    sequence(:email) { |n| "reader#{n}@example.com" }

    trait :anonymized do
      card_number { nil }
      full_name { nil }
      email { nil }
      anonymized_at { Time.zone.local(2026, 1, 1, 12) }
    end
  end
end
