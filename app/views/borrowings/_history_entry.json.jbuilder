json.extract! borrowing, :id, :borrowed_at, :due_on, :returned_at

if (reader = borrowing.identified_reader)
  json.reader { json.partial! "readers/reader_details", reader: }
else
  json.reader nil
end
