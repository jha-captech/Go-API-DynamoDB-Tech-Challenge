#!/bin/bash
table_name="BlogContent"

# export schema
echo "Exporting schema for table: $table_name"
aws dynamodb describe-table \
    --table-name "$table_name" > table_schema_out.json \
    --endpoint-url http://localhost:8000

# convert schema to format that can be imported
jq <table_schema_out.json '.Table | {TableName, KeySchema, AttributeDefinitions} + (try {LocalSecondaryIndexes: [ .LocalSecondaryIndexes[] | {IndexName, KeySchema, Projection} ]} // {}) + (try {GlobalSecondaryIndexes: [ .GlobalSecondaryIndexes[] | {IndexName, KeySchema, Projection} ]} // {}) + {BillingMode: "PAY_PER_REQUEST"}' >table_schema.json
#jq '.Table' table_schema_out.json > table_schema.json

# export data
echo "Exporting data for table: $table_name"
aws dynamodb scan \
  --table-name "$table_name" \
  --endpoint-url http://localhost:8000 \
  --output json > data.json

# convert data to format that can be imported
echo "Converting data to importable format"
jq -c --arg table_name "$table_name" '.Items[] | {($table_name): [{PutRequest: {Item: .}}]}' data.json > batch_items.json
