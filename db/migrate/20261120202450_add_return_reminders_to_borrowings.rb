class AddReturnRemindersToBorrowings < ActiveRecord::Migration[8.1]
  def change
    add_column :borrowings, :due_soon_reminder_sent_at, :datetime
    add_column :borrowings, :due_today_reminder_sent_at, :datetime
    add_index :borrowings, :due_on, where: "returned_at IS NULL", name: "index_borrowings_on_due_on_active"
  end
end
