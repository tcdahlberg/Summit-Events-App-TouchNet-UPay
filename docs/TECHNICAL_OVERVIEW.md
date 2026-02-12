# TouchNet UPay Payment Gateway for Summit Events App

## Overview

This package provides a complete TouchNet UPay payment integration for Summit Events App (SEA). The implementation enables secure credit card payment processing through TouchNet's UPay gateway with support for multiple payment sites, encrypted security tokens, and comprehensive payment tracking.

## Features

- **Multiple UPay Sites** - Configure different TouchNet sites for different event types
- **Secure Token Validation** - AES256 encrypted passthrough tokens prevent fraud
- **Automatic Payment Processing** - Seamless redirect flow with no manual intervention required
- **Complete Audit Trail** - Full payment and fee tracking in Summit Events
- **Flexible Configuration** - Per-event UPay site selection via picklist field
- **Guest User Support** - Works with Experience Cloud guest users

## Architecture

### Components

#### Custom Metadata Type
- **TouchNet_UPay_Site__mdt** - Multi-site payment gateway configuration
  - Gateway URL and site identifiers
  - Validation keys (supports Named Credentials)
  - Active/inactive flags

#### Apex Classes
- **UPayHelper.cls** - Core encryption, cookie management, and configuration utilities
- **UPayPaymentController.cls** - Payment page controller, builds TouchNet POST parameters
- **UPayPaymentRest.cls** - REST API endpoint for TouchNet callbacks
- **UPayCallbackController.cls** - User-facing callback page controller
- **UPayHelper_TEST.cls** - Test coverage for helper utilities

#### Visualforce Pages
- **UPayPayment.page** - Auto-submit payment form (SLDS styled)
- **UPayCallback.page** - Success/cancel/error callback handler

#### REST Endpoint
- `/services/apexrest/upaypaymentreceive` - TouchNet POST callback endpoint

### Data Flow

1. **User Initiates Payment** → UPayPayment page
2. **Form Auto-Submits** → TouchNet UPay Gateway
3. **User Enters Payment** → TouchNet processes
4. **TouchNet POSTs Results** → Proxy Server → Salesforce REST API
5. **REST API Creates Payment** → Links to registration and fees
6. **TouchNet Redirects User** → UPayCallback page
7. **Callback Verifies Payment** → Redirects to confirmation

## Payment Processing Flow

### Phase 1: Payment Initiation
```
User → UPayPayment.page
  ├─ Reads registration context from encrypted cookie
  ├─ Queries event, instance, registration, fees
  ├─ Calculates total amount
  ├─ Creates SEA_SECURE encrypted token
  ├─ Builds POST parameters
  └─ Auto-submits to TouchNet
```

### Phase 2: TouchNet Processing
```
TouchNet UPay Gateway
  ├─ User enters credit card details
  ├─ Processes payment
  ├─ POSTs results to Proxy Server
  └─ Proxy forwards to Salesforce REST endpoint
```

### Phase 3: Payment Recording
```
UPayPaymentRest.cls (REST API)
  ├─ Validates SEA_SECURE token
  ├─ Creates Summit_Events_Payment__c record
  ├─ Links all fees to payment
  ├─ Updates registration status to "Registered"
  └─ Returns HTTP_OK to TouchNet
```

### Phase 4: User Confirmation
```
TouchNet → Redirects user → UPayCallback.page
  ├─ Retrieves registration ID from URL
  ├─ Queries for payment record
  ├─ Displays success message
  └─ Auto-redirects to Summit Events confirmation
```

## Security

### SEA_SECURE Token
Custom passthrough parameter containing encrypted payment context:
- Registration ID
- Event and Instance IDs
- Payment amount
- Timestamp (24-hour expiration)

**Encryption:** AES256 with managed IV using Summit Events encryption key

**Validation:** REST endpoint decrypts and validates before creating payment

### Permissions
- REST endpoint uses `without sharing` inner class for DML operations
- Enables guest user access from Experience Cloud sites
- All queries and updates execute with elevated permissions

### Duplicate Prevention
REST API checks for existing payments by transaction ID before creating new records

## Configuration

### Required Setup

1. **Proxy Server** (AWS Lambda + NLB with static IPs)
   - TouchNet requires static IPs for REST callbacks
   - See [PROXY_SETUP.md](PROXY_SETUP.md)

2. **Custom Metadata Records**
   - Create TouchNet_UPay_Site__mdt records for each payment site
   - Configure gateway URLs, site IDs, validation keys

3. **UPay Site Field** (Optional but Recommended)
   - Create picklist field `UPay_Site__c` on Summit Events object
   - Allows per-event site selection
   - See [FIELD_SETUP.md](FIELD_SETUP.md)

4. **TouchNet Configuration**
   - Add `SEA_SECURE` custom parameter
   - Configure POST_LINK to proxy server URL
   - Whitelist proxy server static IPs

5. **Summit Events Settings**
   - 32+ character encryption key configured
   - Community base URL configured

## Technical Specifications

### Apex Classes

**UPayHelper.cls**
- Security token generation and validation
- AES256 encryption/decryption
- Cookie management for registration context
- MD5 validation key hashing
- UPay site configuration retrieval

**UPayPaymentController.cls**
- Payment page controller
- Registration data queries
- Fee calculation
- POST parameter building
- SEA_SECURE token creation
- Callback URL generation with registration ID

**UPayPaymentRest.cls**
- REST resource (`@RestResource`)
- SEA_SECURE token validation
- Payment record creation
- Fee linking (sets `Summit_Events_Payment__c` on all fees)
- Registration status update
- Duplicate payment prevention
- `without sharing` DML operations

