# TouchNet UPay Integration - Recommendations Based on Technical Guide

## Summary

After reviewing the official TouchNet UPay Technical Guide, our current implementation covers the core functionality well. Below are recommendations for enhancements and additional features.

## Current Implementation Status: ✅ GOOD

### What We're Doing Right:
1. ✅ **Core Payment Parameters** - All essential parameters (UPAY_SITE_ID, AMT, EXT_TRANS_ID)
2. ✅ **Billing Information** - Complete address pass-through
3. ✅ **Security** - Encrypted validation using SEA_SECURE parameter
4. ✅ **Callback Handling** - REST endpoint properly captures payment data
5. ✅ **Named Credentials Support** - Secure storage of validation keys
6. ✅ **Multiple UPay Sites** - Custom metadata configuration

## Recommended Enhancements

### Priority 1: High Value, Low Effort

#### 1. Add EXT_TRANS_ID_LABEL Parameter
**Benefit:** Provides friendly description on TouchNet receipts
**Implementation:**
```apex
// In UPayPaymentController.buildPaymentParameters()
parameters.put('EXT_TRANS_ID_LABEL', 'Summit Events Registration');
// Or make this configurable in custom metadata
```

#### 2. Add Link Text Customization
**Benefit:** Better UX with customized link text
**Implementation:**
```apex
// Add to custom metadata fields:
// - Success_Link_Text__c
// - Error_Link_Text__c  
// - Cancel_Link_Text__c
// - Continue_Link_Text__c

// Then pass to UPay:
parameters.put('SUCCESS_LINK_TEXT', siteConfig.Success_Link_Text__c);
parameters.put('ERROR_LINK_TEXT', siteConfig.Error_Link_Text__c);
parameters.put('CANCEL_LINK_TEXT', siteConfig.Cancel_Link_Text__c);
```

#### 3. Capture sys_tracking_id from Callback
**Benefit:** Full traceability with TouchNet's internal order ID
**Implementation:**
```apex
// In UPayPaymentRest.cls, add to payment record:
payment.Marketplace_Order_ID__c = paymentData.get('sys_tracking_id');
```

### Priority 2: Medium Value

#### 4. Add Accounting Code Support
**Benefit:** Enables GL integration for institutions that need it
**Implementation:**
```apex
// Add to custom metadata:
// - Credit_Account_Code__c
// - Debit_Account_Code__c

// Pass to UPay:
if (String.isNotBlank(siteConfig.Credit_Account_Code__c)) {
    parameters.put('CREDIT_ACCT_CODE', siteConfig.Credit_Account_Code__c);
}
```

#### 5. Capture Additional Address Fields
**Benefit:** Complete customer data for reporting
**Currently captured:** Name, email, amount, transaction ID
**Should also capture:**
- `acct_addr`, `acct_addr2`, `acct_city`, `acct_state`, `acct_zip`, `acct_country`
- `acct_phone_day`, `acct_phone_night`, `acct_phone_mobile`

**Implementation:** Add fields to Summit_Events_Payment__c or create related record

#### 6. Support ADD_ON_OFFER_DISABLED
**Benefit:** Control donation prompts per event
**Implementation:**
```apex
// Add to Event object: Disable_Donation_Prompt__c
// Pass to UPay:
if (event.Disable_Donation_Prompt__c) {
    parameters.put('ADD_ON_OFFER_DISABLED', 'true');
}
```

### Priority 3: Advanced Features (Future)

#### 7. ACH Payment Support
**Benefit:** Lower transaction fees for customers paying via bank account
**Requirements:**
- Add SSV (Shared Secret Value) support
- Update UI to collect SSV and prompt
- NACHA compliance considerations

#### 8. Recurring Payments Support
**Benefit:** Subscription-based event fees
**Requirements:**
- Extensive changes to data model
- Scheduled payment tracking
- Multiple callback handling
**Recommendation:** Only if there's a business case (season tickets, installment payments, etc.)

#### 9. Multiple Accounting Codes
**Benefit:** Split payments across GL accounts
**Requirements:**
- Support for CREDIT_ACCT_CODE_2, CREDIT_ACCT_AMT_2, etc.
- UI for configuring splits
**Recommendation:** Only if institution requires it

