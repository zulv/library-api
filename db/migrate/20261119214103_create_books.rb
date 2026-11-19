class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :serial_number, null: false
      t.string :title, null: false
      t.string :author, null: false
      t.datetime :discarded_at

      t.timestamps

      t.check_constraint "serial_number ~ '^[0-9]{6}$'", name: "books_serial_number_format"
    end
    add_index :books, :serial_number, unique: true
    add_index :books, :discarded_at
  end
end
