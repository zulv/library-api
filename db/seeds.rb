if Rails.env.development?
  User.find_or_create_by!(email_address: "librarian@example.com") do |user|
    user.password = "password"
  end
end
