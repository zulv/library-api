require "swagger_helper"

RSpec.describe "Sessions", type: :request do
  let!(:user) { create(:user, email_address: "user@example.com", password: "password123") }

  path "/session" do
    post "Creates a session" do
      tags "Authentication"
      consumes "application/json"
      produces "application/json"
      security []

      parameter name: :credentials, in: :body, schema: {
        type: :object,
        properties: {
          email_address: { type: :string, format: :email },
          password: { type: :string }
        },
        required: %w[email_address password]
      }

      response "201", "session created" do
        schema type: :object, properties: { token: { type: :string } }, required: %w[token]

        let(:credentials) { { email_address: "user@example.com", password: "password123" } }

        run_test! do |response|
          token = response.parsed_body["token"]

          expect(Session.find_signed(token, purpose: :session).user).to eq(user)
        end
      end

      response "401", "invalid credentials" do
        schema "$ref" => "#/components/schemas/error"

        let(:credentials) { { email_address: "user@example.com", password: "wrong" } }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "invalid credentials")
        end
      end

      response "429", "too many requests" do
        schema "$ref" => "#/components/schemas/error"

        let(:credentials) { { email_address: "user@example.com", password: "wrong" } }

        before do
          10.times do |n|
            post "/session", params: { email_address: "user#{n}@example.com", password: "wrong" }
          end
        end

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "too many requests")
        end
      end
    end

    delete "Destroys the current session" do
      tags "Authentication"
      produces "application/json"

      response "204", "session destroyed" do
        let(:Authorization) { auth_headers(user)["Authorization"] }

        run_test! do
          expect(Session.count).to eq(0)
        end
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/error"

        let(:Authorization) { nil }

        run_test! do |response|
          expect(response.parsed_body).to eq("error" => "unauthorized")
        end
      end
    end
  end

  describe "POST /session variants" do
    it "accepts an email with different case and whitespace" do
      post "/session", params: { email_address: "  USER@Example.com ", password: "password123" }

      expect(response).to have_http_status(:created)
    end

    it "rejects an unknown email" do
      post "/session", params: { email_address: "ghost@example.com", password: "password123" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "invalid credentials")
    end

    it "rejects an empty body" do
      post "/session", params: {}, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "invalid credentials")
    end

    it "rejects a missing password" do
      post "/session", params: { email_address: "user@example.com" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "invalid credentials")
    end

    it "rejects an array as email address" do
      post "/session", params: { email_address: [ "user@example.com", "junk@example.com" ], password: "password123" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq("error" => "invalid credentials")
    end

    it "limits attempts per IP" do
      10.times do |n|
        post "/session", params: { email_address: "user#{n}@example.com", password: "wrong" }
      end

      post "/session", params: { email_address: "user@example.com", password: "password123" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "limits attempts per email across different IPs" do
      10.times do |n|
        post "/session",
          params: { email_address: " USER@example.com ", password: "wrong" },
          env: { "REMOTE_ADDR" => "10.0.0.#{n + 1}" }
      end

      post "/session",
        params: { email_address: "user@example.com", password: "password123" },
        env: { "REMOTE_ADDR" => "10.0.1.1" }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "rate limits array emails under one shared key" do
      10.times do |n|
        post "/session",
          params: { email_address: [ "user@example.com", "junk#{n}@example.com" ], password: "wrong" },
          as: :json,
          env: { "REMOTE_ADDR" => "10.0.0.#{n + 1}" }
      end

      post "/session",
        params: { email_address: [ "user@example.com" ], password: "password123" },
        as: :json,
        env: { "REMOTE_ADDR" => "10.0.1.1" }

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "DELETE /session variants" do
    it "rejects a token reused after logout" do
      headers = auth_headers(user)
      delete "/session", headers: headers

      delete "/session", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "responds with a Bearer challenge when unauthorized" do
      delete "/session"

      expect(response.headers["WWW-Authenticate"]).to eq("Bearer")
    end

    it "rejects a non-Bearer scheme" do
      credentials = Base64.strict_encode64("user@example.com:password123")

      delete "/session", headers: { "Authorization" => "Basic #{credentials}" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a garbage token" do
      delete "/session", headers: { "Authorization" => "Bearer garbage" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a token just before it expires" do
      headers = auth_headers(user)

      travel_to((Session::LIFETIME - 1.minute).from_now)
      delete "/session", headers: headers

      expect(response).to have_http_status(:no_content)
    end

    it "rejects a token after it expires" do
      headers = auth_headers(user)

      travel_to((Session::LIFETIME + 1.minute).from_now)
      delete "/session", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
