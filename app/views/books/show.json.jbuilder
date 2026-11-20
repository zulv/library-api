json.partial! "books/book", book: @book
json.borrowings @book.borrowing_history, partial: "borrowings/history_entry", as: :borrowing
