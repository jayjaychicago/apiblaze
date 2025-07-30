#!/bin/bash

# ApiBlaze Monitoring Script
# Usage: ./scripts/monitor.sh [option]
# Options:
#   costs      - Check AWS costs (default)
#   lambda     - Check Lambda function metrics
#   dynamodb   - Check DynamoDB metrics
#   api        - Check API Gateway metrics
#   all        - Check all metrics

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "SUCCESS")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# Check if we're in the right directory
if [ ! -f "main.tf" ]; then
    print_status "ERROR" "Please run this script from the terraform directory"
    exit 1
fi

# Get monitoring option
MONITOR_OPTION=${1:-costs}

echo "📊 ApiBlaze Monitoring Script"
echo "============================="
print_status "INFO" "Monitoring option: $MONITOR_OPTION"

# Get current date and 30 days ago
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date -d "30 days ago" +%Y-%m-%d)

case $MONITOR_OPTION in
    "costs"|"all")
        echo ""
        print_status "INFO" "Checking AWS costs for the last 30 days..."
        
        # Check if Cost Explorer is available
        if aws ce get-cost-and-usage --time-period Start="$START_DATE",End="$END_DATE" --granularity MONTHLY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE &> /dev/null; then
            print_status "SUCCESS" "Cost Explorer data available"
            
            # Get costs by service
            echo "Costs by service (last 30 days):"
            aws ce get-cost-and-usage \
                --time-period Start="$START_DATE",End="$END_DATE" \
                --granularity MONTHLY \
                --metrics BlendedCost \
                --group-by Type=DIMENSION,Key=SERVICE \
                --query 'ResultsByTime[0].Groups[?contains(Keys[0].Value, `Lambda`) || contains(Keys[0].Value, `DynamoDB`) || contains(Keys[0].Value, `API Gateway`) || contains(Keys[0].Value, `Cognito`) || contains(Keys[0].Value, `S3`)].{Service:Keys[0].Value,Cost:Metrics.BlendedCost.Amount}' \
                --output table
        else
            print_status "WARNING" "Cost Explorer not available or no cost data"
        fi
        ;;
esac

case $MONITOR_OPTION in
    "lambda"|"all")
        echo ""
        print_status "INFO" "Checking Lambda function metrics..."
        
        LAMBDA_FUNCTIONS=(
            "apiblaze-admin-api"
            "apiblaze-oauth-handler"
            "apiblaze-oauth-callback"
            "apiblaze-github-webhook"
            "apiblaze-config-change-handler"
        )
        
        for func in "${LAMBDA_FUNCTIONS[@]}"; do
            echo "Function: $func"
            
            # Get invocation count
            INVOCATIONS=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Invocations \
                --dimensions Name=FunctionName,Value="$func" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            # Get error count
            ERRORS=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Errors \
                --dimensions Name=FunctionName,Value="$func" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            # Get duration
            DURATION=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Duration \
                --dimensions Name=FunctionName,Value="$func" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[0].Average' \
                --output text 2>/dev/null || echo "0")
            
            print_status "INFO" "  Invocations: $INVOCATIONS"
            print_status "INFO" "  Errors: $ERRORS"
            print_status "INFO" "  Avg Duration: ${DURATION}ms"
            
            # Calculate error rate
            if [ "$INVOCATIONS" != "0" ] && [ "$INVOCATIONS" != "None" ]; then
                ERROR_RATE=$(echo "scale=2; $ERRORS * 100 / $INVOCATIONS" | bc 2>/dev/null || echo "0")
                print_status "INFO" "  Error Rate: ${ERROR_RATE}%"
            fi
            echo ""
        done
        ;;
esac

case $MONITOR_OPTION in
    "dynamodb"|"all")
        echo ""
        print_status "INFO" "Checking DynamoDB metrics..."
        
        DYNAMODB_TABLES=(
            "apiblaze-users"
            "apiblaze-customers"
            "apiblaze-api-keys"
            "apiblaze-user-project-access"
            "apiblaze-customer-oauth-configs"
        )
        
        for table in "${DYNAMODB_TABLES[@]}"; do
            echo "Table: $table"
            
            # Get consumed read capacity
            READ_CAPACITY=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/DynamoDB \
                --metric-name ConsumedReadCapacityUnits \
                --dimensions Name=TableName,Value="$table" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            # Get consumed write capacity
            WRITE_CAPACITY=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/DynamoDB \
                --metric-name ConsumedWriteCapacityUnits \
                --dimensions Name=TableName,Value="$table" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            # Get item count
            ITEM_COUNT=$(aws dynamodb describe-table --table-name "$table" --query 'Table.ItemCount' --output text 2>/dev/null || echo "0")
            
            print_status "INFO" "  Read Capacity: $READ_CAPACITY"
            print_status "INFO" "  Write Capacity: $WRITE_CAPACITY"
            print_status "INFO" "  Item Count: $ITEM_COUNT"
            echo ""
        done
        ;;
esac

case $MONITOR_OPTION in
    "api"|"all")
        echo ""
        print_status "INFO" "Checking API Gateway metrics..."
        
        # Get API Gateway ID
        API_GATEWAY_ID=$(aws apigateway get-rest-apis --query 'items[?contains(name, `apiblaze`)].id' --output text 2>/dev/null || echo "")
        
        if [ -n "$API_GATEWAY_ID" ]; then
            echo "API Gateway: $API_GATEWAY_ID"
            
            # Get request count
            REQUEST_COUNT=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApiGateway \
                --metric-name Count \
                --dimensions Name=ApiName,Value="$API_GATEWAY_ID" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            # Get 4xx errors
            ERROR_4XX=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApiGateway \
                --metric-name 4XXError \
                --dimensions Name=ApiName,Value="$API_GATEWAY_ID" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            # Get 5xx errors
            ERROR_5XX=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApiGateway \
                --metric-name 5XXError \
                --dimensions Name=ApiName,Value="$API_GATEWAY_ID" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text 2>/dev/null || echo "0")
            
            # Get latency
            LATENCY=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/ApiGateway \
                --metric-name Latency \
                --dimensions Name=ApiName,Value="$API_GATEWAY_ID" \
                --start-time "$START_DATE"T00:00:00Z \
                --end-time "$END_DATE"T23:59:59Z \
                --period 86400 \
                --statistics Average \
                --query 'Datapoints[0].Average' \
                --output text 2>/dev/null || echo "0")
            
            print_status "INFO" "  Request Count: $REQUEST_COUNT"
            print_status "INFO" "  4XX Errors: $ERROR_4XX"
            print_status "INFO" "  5XX Errors: $ERROR_5XX"
            print_status "INFO" "  Avg Latency: ${LATENCY}ms"
            
            # Calculate error rate
            if [ "$REQUEST_COUNT" != "0" ] && [ "$REQUEST_COUNT" != "None" ]; then
                TOTAL_ERRORS=$(echo "$ERROR_4XX + $ERROR_5XX" | bc 2>/dev/null || echo "0")
                ERROR_RATE=$(echo "scale=2; $TOTAL_ERRORS * 100 / $REQUEST_COUNT" | bc 2>/dev/null || echo "0")
                print_status "INFO" "  Error Rate: ${ERROR_RATE}%"
            fi
        else
            print_status "WARNING" "API Gateway not found"
        fi
        ;;
esac

echo ""
print_status "SUCCESS" "Monitoring completed!"
print_status "INFO" "For detailed cost analysis, visit AWS Cost Explorer in the console" 