## Fields to Add to Custom Metadata

### TouchNet_UPay_Site__mdt Enhancements:
```xml
<!-- User Experience -->
<field>
    <fullName>EXT_TRANS_ID_Label__c</fullName>
    <label>Transaction ID Label</label>
    <type>Text</type>
    <length>255</length>
    <defaultValue>Summit Events Registration</defaultValue>
</field>

<field>
    <fullName>Success_Link_Text__c</fullName>
    <label>Success Link Text</label>
    <type>Text</type>
    <length>255</length>
    <defaultValue>Return to Event Registration</defaultValue>
</field>

<field>
    <fullName>Error_Link_Text__c</fullName>
    <label>Error Link Text</label>
    <type>Text</type>
    <length>255</length>
    <defaultValue>Return to Event Registration</defaultValue>
</field>

<field>
    <fullName>Cancel_Link_Text__c</fullName>
    <label>Cancel Link Text</label>
    <type>Text</type>
    <length>255</length>
    <defaultValue>Return to Event Registration</defaultValue>
</field>

<!-- Accounting -->
<field>
    <fullName>Credit_Account_Code__c</fullName>
    <label>Credit Account Code</label>
    <type>Text</type>
    <length>50</length>
</field>

<field>
    <fullName>Debit_Account_Code__c</fullName>
    <label>Debit Account Code</label>
    <type>Text</type>
    <length>50</length>
</field>

<!-- Features -->
<field>
    <fullName>Disable_Donations__c</fullName>
    <label>Disable Additional Donations</label>
    <type>Checkbox</type>
    <defaultValue>false</defaultValue>
</field>
```

## Fields to Add to Summit_Events_Payment__c

```xml
<field>
    <fullName>Marketplace_Order_ID__c</fullName>
    <label>TouchNet Order ID</label>
    <type>Text</type>
    <length>50</length>
</field>

<field>
    <fullName>Billing_Address__c</fullName>
    <label>Billing Address</label>
    <type>TextArea</type>
</field>

<field>
    <fullName>Billing_City__c</fullName>
    <label>Billing City</label>
    <type>Text</type>
    <length>35</length>
</field>

<field>
    <fullName>Billing_State__c</fullName>
    <label>Billing State</label>
    <type>Text</type>
    <length>2</length>
</field>

<field>
    <fullName>Billing_Postal_Code__c</fullName>
    <label>Billing Postal Code</label>
    <type>Text</type>
    <length>30</length>
</field>

<field>
    <fullName>Billing_Country__c</fullName>
    <label>Billing Country</label>
    <type>Text</type>
    <length>2</length>
</field>

<field>
    <fullName>Phone_Day__c</fullName>
    <label>Daytime Phone</label>
    <type>Phone</type>
</field>

<field>
    <fullName>Phone_Evening__c</fullName>
    <label>Evening Phone</label>
    <type>Phone</type>
</field>

<field>
    <fullName>Phone_Mobile__c</fullName>
    <label>Mobile Phone</label>
    <type>Phone</type>
</field>
```

## Implementation Priority

### Phase 1 (Quick Wins - 1-2 hours)
1. Add EXT_TRANS_ID_LABEL
2. Capture sys_tracking_id
3. Add link text parameters

### Phase 2 (If Needed - 4-8 hours)
1. Add accounting code support
2. Capture additional address/phone fields
3. Add donation control

### Phase 3 (Major Features - Future)
1. ACH payments
2. Recurring payments
3. Multiple accounting codes

## Conclusion

Our current implementation is **solid and production-ready**. The recommendations above are enhancements that add value but aren't critical for core functionality. Implement based on your institution's specific needs.

**Key Strengths of Current Implementation:**
- ✅ Secure payment processing with validation
- ✅ Multi-site support
- ✅ Proper error handling
- ✅ Clean data model
- ✅ Good test coverage

**Next Steps:**
1. Review Phase 1 enhancements with stakeholders
2. Determine if accounting codes are needed
3. Consider ACH/recurring payments based on business requirements

