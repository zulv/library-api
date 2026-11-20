json.partial! "readers/reader_details", reader: @reader
json.extract! @reader, :created_at
