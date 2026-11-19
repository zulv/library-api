class CreateReaders < ActiveRecord::Migration[8.1]
  def change
    create_table :readers, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :card_number
      t.string :full_name
      t.string :email
      t.datetime :anonymized_at

      t.timestamps

      t.check_constraint "card_number ~ '^[0-9]{6}$'", name: "readers_card_number_format"
      t.check_constraint "anonymized_at IS NOT NULL OR (card_number IS NOT NULL AND full_name IS NOT NULL AND email IS NOT NULL)",
        name: "readers_identity_present_unless_anonymized"
    end
    add_index :readers, :card_number, unique: true
    add_index :readers, :email, unique: true
  end
end
