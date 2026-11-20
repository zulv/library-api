class AddRetentionIndexToBorrowings < ActiveRecord::Migration[8.1]
  def change
    add_index :borrowings, :returned_at, where: "returned_at IS NOT NULL AND reader_id IS NOT NULL", name: "index_borrowings_on_returned_at_with_reader"
  end
end
