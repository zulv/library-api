json.partial! "readers/reader", reader: @reader
json.extract! @reader, :email, :created_at
