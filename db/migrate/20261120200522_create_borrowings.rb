class CreateBorrowings < ActiveRecord::Migration[8.1]
  def change
    create_table :borrowings, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :book, null: false, foreign_key: { on_delete: :restrict }, type: :uuid
      t.references :reader, foreign_key: { on_delete: :restrict }, type: :uuid
      t.datetime :borrowed_at, null: false
      t.date :due_on, null: false
      t.datetime :returned_at

      t.timestamps

      t.check_constraint "returned_at IS NULL OR returned_at >= borrowed_at", name: "borrowings_returned_after_borrowed"
    end
    add_index :borrowings, :book_id, unique: true, where: "returned_at IS NULL", name: "index_borrowings_on_book_id_active"
  end
end
