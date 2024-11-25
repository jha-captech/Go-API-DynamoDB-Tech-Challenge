#!/bin/bash
url="http://localhost:8000"

table_name="BlogContent"
schema_file="table_schema.json"
data_file="batch_items.json"

# create table
echo "Creating table: $table_name"
aws dynamodb create-table \
    --cli-input-json "file://$schema_file" \
    --endpoint-url "$url" \
    --no-cli-pager


# seed table
echo "Seeding table: $table_name"

current_line=0
total_lines=$(wc -l < "$data_file")

while IFS= read -r line; do
    current_line=$((current_line+1))
    echo "Processing line $current_line of $total_lines"
    aws dynamodb batch-write-item \
        --request-items "$line" \
        --endpoint-url "$url" \
        --no-cli-pager
done < "$data_file"

