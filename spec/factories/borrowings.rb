FactoryBot.define do
  factory :borrowing do
    book
    reader

    trait :returned do
      borrowed_at { 10.days.ago }
      returned_at { borrowed_at + 1.day }
    end
  end
end
