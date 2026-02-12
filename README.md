# TouchNet UPay Integration for Summit Events App

Secure credit card payment processing for Summit Events App using TouchNet's UPay gateway.

[![Salesforce API](https://img.shields.io/badge/Salesforce-API%2065.0-blue.svg)](https://developer.salesforce.com)
[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)

## Quick Start

### 1. Deploy to Salesforce
```powershell
cci flow run dev_org --org dev
```

### 2. Set Up AWS Proxy Server
TouchNet requires static IP addresses. Deploy a proxy server using AWS Lambda + Network Load Balancer.

📖 **[Complete Proxy Setup Guide](docs/PROXY_SETUP.md)**

### 3. Configure TouchNet Gateway
- Add `SEA_SECURE` custom parameter
- Set POST_LINK to your proxy server URL
- Provide your static IPs for whitelisting

### 4. Test Payment Flow
Navigate to the payment page and complete a test transaction.

## Features

- ✅ **Secure Payment Processing** - AES256 encrypted tokens prevent fraud
- ✅ **Auto-Submit Payment Forms** - Seamless user experience
- ✅ **Multiple Payment Sites** - Support different TouchNet sites per event
- ✅ **Guest User Compatible** - Works with Experience Cloud
- ✅ **Complete Audit Trail** - Links payments to fees and registrations
- ✅ **Flexible Configuration** - Per-event site selection

## Requirements

### Infrastructure
- ⚠️ **AWS Proxy Server** - Lambda + NLB with static IPs ([PROXY_SETUP.md](docs/PROXY_SETUP.md))

### Salesforce
- Summit Events App installed
- Summit Events Settings configured with encryption key (32+ characters)
- `UPay_Site__c` picklist field on Summit Events object ([FIELD_SETUP.md](docs/FIELD_SETUP.md))

### TouchNet
- Active UPay account
- Site credentials (Site ID, Gateway URL, Validation Key)
- `SEA_SECURE` custom parameter configured
- Static IPs whitelisted

## Documentation

| Document | Description |
|----------|-------------|
| **[SETUP_GUIDE.md](docs/SETUP_GUIDE.md)** | Complete installation and configuration guide |
| **[PROXY_SETUP.md](docs/PROXY_SETUP.md)** | AWS proxy server deployment (required) |
| **[FIELD_SETUP.md](docs/FIELD_SETUP.md)** | Manual field creation on Summit Events |
| **[TECHNICAL_OVERVIEW.md](docs/TECHNICAL_OVERVIEW.md)** | Architecture and technical specifications |
| **[PAYMENT_FLOW.md](docs/PAYMENT_FLOW.md)** | Visual payment flow diagrams |
| **[SECURITY.md](docs/SECURITY.md)** | Security implementation details |

## Architecture

```
┌─────────────┐
│ User Browser │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Salesforce      │
│ Payment Page    │ → Auto-submits to TouchNet
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ TouchNet UPay   │
│ Gateway         │ → User enters payment
└──────┬──────────┘
       │
       ├─ POST → ┌──────────────┐
       │          │ AWS Proxy    │ → Forwards to Salesforce REST API
       │          │ (Static IPs) │
       │          └──────────────┘
       │                  │
       │                  ▼
       │          ┌──────────────┐
       │          │ Salesforce   │
       │          │ REST API     │ → Creates payment + links fees
       │          └──────────────┘
       │
       └─ Redirect User → ┌──────────────┐
                          │ Callback Page │ → Shows confirmation
                          └──────────────┘
```

## Components

### Apex Classes
- `UPayHelper` - Encryption, configuration, utilities
- `UPayPaymentController` - Payment page controller
- `UPayPaymentRest` - REST API for TouchNet callbacks
- `UPayCallbackController` - Callback page controller
- `UPayHelper_TEST` - Test coverage

### Visualforce Pages
- `UPayPayment` - Auto-submit payment form
- `UPayCallback` - Success/cancel/error callback

### Custom Metadata
- `TouchNet_UPay_Site__mdt` - Payment site configuration

### REST Endpoint
- `/services/apexrest/upaypaymentreceive` - Payment callback handler

## Security

### SEA_SECURE Token
- AES256 encrypted passthrough parameter
- Contains: registration ID, event ID, amount, timestamp
- 24-hour expiration
- Prevents payment fraud and tampering

### Permission Model
- REST endpoint uses `without sharing` for guest user support
- All DML operations isolated to secure inner class
- Cookie encryption for registration context

### Validation
- Token expiration check
- Duplicate payment prevention
- Registration and amount validation

## How It Works

1. **User registers** for event in Summit Events
2. **Clicks payment link** → UPayPayment page loads
3. **Page auto-submits** → User goes directly to TouchNet
4. **User pays** on TouchNet gateway
5. **TouchNet POSTs** payment results → Proxy → Salesforce REST API
6. **REST API creates** payment record and links fees
7. **TouchNet redirects** user → Callback page
8. **Callback shows** success message and redirects to confirmation

**User sees:** Event registration → Payment gateway → Success confirmation  
**Behind the scenes:** Encrypted tokens, REST callbacks, payment linking

## Installation

### 1. Deploy Code
```powershell
# Full deployment
cci flow run dev_org --org dev

# Or incremental
cci task run deploy --path force-app/main/default/classes --org dev
cci task run deploy --path force-app/main/default/objects --org dev
cci task run deploy --path force-app/main/default/pages --org dev
```

### 2. Create UPay Site Field
Create `UPay_Site__c` picklist field on Summit Events object.

**See:** [FIELD_SETUP.md](docs/FIELD_SETUP.md)

### 3. Deploy Proxy Server
Deploy AWS Lambda + Network Load Balancer with static IPs.

**See:** [PROXY_SETUP.md](docs/PROXY_SETUP.md)

### 4. Create Custom Metadata
Setup → Custom Metadata Types → TouchNet UPay Site → New

**Required fields:**
- Label: "Event Registration"
- UPay Site ID: Your TouchNet site ID
- Gateway URL: TouchNet gateway endpoint
- Validation Key: Your validation key
- Active: ✓

### 5. Configure TouchNet
In TouchNet UPay Admin Portal:

1. Add custom parameter: `SEA_SECURE` (passthrough variable)
2. Set POST_LINK: `https://your-proxy.com/services/apexrest/upaypaymentreceive`
3. Request IP whitelist for your proxy server IPs

### 6. Test
Create test event, register, and complete test payment.

## Testing

### Run Tests
```powershell
# All tests
cci task run run_tests --org dev

# Specific test
cci task run run_tests --org dev --test_name_match UPayHelper_TEST

# Check coverage
sf data query --query "SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate WHERE ApexClassOrTrigger.Name LIKE 'UPay%'" --target-org YourOrg__dev --result-format human
```

### Manual Test Checklist
- [ ] Payment page loads and auto-submits
- [ ] TouchNet processes test payment
- [ ] Payment record created in Salesforce
- [ ] Fees linked to payment
- [ ] Registration status = "Registered"
- [ ] Callback page shows success
- [ ] Auto-redirect to confirmation

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Payment not created | Check proxy server is running, verify TouchNet POST_LINK |
| "Invalid security token" | Configure `SEA_SECURE` in TouchNet admin portal |
| Static IP required | Deploy proxy server ([PROXY_SETUP.md](docs/PROXY_SETUP.md)) |
| Guest user errors | Verify `without sharing` in REST class |
| Fees not linked | Check fee update in PaymentCRUD inner class |

**Debug Logs:** Filter by `UPayPaymentRest` or `UPayCallback`

## Cost Estimate

### AWS Proxy Server
- Lambda: $0-5/month (1M requests free)
- Network Load Balancer: ~$16/month
- Elastic IPs: ~$4/month
- **Total: ~$20-40/month**

### Salesforce
- No additional Salesforce costs
- Uses standard Summit Events license

## Support

**Documentation Issues:** Check the `/docs` folder

**TouchNet Issues:** Contact your TouchNet representative

**Salesforce Issues:** Review debug logs, check permissions

**Proxy Issues:** Check AWS CloudWatch logs

## Contributing

This project is maintained by Thaddaeus Dahlberg.

## Acknowledgments

- Built for Summit Events App
- Integrates with TouchNet UPay Gateway
- AWS proxy architecture pattern

---

**Version:** 1.0  
**Released:** February 2026  
**Salesforce API:** 65.0

