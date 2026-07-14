class WebhookEndpoint < ApplicationRecord
  belongs_to :user

  serialize :events, coder: JSON, default: []
  encrypts :secret_digest

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :secret_digest, presence: true
end
