json.partial! "books/book", book: @book

if (borrowing = @book.active_borrowing)
  json.current_borrowing { json.partial! "borrowings/history_entry", borrowing: }
else
  json.current_borrowing nil
end
