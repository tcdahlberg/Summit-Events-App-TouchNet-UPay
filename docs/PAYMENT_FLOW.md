# TouchNet UPay Payment Flow

## Complete Payment Process

### Visual Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    USER STARTS IN SUMMIT EVENTS APP                 │
│                         (Event Registration)                        │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 │ Clicks "Proceed to Payment"
                                 │ (Registration saved in encrypted cookie)
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│               VISUALFORCE PAGE: UPayPayment.page                    │
│                  (UPayPaymentController.cls)                        │
├─────────────────────────────────────────────────────────────────────┤
│  1. Read encrypted cookie → Get registration context                │
│  2. Query event, fees, registrant data                              │
│  3. Calculate total amount                                          │
│  4. Create encrypted security token:                                │
│     {registrationId, eventId, timestamp, amount}                    │
│  5. Build POST parameters:                                          │
│     • UPAY_SITE_ID = site identifier                                │
│     • AMT = total amount                                            │
│     • EXT_TRANS_ID = "John Doe | Event | Date"                      │
│     • EXT_TRANS_ID_LABEL = "Payment for [Event Name]"               │
│     • SEA_SECURE = <encrypted security token> ⭐ PASSTHROUGH        │
│     • VALIDATION_KEY = MD5(key+transId+amt)                          │
│     • POST_LINK = /services/apexrest/upaypaymentreceive              │
│     • SUCCESS_LINK = /apex/UPayCallback?type=success                 │
│     • CANCEL_LINK = /apex/UPayCallback?type=cancel                   │
│     • ERROR_LINK = /apex/UPayCallback?type=error                     │
│  6. JavaScript builds hidden form                                    │
│  7. User clicks "Proceed to Payment"                                 │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 │ POST form to TouchNet
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     TOUCHNET UPAY GATEWAY                            │
│                    (External Payment Processor)                      │
├─────────────────────────────────────────────────────────────────────┤
│  1. Display payment form to user                                     │
│  2. User enters credit card information                              │
│  3. Process payment                                                  │
│  4. If SUCCESSFUL:                                                   │
│     ├─ POST payment results to POST_LINK (REST API) ───────┐         │
│     │  Body includes:                                       │        │
│     │  • pmt_status = "success"                             │        │
│     │  • pmt_amt = "150.00"                                 │        │
│     │  • pmt_date = "02/10/2026"                            │        │
│     │  • tpg_trans_id = "20260210000123"                    │        │
│     │  • SEA_SECURE = <encrypted token> (passthrough) ⭐    │        │
│     │  • card_type, billing info, etc.                      │        │
│     │                                                       │        │
│     └─ Wait for HTTP_OK response                            │        │
│     └─ Redirect user to SUCCESS_LINK                        │        │
│                                                             │        │
│  5. If CANCELLED:                                           │        │
│     └─ Redirect to CANCEL_LINK                              │        │
│                                                             │        │
│  6. If ERROR:                                               │        │
│     └─ Redirect to ERROR_LINK                               │        │
└──────────────────────────────────────────────────────────────────────┘
                                 │
                     ┌───────────┴────────────┐
                     │                        │
                     ▼                        ▼
     ┌───────────────────────────┐  ┌────────────────────────┐
     │   REST API ENDPOINT       │  │   USER REDIRECT        │
     │ UPayPaymentRest.cls       │  │   (in browser)         │
     │ /apexrest/upaypaymentreceive │  │                        │
     ├───────────────────────────┤  └────────┬───────────────┘
     │ 1. Receive POST from      │           │
     │    TouchNet               │           │
     │ 2. Decrypt security token │           │
     │ 3. Validate:              │           │
     │    • Token not expired    │           │
     │    • Registration valid   │           │
     │ 4. Check for duplicate    │           │
     │ 5. Create Payment record: │           │
     │    summit__Summit_Events_ │           │
     │    Payment__c             │           │
     │    • TouchnetReceiptNumber│           │
     │    • Payment_Amount       │           │
     │    • Payment_Received_Date│           │
     │    • Billing info         │           │
     │ 6. Update registration    │           │
     │    status = "Registered"  │           │
     │ 7. Return "HTTP_OK"       │           │
     └───────────────────────────┘           │
                                              │
                                              ▼
                    ┌─────────────────────────────────────────────────┐
                    │    VISUALFORCE PAGE: UPayCallback.page           │
                    │       (UPayCallbackController.cls)               │
                    ├─────────────────────────────────────────────────┤
                    │  1. Get transaction ID from URL params           │
                    │  2. Read registration from encrypted cookie      │
                    │  3. Query for payment record:                    │
                    │     WHERE TouchnetReceiptNumber = transactionId  │
                    │     AND Event_Registration = registrationId      │
                    │  4. If payment found:                            │
                    │     ✓ Display success message                    │
                    │     ✓ Show transaction ID                        │
                    │     ✓ Auto-redirect in 3 seconds                 │
                    │  5. If payment NOT found:                        │
                    │     • Retry query 3 times (timing issue)         │
                    │     • If still not found: show error             │
                    └────────────────────┬────────────────────────────┘
                                         │
                                         │ Auto-redirect (3 seconds)
                                         ▼
                    ┌─────────────────────────────────────────────────┐
                    │        SUMMIT EVENTS CONFIRMATION PAGE          │
                    │     (summit__SummitEventsConfirmation)          │
                    ├─────────────────────────────────────────────────┤
                    │  • Shows registration complete                  │
                    │  • Shows payment received                       │
                    │  • User journey complete ✓                      │
                    └─────────────────────────────────────────────────┘
