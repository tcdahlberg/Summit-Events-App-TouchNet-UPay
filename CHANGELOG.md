# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-12

### Initial Release

First production release of TouchNet UPay integration for Summit Events App.

#### Added

**Apex Classes**
- `UPayHelper` - Core encryption, configuration, and cookie management utilities
- `UPayPaymentController` - Payment page controller with auto-submit functionality
- `UPayPaymentRest` - REST API endpoint for TouchNet payment callbacks
- `UPayCallbackController` - Post-payment callback page controller
- `UPayHelper_TEST` - Comprehensive test coverage

**Visualforce Pages**
- `UPayPayment` - Auto-submit payment form with SLDS styling
- `UPayCallback` - Success/cancel/error callback handler with SLDS styling

**Custom Metadata**
- `TouchNet_UPay_Site__mdt` - Multi-site payment gateway configuration
  - Support for multiple TouchNet UPay sites
  - Named Credential integration
  - Active/inactive flags

**Security Features**
- SEA_SECURE encrypted token passthrough parameter
- AES256 encryption for payment context
- 24-hour token expiration
- MD5 validation key hashing
- Duplicate payment prevention

**Integration Features**
- Auto-submit payment forms (no user interaction required)
- Guest user support via `without sharing` DML operations
- Automatic fee linking to payment records
- Registration status updates on successful payment
- Multi-source registration ID retrieval (URL → Cookie → Default)

**Documentation**
- Complete setup guide (SETUP_GUIDE.md)
- AWS proxy server deployment guide (PROXY_SETUP.md)
- Manual field creation guide (FIELD_SETUP.md)
- Technical overview (TECHNICAL_OVERVIEW.md)
- Payment flow diagrams (PAYMENT_FLOW.md)
- Security implementation details (SECURITY.md)
- Release notes (RELEASE_NOTES.md)

**Developer Tools**
- CumulusCI configuration (cumulusci.yml)
- SFDX project configuration (sfdx-project.json)
- Test framework with 75%+ code coverage
- Debug logging throughout

#### Technical Details

**REST Endpoint**
- URL: `/services/apexrest/upaypaymentreceive`
- Method: POST
- Authentication: Site Guest User
- Response: HTTP_OK or HTTP_ERROR

**Payment Flow**
1. User registration → Payment page auto-submits → TouchNet gateway
2. TouchNet processes payment → POSTs to proxy → Proxy forwards to Salesforce
3. REST API validates token → Creates payment → Links fees → Updates registration
4. TouchNet redirects user → Callback page → Auto-redirect to confirmation

**Requirements**
- Summit Events App installed
- AWS proxy server (Lambda + NLB with static IPs)
- TouchNet UPay account with SEA_SECURE parameter configured
- Summit Events encryption key (32+ characters)
- Optional: UPay_Site__c picklist field on Summit Events

**Deployment**
- Unmanaged package
- Salesforce API version 65.0
- Compatible with all Salesforce editions supporting Apex and Visualforce
- Requires Experience Cloud for guest user payments

---

## Upcoming

Future releases may include:
- Lightning Web Component conversion
- Additional payment gateway support
- Enhanced reporting and analytics
- Automated retry logic for failed payments
- Payment plan support

---

**Legend:**
- `Added` - New features
- `Changed` - Changes in existing functionality
- `Deprecated` - Soon-to-be removed features
- `Removed` - Removed features
- `Fixed` - Bug fixes
- `Security` - Security improvements

