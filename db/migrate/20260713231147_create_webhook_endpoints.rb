class CreateWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.references :user, null: false, foreign_key: true
      t.string    :url,            null: false
      t.string    :secret_digest,  null: false
      t.boolean   :active,         null: false, default: true
      t.text      :events

      t.timestamps
    end
  end
end
