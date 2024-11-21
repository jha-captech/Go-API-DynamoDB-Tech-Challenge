#!/bin/bash
table_name="Content"

echo "Deleting all table in dynamodb"
aws dynamodb delete-table \
    --table-name "$table_name" \
    --endpoint-url http://localhost:8000 \
    --no-cli-pager