**UPayCallbackController.cls**
- Multi-source registration ID retrieval (URL → Cookie)
- Payment record verification
- Success/cancel/error state handling
- Auto-redirect on success

### Visualforce Pages

**UPayPayment.page**
- SLDS-styled loading spinner
- Hidden form generation via JavaScript
- Auto-submit (no user interaction required)
- Error display for configuration issues
- Session timeout detection

**UPayCallback.page**
- SLDS-styled status pages
- Transaction ID display
- Auto-redirect timer (3 seconds)
- Manual fallback links
- Different states: success, cancel, error

### Custom Metadata

**TouchNet_UPay_Site__mdt**

Fields:
- `UPay_Site_Id__c` - TouchNet site identifier
- `Gateway_URL__c` - TouchNet gateway endpoint
- `Validation_Key__c` - MD5 validation key
- `Named_Credential__c` - Optional named credential reference
- `Active__c` - Enable/disable flag

### REST API

**Endpoint:** `/services/apexrest/upaypaymentreceive`

**Method:** POST

**Content-Type:** application/x-www-form-urlencoded

**Parameters Received:**
- `pmt_status` - Payment status
- `tpg_trans_id` - TouchNet transaction ID
- `pmt_amt` - Payment amount
- `pmt_date` - Payment date
- `SEA_SECURE` - Encrypted security token
- `card_type` - Credit card type
- `name_on_acct` - Cardholder name
- Billing address fields
- Other TouchNet metadata

**Response:**
- `HTTP_OK` - Success
- `HTTP_ERROR` - Validation failure

## Deployment

### Package Contents
```
force-app/main/default/
├── classes/
│   ├── UPayHelper.cls
│   ├── UPayPaymentController.cls
│   ├── UPayPaymentRest.cls
│   ├── UPayCallbackController.cls
│   └── UPayHelper_TEST.cls
├── objects/
│   └── TouchNet_UPay_Site__mdt/
│       └── fields/
│           ├── Active__c.field-meta.xml
│           ├── Gateway_URL__c.field-meta.xml
│           ├── Named_Credential__c.field-meta.xml
│           ├── UPay_Site_Id__c.field-meta.xml
│           └── Validation_Key__c.field-meta.xml
└── pages/
    ├── UPayPayment.page
    └── UPayCallback.page
```

### Installation

```powershell
# Deploy all components
cci flow run dev_org --org dev

# Or deploy incrementally
cci task run deploy --path force-app/main/default/classes --org dev
cci task run deploy --path force-app/main/default/objects --org dev
cci task run deploy --path force-app/main/default/pages --org dev
```

### Post-Installation

1. Deploy AWS proxy server ([PROXY_SETUP.md](PROXY_SETUP.md))
2. Create UPay_Site__c field on Summit Events ([FIELD_SETUP.md](FIELD_SETUP.md))
3. Create Custom Metadata records
4. Configure TouchNet gateway
5. Test end-to-end payment flow

## Testing

### Test Coverage
- UPayHelper_TEST.cls provides comprehensive test coverage
- Tests encryption, decryption, token validation
- Tests expired token rejection
- Tests validation key hashing

### Manual Testing Checklist
- [ ] Payment page loads without errors
- [ ] Form auto-submits to TouchNet
- [ ] TouchNet processes test payment
- [ ] REST endpoint creates payment record
- [ ] All fees linked to payment
- [ ] Registration status updated
- [ ] Callback page shows success
- [ ] Auto-redirect to confirmation works

## Troubleshooting

### Payment Not Created
**Cause:** TouchNet POST_LINK not configured or proxy not deployed  
**Solution:** Verify proxy server is running and TouchNet has POST_LINK set

### Invalid Security Token
**Cause:** SEA_SECURE parameter not configured in TouchNet  
**Solution:** Add SEA_SECURE as custom parameter in TouchNet admin portal

### Guest User Permissions
**Cause:** Guest user cannot access Visualforce pages or create records  
**Solution:** Grant guest user access to pages; REST API uses `without sharing`

### Payment Found but Fees Not Linked
**Cause:** Fee query/update must run with elevated permissions  
**Solution:** All fee operations are in `without sharing` inner class

## Best Practices

### Security
- Use Named Credentials for validation keys in production
- Rotate encryption keys periodically
- Monitor failed payment attempts
- Review payment records regularly for anomalies

### Performance
- Payment pages load and auto-submit quickly
- Minimal server round-trips
- Efficient SOQL queries (bulk processing)

### Maintenance
- Keep TouchNet IP whitelist current
- Monitor proxy server CloudWatch logs
- Test after Salesforce releases
- Keep documentation updated

## Support

### Documentation
- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Step-by-step configuration
- [PROXY_SETUP.md](PROXY_SETUP.md) - AWS proxy deployment
- [SECURITY.md](SECURITY.md) - Security implementation details
- [PAYMENT_FLOW.md](PAYMENT_FLOW.md) - Detailed flow diagrams

### Debug Logs
- Filter by `UPayPaymentRest` for REST API calls
- Filter by `UPayCallback` for redirect issues
- Check for SEA_SECURE validation messages

### Common Issues
- Missing SEA_SECURE → Check TouchNet configuration
- Static IP required → Deploy proxy server
- Guest user errors → Check `without sharing` usage
- Duplicate payments → Check transaction ID uniqueness

## Version Information

**Version:** 1.0  
**Release Date:** February 2026  
**API Version:** 65.0  
**Dependencies:** Summit Events App


---

**Next Steps:** See [SETUP_GUIDE.md](SETUP_GUIDE.md) to begin installation and configuration.