```

## Key Points

### ⚠️ Proxy Server (REQUIRED)

**TouchNet requires static IP addresses** for REST API callbacks. Since Salesforce does not provide static IPs, a **proxy server is mandatory**.

**Architecture:**
```
TouchNet → Proxy Server (Static IPs) → Salesforce REST API
          AWS Lambda + NLB
          IPs: 54.x.x.x, 54.y.y.y
```

**What the proxy does:**
1. Receives POST from TouchNet with payment results
2. Forwards request to Salesforce REST endpoint (`/services/apexrest/upaypaymentreceive`)
3. Returns Salesforce's response back to TouchNet
4. Provides static IPs that TouchNet can whitelist

**Setup Required:**
- AWS Lambda function with NodeJS proxy code
- Network Load Balancer with Elastic IPs (static)
- SSL certificate for HTTPS
- TouchNet whitelist approval for your static IPs

**Complete setup instructions:** [PROXY_SETUP.md](PROXY_SETUP.md)

**POST_LINK Configuration:**
- ✅ Correct: `https://touchnet-proxy.yourschool.edu/services/apexrest/upaypaymentreceive`
- ❌ Wrong: `https://yourorg.my.salesforce.com/services/apexrest/upaypaymentreceive`

### 🔒 Security
- **SEA_SECURE Parameter:** Custom passthrough variable containing encrypted security token
  - TouchNet Gateway configured to accept SEA_SECURE as a custom parameter
  - Token contains: {registrationId, eventId, instanceId, timestamp, amount}
  - Passed to TouchNet during payment submission
  - TouchNet passes it back unchanged in the REST API callback
  - REST endpoint decrypts and validates token before creating payment
  - Prevents tampering: validates payment is for the correct registration and amount
- **Token Expiration:** 24-hour window prevents replay attacks
- **Duplicate Prevention:** REST API checks for existing payments by transaction ID
- **Validation Hash:** MD5 hash validates request came from authorized source

### ⚡ Asynchronous Flow
1. **REST API call** happens independently (TouchNet → Salesforce)
2. **User redirect** happens after REST call completes
3. **Callback page** verifies payment record exists (created by REST)

### 🛡️ Fault Tolerance
- Callback page retries payment lookup (handles timing issues)
- REST API returns HTTP_ERROR on validation failure
- TouchNet won't redirect user until REST API returns success

### 📝 Why This Architecture?

**Q: Why not create payment record in callback page?**  
**A:** TouchNet must receive confirmation from Salesforce before redirecting the user. The REST API provides this confirmation, then TouchNet redirects. If the callback page created the payment, TouchNet wouldn't know if it succeeded.

**Q: What if REST API fails but user gets redirected?**  
**A:** TouchNet shouldn't redirect unless REST API returns HTTP_OK. If this happens anyway, callback page will detect missing payment and show appropriate error.

**Q: What if REST API succeeds but user never reaches callback page?**  
**A:** Payment record still exists in Salesforce. User can return to SEA and see their registration is complete. No data loss.

## Implementation Notes

### Required Configuration
1. **Custom Metadata:** UPay site configuration
2. **Summit Events Settings:** Encryption key for cookies/tokens
3. **TouchNet Admin:** Configure POST_LINK to REST endpoint
4. **Permissions:** Guest user access to REST API and payment object

### Testing Strategy
1. Monitor debug logs for REST API (`UPayPaymentRest`)
2. Check payment records created with correct transaction IDs
3. Verify callback page finds payment record immediately
4. Test cancel/error scenarios
5. Test with expired security tokens (> 24 hours)

### Common Issues
- **REST API not called:** Check TouchNet POST URL configuration
- **Payment not found:** Check query criteria (transaction ID, registration ID)
- **HTTP_ERROR returned:** Check debug logs for validation failures
- **Duplicate payments:** REST API prevents, returns success for existing

---

**Version:** 1.0  
**Last Updated:** February 10, 2026  
**Author:** TouchNet UPay Integration Team

