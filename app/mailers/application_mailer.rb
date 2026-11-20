class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("LIBRARY_EMAIL_FROM", "library@example.com")
  layout "mailer"
end
