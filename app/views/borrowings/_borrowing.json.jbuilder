json.extract! borrowing, :id, :book_id, :borrowed_at, :due_on, :returned_at

if (reader = borrowing.identified_reader)
  json.reader { json.partial! "readers/reader", reader: }
else
  json.reader nil
end
